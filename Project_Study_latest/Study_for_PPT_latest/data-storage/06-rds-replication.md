# 06. PXC → AWS RDS External Replication

> ⭐ **한 줄 요약**: 온프레 PXC가 master고 AWS RDS는 **external read replica**다. AWS native replica (source가 AWS RDS여야 함)가 아니라 **binlog 기반 replication을 수동 설정**해 VPN 위에서 데이터가 흐른다. EKS Pod이 burst 시 RDS replica에서 read해서 latency를 줄인다.

---

## 🎯 우리가 한 선택

이 구성의 핵심은 **온프레가 진리의 source**라는 점이다. 모든 write는 온프레 PXC로 가고, RDS는 그저 read 분산용 그림자다. AWS native RDS Read Replica는 source가 AWS RDS여야 가능한데, 우리는 온프레 PXC가 source라 external replication을 수동 설정했다.

| 항목 | 값 |
|---|---|
| **Master** | 온프레 PXC `kosa-pxc-pxc-0` (172.16.23.x) |
| **Replica** | AWS RDS `kosa-rds-replica` |
| Engine | MySQL 8.0.40 (RDS db.t3.micro) |
| Endpoint | `kosa-rds-replica.cf88aaksmeg8.ap-northeast-2.rds.amazonaws.com` |
| Replication type | **External source replication** (RDS native가 아님) |
| Binlog format | ROW (Galera 기본) |
| Replication user | `repl` (PXC에서 생성) |
| Network | VPN 위에서 (~6ms latency) |
| `ReadReplicaSourceDBInstanceIdentifier` | None (= external replica 증거) |

### 데이터 흐름

```
[온프레 PXC]
  ├─ pxc-0 (master, server_id=1)
  ├─ pxc-1 (Galera sync)
  └─ pxc-2 (Galera sync)
       │
       │ binlog stream (TCP 3306)
       │ VPN tunnel (IPsec)
       ↓
[AWS RDS Replica server_id=2426772]
  └─ kosa-rds-replica (read-only)
        ↑
        │ SELECT 쿼리 (read)
        │
[EKS Pod (burst 시)]
```

위에서 흥미로운 점은 RDS가 single endpoint지만 **PXC는 3-node cluster**라는 점이다. PXC의 어느 노드가 binlog source 역할을 할지는 wsrep_node_address 기반으로 자동 결정된다. 보통 pxc-0이 source 역할이지만, Galera 동기 복제 덕분에 다른 노드도 같은 binlog position을 가지고 있어 source 노드가 죽어도 다른 노드가 이어받을 수 있다.

---

## 🔍 고려한 대안

### Q1. AWS RDS native replica vs External source replication

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **External (선택)** | 온프레 master 가능, 자체 통제 | 수동 설정, AWS UI에서 "replica" 안 보임 | ★★★★★ (온프레 master면 유일) |
| AWS native replica | 콘솔 UI 지원, automated promotion | source가 AWS RDS여야 가능 (온프레 안 됨) | ★ (불가) |
| Aurora Global Database | cross-region active-active | Aurora만, on-prem 안 됨 | ★ |
| 양방향 (master-master) | 양쪽 write | conflict 위험 ★★★★★ | ★ |

우리 시나리오 (온프레가 source)에선 사실 **External 외에 다른 옵션이 없다**. AWS native replica는 source가 AWS여야 하고, Aurora Global도 Aurora 전용이다. 양방향 master-master는 conflict resolution이 복잡해 거의 안 쓴다.

### Q2. Replication 방식 — async vs semi-sync vs sync

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Async (선택)** | 빠름, master 영향 X | replica lag 가능 (data loss 위험) | ★★★★ |
| Semi-sync | 적어도 1 replica가 받았다고 보장 | latency ↑ | ★★★ |
| Sync (Galera 같은) | 강한 일관성 | VPN 6ms 환경엔 부적합 (write 멈춤) | ★ |

**우리 6ms VPN 환경에서 sync replication은 부적합**하다. write 시점에 RDS commit 대기하면 매 write에 6ms 추가 → throughput 급감. async는 master에 영향 없고 RDS가 약간 lag있게 따라간다 (몇 초 이내). cache처럼 약간의 stale 허용 가능한 use case에 잘 맞는다.

### Q3. DMS vs 직접 설정

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **직접 binlog (선택)** | 무료, 통제 | 수동 설정, 모니터링 직접 | ★★★★ |
| AWS DMS | GUI, 자동 모니터링 | 시간당 과금, 학습 곡선 | ★★★ |

AWS DMS (Database Migration Service)도 cross-cloud replication을 지원하지만 시간당 과금 ($0.018+/h)이 누적되고, 사실 PXC binlog 직접 설정이 더 직관적이다. 한 번 설정하면 운영이 단순하다.

---

## 💡 왜 External Source Replication?

### 1. 온프레 master = 데이터 주권

> 🔥 **핵심**: PXC는 우리가 통제, RDS는 read-only 그림자.

모든 write는 PXC에서 일어나고 (강한 일관성, Galera), RDS는 read 분산을 위한 캐시 역할이다. **온프레 DB가 진리**라는 원칙을 명확히 한다.

### 2. RDS 비용 최소화

AWS RDS HA가 아니라 단일 replica (db.t3.micro)라 월 ~$12 정도다. 정작 source가 온프레라서 AWS RDS HA를 갖춰도 의미가 적다. 단일 replica로 충분하다.

### 3. EKS burst 시 latency ↓

EKS Pod (AWS)이 read를 보낼 곳:
- 온프레 PXC (VPN 통해): 6ms
- RDS replica (같은 region): <1ms

**6배 latency 차이**다. 읽기 부하 많은 워크로드 (예: ticket 조회)에서 효과가 크다.

### 4. DR 후보

온프레가 죽으면 RDS를 promote해서 새 master로 만들 수 있다. RTO 약 30분 (DNS 변경 + 앱 reconfig 수동). 진짜 DR 시나리오의 마지막 안전망 역할.

### 5. 학습 가치

MySQL replication을 깊이 이해하는 좋은 use case다. VPN 위 cross-cloud replication 패턴, binlog format 함정, NAT-T 같은 깊은 개념을 직접 다뤄볼 수 있다. 면접에서 "진짜 하이브리드 데이터 흐름"으로 어필 가능하다.

---

## 💰 비용 분석

### AWS RDS

| 항목 | 비용 |
|---|---|
| db.t3.micro (1 vCPU, 1GB) | $0.017/h × 720 = $12.2/월 |
| Storage 20GB gp3 | $0.115/GB × 20 = $2.3/월 |
| 백업 storage (RDS 자동) | 무료 (storage 100% 이내) |
| VPN 데이터 전송 (binlog) | $0.09/GB × ~5GB = $0.5/월 |
| **합계** | **약 $15/월** |

### 가설 — 같은 일을 AWS native replica로

만약 source도 AWS RDS여야 하니 온프레 PXC를 RDS로 마이그레이션해야 한다. 그러면 PXC HA 3-node 대체 = $300/월 + replica $15 = $315/월. **우리 패턴이 $300 절감**이다.

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 온프레 master + AWS replica | RDS UI에 "replica" 인식 X (수동 모니터링) |
| 데이터 주권 | binlog lag 모니터링 직접 |
| 비용 ↓ | external replication 함정 (binlog format, log retention) |
| EKS burst 시 fast read | 양방향 write 불가 (단순 read replica) |

가장 큰 trade-off는 **AWS UI 제약**이다. RDS Console에서 "Replica?" 컬럼이 None으로 보여서 누가 봐도 "이게 replica인지 모름". 우리가 직접 binlog position을 모니터링하고 lag을 측정해야 한다.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **VPN 끊김** | binlog 전송 멈춤, replica lag 발생 | VPN 복구 후 catch-up (수분~수시간) |
| **PXC master 죽음** | replica 새 binlog 없음 (stale) | PXC 회복 후 replica 자동 catch-up |
| **RDS 죽음** | EKS Pod read 실패 → 온프레 PXC로 fallback 필요 (미구현) | RDS reboot |
| **Replication 깨짐** | replica drift | re-bootstrap (mysqldump 다시) |
| **binlog format 다름** | replication 멈춤 | source PXC에 `binlog_format=ROW` 강제 |

VPN 끊김이 가장 흔한 시나리오인데, binlog는 PXC에 retain (default 7일)되므로 VPN 복구 후 RDS가 마지막 position부터 catch-up한다. 진짜 위험한 건 **VPN이 7일 이상 끊긴 상태**인데, 그러면 binlog 만료로 re-bootstrap 필요.

---

## 🚀 확장 가능성

### Option A: ⭐ RDS Multi-AZ로 (현재 Single-AZ)

AZ 죽어도 standby가 자동 promotion된다. 비용 2배 (~$30/월)지만 진짜 read-heavy 운영 진입 시 검토.

### Option B: ⭐ RDS write fallback 추가 (DR)

현재 RDS는 read-only. 확장으론 온프레 죽으면 RDS를 master로 promote. 자동화 스크립트 또는 수동 절차 + DNS 전환. 진짜 DR 정책의 핵심 부분.

### Option C: 양방향 (master-master)

conflict 위험 ★★★★★라 거의 안 함.

### Option D: 다른 region에도 replica

글로벌 사용자 latency ↓. 비용 2배.

### Option E: GTID 기반 (현재 log file/position 방식?)

replica 전환 자동화 쉬워짐. PXC가 이미 GTID 사용 중인지 확인 필요.

### Option F: 백업 통합 (RDS automated backup as DR)

AWS가 자동으로 7일 PITR 제공. 이미 default 활성. 추가 확장 옵션은 cross-region snapshot 등.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 진짜 운영 + read 부하 ↑ | A (Multi-AZ) |
| DR 정책 강화 | B + F |
| 글로벌 사용자 | D |

---

## 🔗 다른 파트와의 연결

이 RDS replication은 PXC (`05-pxc-redis.md`)의 source 역할과 직결된다. 아키텍처 측면에선 VPN 위에서 동작하니 `architecture/03-aws-hybrid.md`와 연결되고, EKS Pod이 burst 시 RDS를 read한다는 점에서 `architecture/04-burst-architecture.md`도 관련된다. 보안 측면에선 replication user 권한 + binlog 암호화 (현재 X)가 향후 보강 대상이다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. RDS가 native replica가 아닌데 어떻게 외부에서 source가 되나요?**

A. **RDS의 external source replication 옵션**을 사용합니다. (1) PXC에 replication user (`repl`) 만들고 binlog 권한 부여, (2) RDS에서 `CALL mysql.rds_set_external_master(...)` stored procedure로 외부 source 설정. RDS UI엔 안 보이지만 binlog stream을 직접 받아옵니다.

**Q2. VPN 끊기면 데이터 손실이 발생하나요?**

A. 일시적으론 lag이지만 **data loss는 거의 없습니다**. binlog는 PXC에 7일 retain되므로 VPN 복구 후 RDS가 마지막 position부터 catch-up합니다. 진짜 위험은 VPN이 7일+ 끊겨서 binlog 만료되는 경우인데, 그땐 re-bootstrap (mysqldump 다시) 필요합니다. 우리는 monitoring으로 lag 감시합니다.

**Q3. EKS Pod이 write도 RDS로 보내면 어떻게 되나요?**

A. **RDS는 read-only (replica)**라 write 시도하면 `Read-only` 에러를 받습니다. 앱이 ProxySQL이나 Pinpoint 같은 라우터로 read는 RDS, write는 PXC로 분리하는 게 정석입니다. 우리 ticket-app은 단순화를 위해 둘 다 PXC로 보내는 상태입니다 (개선 여지).

**Q4. RDS Multi-AZ 안 한 이유는요?**

A. **비용 2배 + 우리 용도가 단순 "read 캐시"**라 single-AZ로 충분합니다. RDS가 primary가 될 가능성이 있는 시나리오 (DR)면 multi-AZ가 맞지만, 현재는 그저 burst 시 read 분산 용도입니다.

**Q5. binlog format 함정은 뭔가요?**

A. **PXC는 ROW format 강제** (Galera 요구사항)인데, MySQL 기본은 STATEMENT 또는 MIXED입니다. RDS replica가 STATEMENT를 기대하면 mismatch로 replication이 멈춥니다. 그래서 source PXC와 replica RDS 둘 다 `binlog_format=ROW`로 명시해야 합니다. 우리도 이걸로 한 번 막혀본 경험이 있습니다.

**Q6. PXC가 3 node인데 어느 node가 binlog를 보내나요?**

A. **PXC는 wsrep_node_address 기반으로 한 노드가 binlog 발행** (보통 server_id=1)합니다. 그 노드가 죽으면 다른 노드가 이어받습니다. Galera 동기 복제 덕분에 모든 노드가 같은 binlog position을 가지고 있어 source 전환이 매끄럽습니다.
