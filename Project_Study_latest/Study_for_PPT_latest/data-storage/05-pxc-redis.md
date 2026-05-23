# 05. PXC + Redis Sentinel — 데이터 레이어

> ⭐ **한 줄 요약**: **Percona XtraDB Cluster (PXC) 3-node**가 primary DB로 Galera 동기 복제를 한다 (Percona Operator로 자동 관리). **Redis Sentinel 3-node**가 캐시/세션/queue를 담당. 둘 다 K8s 위에서 HA를 구현하고 anti-affinity로 강제 분산된다.

---

## 🎯 우리가 한 선택

### PXC (Percona XtraDB Cluster)

PXC는 MySQL fork인 Percona Server에 Galera 동기 복제를 더한 클러스터다. Percona Operator로 K8s 위에서 자동 관리되고, 앞단에 ProxySQL이 있어 read/write split + connection pooling을 담당한다.

| 항목 | 값 |
|---|---|
| Operator | Percona XtraDB Cluster Operator |
| Cluster name | `kosa-pxc` |
| Namespace | `pii-protected` |
| PXC nodes | 3 (`kosa-pxc-pxc-0/1/2`) |
| ProxySQL nodes | 2 (`kosa-pxc-proxysql-0/1`) |
| Replication | **Galera 동기 복제** (write 모든 노드 commit 보장) |
| Storage | RBD PVC per node |
| Service endpoint | `kosa-pxc-proxysql.pii-protected` |

namespace 이름이 `pii-protected`인 게 의도적이다. PII (Personally Identifiable Information) 데이터를 다루는 영역이라는 표시로, NetworkPolicy로 격리하고 향후 보안 강화 시 우선 적용 대상이 된다.

### Redis Sentinel

Redis는 cache + session + queue 용도로 쓴다. Sentinel HA 구성으로 3-node quorum이라 노드 1대 죽어도 자동 failover된다.

| 항목 | 값 |
|---|---|
| Helm chart | bitnami/redis (Sentinel HA) |
| Namespace | `redis` |
| Nodes | 3 (`kosa-redis-node-0/1/2`) |
| Sentinel | 3 (각 node와 colocated) |
| Replication | async, master-replica |
| Quorum | 2 (3 중 2가 동의해야 failover) |

---

## 🔍 고려한 대안들

### DB — PXC vs PostgreSQL HA vs MongoDB vs DynamoDB

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **PXC (선택)** | Galera 동기 복제 (강한 일관성), MySQL 호환, Operator | Galera 한계 (write throughput), schema lock 까다로움 | ★★★★ |
| PostgreSQL + Patroni | 가장 강력한 DB, MVCC | replication 비동기, Patroni 학습 곡선 | ★★★★ |
| MongoDB Replica Set | document DB, schema-less | 우리 PII 데이터는 SQL 적합, MongoDB 운영 부담 | ★★ |
| AWS DynamoDB | 관리형, 무한 확장 | AWS lock-in, 온프레 X | ★ |
| Vitess | MySQL sharding | 매우 무거움, K8s 운영 부담 ★★★★★ | ★ |

DB 선택은 워크로드 특성에 강하게 의존한다. 우리는 PII 데이터를 다루므로 **강한 일관성과 SQL의 ACID 보장**이 필요했다.

**PXC**는 MySQL 호환 + Galera 동기 복제로 강한 일관성을 보장한다. Write가 모든 노드에 commit된 후 client에게 ACK를 보내니, read after write가 무조건 보장된다. 단점은 Galera 한계로 write throughput에 ceiling이 있고 (모든 노드 commit 대기), schema migration이 까다롭다.

**PostgreSQL + Patroni**는 강력한 대안이다. MVCC, JSONB, 풍부한 기능. 단점은 native replication이 async라 data loss 가능성이 있고, Patroni라는 별도 도구의 학습 곡선이 있다. MySQL에 익숙한 우리 팀엔 PXC가 자연스러웠다.

**MongoDB**는 schema-less 매력이 있지만 PII 데이터의 정규화에는 SQL이 맞다. **DynamoDB**는 관리형이지만 온프레 환경엔 부적합. **Vitess**는 진짜 수평 확장 (sharding)이 가능하지만 매우 무겁다.

### Cache — Redis vs Memcached vs DragonflyDB

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Redis Sentinel (선택)** | 사실상 표준, persistence + pub/sub | single-thread (CPU bound 가능) | ★★★★★ |
| Memcached | 가장 빠름 (multi-thread) | persistence X, 기능 적음 | ★★★ |
| DragonflyDB | Redis 호환 + multi-thread | 신규, 사례 적음 | ★★★ |
| Redis Cluster | 진짜 sharding | 더 복잡, slot 관리 | ★★★ (확장 시) |

Redis는 cache 영역의 사실상 표준이다. **Memcached가 multi-thread라 더 빠르지만**, persistence가 없어 재시작 시 데이터 휘발이고, pub/sub/list 같은 자료 구조도 없다. **DragonflyDB**는 Redis 호환 + multi-thread를 표방하는 신규 솔루션인데 production 사례가 적어 보류했다.

**Redis Sentinel vs Cluster** 차이가 헷갈리기 쉬운데, Sentinel = master-replica HA (3-5 node quorum), Cluster = sharding (16384 slot 분산)이다. 우리 데이터 양이 작아서 sharding 필요 없으니 Sentinel이 단순해서 좋다.

### PXC 설치 방식 — Operator vs Helm vs 수동

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Percona Operator (선택)** | 공식, 자동 backup/restore, monitoring | Operator 자체 운영 | ★★★★★ |
| bitnami Helm | 단순 | HA 약함, operator 기능 없음 | ★★★ |
| 수동 설치 (StatefulSet) | 통제 ★★★★★ | 자동화 0 | ★ |

**Percona Operator**는 공식 K8s operator로 PXC 클러스터를 declarative하게 관리한다. Galera 부트스트랩, 노드 추가/제거, backup/restore, upgrade 등이 모두 CR (Custom Resource)로 자동화된다. bitnami helm chart도 MySQL을 K8s에 깔지만 HA가 약하고 operator-level 자동화가 없다.

---

## 💡 왜 이걸 선택했나

### PXC를 고른 네 가지 이유

**첫째, MySQL 호환이라 학습 자료가 풍부**하다. 가장 보편적인 SQL DB라 개발자가 익숙하고, 마이그레이션도 쉽다.

**둘째, Galera 동기 복제로 강한 일관성**을 보장한다. PII 데이터의 정확성이 중요한데, async replication이면 master 장애 시 데이터 손실 위험이 있다. Galera는 write 시점에 모든 노드 commit을 보장한다.

**셋째, Percona Operator의 자동화**가 강력하다. 노드 추가/제거, backup, monitoring이 모두 declarative하게 동작한다. 사람 개입 최소화.

**넷째, ProxySQL 통합**으로 read/write split이 자동이다. App은 endpoint 1개만 알면 되고, ProxySQL이 알아서 read는 replica로, write는 master로 보낸다. connection pooling도 자동.

### Redis Sentinel을 고른 세 가지 이유

**첫째, 사실상 표준이다.** cache, session, queue, pub/sub 모두 Redis가 표준 도구다. 자료가 풍부하고 학습 곡선이 낮다.

**둘째, Sentinel = 단순 HA**다. Cluster (sharding)보다 학습이 쉽고, 우리 데이터 양엔 sharding이 불필요하다.

**셋째, 3-node = 진짜 quorum**이다. 2-node 구성은 SPoF (1대 죽으면 quorum 깨짐). 3-node면 1대 죽어도 2/3 quorum 유지로 자동 failover가 정상 작동한다.

---

## 💰 비용 분석

### 자원 사용

| 컴포넌트 | CPU | RAM | Storage |
|---|---|---|---|
| PXC × 3 | 1 vCPU × 3 | 2GB × 3 = 6GB | 20GB × 3 = 60GB |
| ProxySQL × 2 | 0.5 vCPU × 2 | 1GB × 2 = 2GB | 5GB × 2 = 10GB |
| Redis × 3 | 0.3 vCPU × 3 | 512MB × 3 = 1.5GB | 5GB × 3 = 15GB |
| **합계** | **~5 vCPU** | **~10 GB** | **85 GB** |

Worker 노드 3대 (각 6GB RAM)에 분산하면 노드당 약 50% 사용률이라 안정적이다.

### 자체 vs 관리형 비교

| 옵션 | 월 비용 |
|---|---|
| **우리 (자체 K8s)** | ~₩0 (자원 amortize) |
| AWS RDS Aurora MySQL HA 3-node | ~$300/월 |
| Google Cloud SQL HA | ~$250/월 |
| AWS ElastiCache Redis 3-node | ~$60/월 |

→ 자체 운영이 **월 ₩40만+ 절감**. 운영 부담은 늘지만 학습 + 데이터 주권 측면에서 가치 있다.

---

## ⚖️ Trade-off

### PXC 선택

| 얻은 것 | 잃은 것 |
|---|---|
| 동기 복제 (강한 일관성) | write throughput 한계 (모든 노드 commit 대기) |
| MySQL 호환 | Galera schema lock 까다로움 |
| Operator 자동화 | Operator 학습 |

PXC의 가장 큰 약점은 **write throughput ceiling**이다. Galera는 write 시점에 모든 노드 commit을 기다리니, 한 write의 latency가 단일 DB보다 느리다. throughput도 모든 노드 처리 능력의 평균에 묶인다. 우리 워크로드 규모엔 충분하지만, 진짜 high-write 환경 (수만 TPS+)에는 Vitess 같은 sharding 솔루션이 필요할 수 있다.

### Redis Sentinel 선택

| 얻은 것 | 잃은 것 |
|---|---|
| 자동 failover | sharding X (단일 노드 용량 한계) |
| 3-node quorum | replicas 동기화 async (data loss 가능) |

Redis는 **async replication**이라 master에 write 후 즉시 ACK가 가고, replica로 비동기 전파된다. master가 갑자기 죽으면 transit 중인 write는 손실 가능. cache 용도엔 OK이지만, queue로 쓰면 메시지 손실 위험이 있다.

---

## ⚠️ SPoF + 회복

### PXC

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **PXC node 1 죽음** | 2/3 quorum → write 가능 | 자동 (Operator가 새 Pod 생성) |
| **PXC node 2 죽음** | 1/3 → quorum loss → write 차단 (read만) | 긴급 — 1대라도 살리기 |
| **ProxySQL 죽음 (1/2)** | 다른 ProxySQL이 받음 | 자동 |
| **DB 데이터 손실** | 백업에서 복구 | xtrabackup restore |

PXC node 2대가 동시에 죽는 시나리오가 가장 위험하다. Galera quorum 1/3 → write 차단되고, **split-brain 위험으로 read조차 차단**될 수 있다. 다행히 anti-affinity로 노드들이 다른 워커에 분산돼 있어 (w1/w2/w3) 동시 사고 확률이 낮다.

### Redis

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Redis master 죽음** | Sentinel 자동 failover (수초) → 다른 replica 승격 | 자동 |
| **Sentinel quorum loss (3 중 2 죽음)** | failover 불가 | 1대라도 살리기 |
| **persistence 데이터 손실** | 캐시 휘발 | 앱이 다시 채움 |

Redis master 죽음은 가장 흔한 시나리오인데 **Sentinel이 수 초 내 자동 failover**한다. client (앱)는 잠시 connection 끊기지만 재연결 시 새 master로 자동 전환된다.

---

## 🚀 확장 가능성

### Option A: ⭐ PXC backup 자동화 (xtrabackup → S3)

**현재 자동 백업이 없다 — 가장 큰 약점.** Percona Operator의 backup 기능을 활성화하면 PerconaXtraDBClusterBackup CR로 schedule + S3 저장이 자동화된다. Ceph RGW를 backend로 쓰면 비용 0.

```yaml
schedule:
  - name: "daily-backup"
    schedule: "0 2 * * *"   # 매일 02:00
    keep: 30
    storageName: ceph-rgw-s3
```

PITR (Point-in-Time Recovery)도 가능해진다. 1일 작업으로 끝나고, 운영 진입 직전 무조건 해야 할 작업이다.

- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option B: PXC node 5개로 (3 → 5, 진짜 quorum 강화)

5-node면 2대 죽어도 quorum 유지 (3/5). 현재 3-node는 1대 죽음만 견딘다. write 부하 ↑되면 검토.

### Option C: ProxySQL → HAProxy 전환

ProxySQL 운영 함정이 늘면 HAProxy로 교체 검토. 우리 팀이 HAProxy에 익숙하기도 하고. 단점은 read/write split을 직접 구현해야 함.

### Option D: PostgreSQL + Patroni 전환

PG가 가진 강력한 기능 (MVCC, JSONB, partial index)이 필요한 비즈니스 요구가 생기면 검토. MySQL → PG 마이그레이션은 ORM이 잘 추상화돼 있으면 의외로 쉽다.

### Option E: Redis → DragonflyDB

Redis single-thread가 CPU 병목으로 측정되면 multi-thread DragonflyDB로 교체 검토. Redis 호환이라 코드 변경 거의 없음.

### Option F: Vitess 도입 (MySQL sharding)

단일 PXC 용량 한계 + 수천만 row+ 데이터 도달하면 Vitess로 sharding. 운영 ★★★★★라 신중해야 함.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 백업 없음 | A (immediate) ⭐ |
| write 부하 ↑ | B (5-node) |
| PG 기능 필요 | D |
| Redis CPU 병목 | E |
| 단일 PXC 용량 한계 | F |

---

## 🔗 다른 파트와의 연결

PXC는 `data-storage/06-rds-replication.md`에서 다루는 RDS external replica의 source다. PXC binlog가 VPN을 거쳐 AWS RDS로 전송된다. 아키텍처 측면에선 `architecture/04-burst-architecture.md`에서 EKS Pod이 RDS replica를 read하는 흐름이 설명된다. 보안 측면에선 DB 접속 password와 PII 데이터 암호화가 `security/05-secrets-rbac.md`와 직결된다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. PXC vs RDS — 왜 자체 운영을 골랐나요?**

A. 세 가지 이유입니다. **첫째, 데이터 주권** — PII 데이터를 외부 클라우드에 보내는 부담 회피. **둘째, 비용** — RDS HA 3-node $300/월 vs 우리 자체 자원만 사용. **셋째, 학습 가치** — Galera operator 운영 경험. 단점은 운영 부담인데 Percona Operator로 자동화해서 완화했습니다.

**Q2. Galera 동기 복제 vs binlog 비동기 차이는요?**

A. **Galera는 모든 노드 commit 후 client에 ACK** → 강한 일관성 (read after write 보장). 단점은 모든 node 대기 → write throughput 한계 + geo-distributed 부적합. **MySQL native binlog는 async** → 빠르지만 master 장애 시 data loss 가능. 우리는 PII 데이터의 정확성을 위해 Galera를 골랐습니다.

**Q3. ProxySQL을 왜 쓰나요?**

A. 세 가지 기능 때문입니다. **read/write split** — write는 master로, read는 replica로 자동 라우팅. **connection pooling** — App connection × DB node 폭증 회피. **query routing/firewall** — 위험한 쿼리 차단 가능. App에서 endpoint 1개 (ProxySQL Service)만 알면 ProxySQL이 알아서 분배합니다.

**Q4. Redis Sentinel vs Cluster 차이는요?**

A. **Sentinel = master-replica HA** (3-5 node quorum). **Cluster = sharding** (16384 slot 분산). 우리 데이터 양 작음 + 단순함 우선 → Sentinel. 진짜 수평 확장 필요시 Cluster 검토합니다.

**Q5. PXC 백업은 어떻게 하나요?**

A. **솔직히 현재 자동 백업이 없습니다 — 위험한 상태**입니다. Phase 6에서 Percona Operator의 backup 기능 활성화 (PerconaXtraDBClusterBackup CR + S3 storage)로 매일 백업 + 30일 보관 + PITR 자동화 예정입니다. 1일 작업이라 우선순위 ★★★★★입니다.

**Q6. 데이터가 PII인데 보안은요?**

A. 다섯 가지 layer입니다. **네임스페이스 격리** (`pii-protected`), **NetworkPolicy로 ticket-app만 접속** (zero-trust), **PXC TLS** (현재 disabled — 개선 필요), **at-rest encryption** (현재 X — Phase 7 후보), **backup 암호화**. 현재 4/5라 부족한 부분 (TLS, at-rest)을 의식적으로 인지하고 Phase 7 일정에 있습니다.
