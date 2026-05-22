# 05. PXC + Redis Sentinel — 데이터 레이어

> ⭐ **한 줄 요약**: **PXC (Percona XtraDB Cluster) 3-node**가 primary DB (operator 관리, Galera 동기 복제). **Redis Sentinel 3-node**가 캐시/세션/queue. 둘 다 K8s 위에서 HA.

---

## 🎯 우리가 한 선택

### PXC (Percona XtraDB Cluster)
| 항목 | 값 |
|---|---|
| Operator | Percona XtraDB Cluster Operator |
| Cluster name | `kosa-pxc` |
| Namespace | `pii-protected` |
| PXC nodes | 3 (`kosa-pxc-pxc-0/1/2`) |
| ProxySQL nodes | 2 (`kosa-pxc-proxysql-0/1`) |
| Replication | Galera 동기 복제 (write 모든 노드에 commit 보장) |
| Storage | RBD PVC per node |
| Service endpoint | `kosa-pxc-proxysql.pii-protected` |

### Redis Sentinel
| 항목 | 값 |
|---|---|
| Helm chart | bitnami/redis (Sentinel HA) |
| Namespace | `redis` |
| Nodes | 3 (`kosa-redis-node-0/1/2`) |
| Sentinel | 3 (각 node와 colocated) |
| Replication | async, master-replica |
| Quorum | 2 (3 중 2가 동의해야 failover) |
| Password | kosa1004 |

---

## 🔍 고려한 대안들

### Q1. DB — PXC vs PostgreSQL HA vs MongoDB vs DynamoDB

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **PXC (선택)** | Galera 동기 복제 (강한 일관성), MySQL 호환, Operator | Galera 한계 (write 부하 single point), schema lock 까다로움 | ★★★★ |
| **PostgreSQL + Patroni** | 가장 강력한 DB, MVCC | replication 비동기, Patroni 학습 곡선 | ★★★★ |
| MongoDB Replica Set | document DB, schema-less | 우리 워크로드 SQL 적합 (PII), MongoDB 운영 부담 | ★★ |
| AWS DynamoDB | 관리형, 무한 확장 | AWS lock-in, 온프레 X | ★ |
| Vitess | MySQL sharding | 매우 무거움, K8s 운영 부담 ★★★★★ | ★ |

### Q2. Cache — Redis vs Memcached vs DragonflyDB

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Redis Sentinel (선택)** | 사실상 표준, persistence + pub/sub | single-thread (CPU bound 가능) | ★★★★★ |
| Memcached | 가장 빠름 (multi-thread) | persistence X, 기능 적음 | ★★★ |
| DragonflyDB | Redis 호환 + multi-thread | 신규, 사례 적음 | ★★★ |
| Redis Cluster | 진짜 sharding | 더 복잡, slot 관리 | ★★★ (확장 시) |

### Q3. PXC 설치 방식 — Operator vs Helm vs 수동

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Percona Operator (선택)** | 공식, 자동 backup/restore, monitoring | Operator 자체 운영 | ★★★★★ |
| bitnami Helm | 단순 | HA 약함, operator 기능 없음 | ★★★ |
| 수동 설치 (StatefulSet) | 통제 ★★★★★ | 자동화 0 | ★ |

---

## 💡 왜 이걸 선택했나

### PXC를 고른 이유
1. **MySQL 호환**: 가장 보편적인 SQL, 학습 자료 ★★★★★
2. **Galera 동기 복제**: 강한 일관성 (PII 데이터엔 중요)
3. **Operator**: backup/restore/monitoring 자동
4. **ProxySQL 통합**: read/write split 자동, connection pooling

### Redis Sentinel을 고른 이유
1. **사실상 표준**: 캐시/세션/queue 모두 가능
2. **Sentinel = 단순 HA**: Cluster (sharding)보다 학습 곡선 ↓
3. **3-node = 진짜 quorum**: 2-node 구성은 SPoF

---

## 💰 비용 분석

### 자원 사용
| 컴포넌트 | CPU | RAM | Storage |
|---|---|---|---|
| PXC × 3 | 1 vCPU × 3 | 2GB × 3 = 6GB | 20GB × 3 = 60GB |
| ProxySQL × 2 | 0.5 vCPU × 2 | 1GB × 2 = 2GB | 5GB × 2 = 10GB |
| Redis × 3 | 0.3 vCPU × 3 | 512MB × 3 = 1.5GB | 5GB × 3 = 15GB |
| **합계** | **~5 vCPU** | **~10 GB** | **85 GB** |

→ Worker 노드 (6GB RAM) 3대에 분산 → 50% 사용

### 비교 (관리형 vs 자체)
| 옵션 | 월 비용 |
|---|---|
| **우리 (자체 K8s)** | ~₩0 (자원 amortize) |
| AWS RDS Aurora MySQL HA 3-node | ~$300/월 |
| Google Cloud SQL HA | ~$250/월 |
| AWS ElastiCache Redis 3-node | ~$60/월 |

→ 자체 운영 ★★★★★ 비용 절감 (운영 부담 trade-off)

---

## ⚖️ Trade-off

### PXC 선택
| 얻은 것 | 잃은 것 |
|---|---|
| 동기 복제 (강한 일관성) | write throughput 한계 (모든 노드 commit 대기) |
| MySQL 호환 | Galera schema lock 까다로움 |
| Operator 자동화 | Operator 학습 |

### Redis Sentinel 선택
| 얻은 것 | 잃은 것 |
|---|---|
| 자동 failover | sharding X (단일 노드 용량 한계) |
| 3-node quorum | replicas 동기화 async (data loss 가능) |

---

## ⚠️ SPoF + 회복

### PXC
| 시나리오 | 영향 | 회복 |
|---|---|---|
| **PXC node 1 죽음** | 2/3 quorum → write 가능 | 자동 (Operator가 새 Pod 생성) |
| **PXC node 2 죽음** | 1/3 → quorum loss → write 차단 (read만) | 긴급 — 1대라도 살리기 |
| **ProxySQL 죽음 (1/2)** | 다른 ProxySQL이 받음 | 자동 |
| **DB 데이터 손실 (xtrabackup 필요)** | 백업에서 복구 | xtrabackup restore |

### Redis
| 시나리오 | 영향 | 회복 |
|---|---|---|
| **Redis master 죽음** | Sentinel 자동 failover (수초) → 다른 replica 승격 | 자동 |
| **Sentinel quorum loss (3 중 2 죽음)** | failover 불가 | 1대라도 살리기 |
| **persistence 데이터 손실** | 캐시 휘발 | 앱이 다시 채움 |

---

## 🚀 확장 가능성

### Option A: ⭐ PXC backup 자동화 (xtrabackup → S3)
- ✅ **장점**: PITR (Point-in-Time Recovery) 가능
- 💰 **비용**: Ceph RGW에 저장 (무료) 또는 AWS S3 ($1~/월)
- ⏱️ **작업**: 1일 (CronJob + xtrabackup 설정)
- 🎯 **추천 시점**: 즉시 (Phase 6)

### Option B: PXC node 5개로 (3 → 5, 진짜 quorum 강화)
- ✅ **장점**: 2대 죽어도 quorum 유지 (3/5)
- ❌ **단점**: 자원 ↑
- 🎯 **추천 시점**: write 부하 ↑

### Option C: ProxySQL → HAProxy (또는 vice versa)
- ✅ **장점**: HAProxy는 우리 팀 익숙
- ❌ **단점**: read/write split 직접 구현
- 🎯 **추천 시점**: ProxySQL 함정 ↑

### Option D: PostgreSQL + Patroni 전환
- ✅ **장점**: MVCC, 강력한 기능
- ❌ **단점**: 앱 SQL 차이, MySQL → PG 마이그레이션
- 🎯 **추천 시점**: 진짜 운영 + PG 필요 기능 (JSONB 등)

### Option E: Redis → DragonflyDB 전환
- ✅ **장점**: multi-thread, 빠름
- 🎯 **추천 시점**: Redis 단일 thread 병목 측정

### Option F: Vitess 도입 (MySQL sharding)
- ✅ **장점**: 진짜 수평 확장
- ❌ **단점**: 무거움 (운영 ★★★★★)
- 🎯 **추천 시점**: 단일 PXC 용량 한계 + 천만 row+ 데이터

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 백업 없음 | A (immediate) |
| write 부하 ↑ | B (5-node) |
| PG 기능 필요 | D |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 자기 (`06-rds-replication.md`) | PXC binlog → AWS RDS external replica |
| 🏛️ 아키텍처 | PXC가 ticket-app의 DB → `architecture/04-burst-architecture.md` (EKS Pod이 RDS replica 사용) |
| 🔒 보안 | DB 접속 password, PII 데이터 암호화 → `security/05-secrets-rbac.md` |
| 🔧 CI/CD | PXC schema migration 자동화 (현재 manual) |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. PXC vs RDS — 왜 자체 운영?**
A. (1) 데이터 주권 (PII 데이터 자체 호스팅), (2) 비용 (RDS HA 3-node $300/월 vs 우리 자원만), (3) 학습 가치. 단점은 운영 부담인데 Percona Operator로 자동화.

**Q2. Galera 동기 복제 vs binlog 비동기?**
A. Galera = 모든 노드 commit 후 client에 ACK → **강한 일관성** (read after write 보장). 단점은 모든 node 대기 → write throughput 한계 (geo-distributed 부적합). MySQL native binlog는 async → 빠르지만 data loss 가능.

**Q3. ProxySQL 왜?**
A. (1) read/write split: write는 master로, read는 replica로 자동, (2) connection pooling (앱 connection × node 조합 폭증 회피), (3) query routing/firewall. App에서 endpoint 1개만 알면 됨.

**Q4. Redis Sentinel vs Cluster?**
A. Sentinel = master-replica HA (3-5 node quorum). Cluster = sharding (16384 slot 분산). 우리 데이터 양 작음 + 단순함 우선 → Sentinel. 진짜 수평 확장 필요시 Cluster.

**Q5. PXC 백업 어떻게?**
A. **현재 자동 백업 없음** (위험). Phase 6에서 xtrabackup CronJob 추가 예정. 또는 Percona Operator의 backup 기능 활성 (S3로 자동 schedule).

**Q6. 데이터가 PII인데 보안은?**
A. (1) namespace `pii-protected` 격리, (2) NetworkPolicy로 ticket-app만 접속 (zero-trust), (3) PXC TLS 활성 (현재 disabled — 개선 필요), (4) at-rest encryption (현재 X — Phase 7 후보), (5) backup도 암호화.
