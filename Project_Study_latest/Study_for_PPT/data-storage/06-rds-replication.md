# 06. PXC → AWS RDS External Replication

> ⭐ **한 줄 요약**: 온프레 PXC가 master, AWS RDS MySQL이 **external read replica**. AWS native replica가 아닌 **binlog 기반 replication** 설정. EKS Pod이 RDS에서 read → burst 시 latency ↓.

---

## 🎯 우리가 한 선택

| 항목 | 값 |
|---|---|
| **Master** | 온프레 PXC `kosa-pxc-pxc-0` (172.16.23.x) |
| **Replica** | AWS RDS `kosa-rds-replica` |
| Engine | MySQL 8.0.40 (RDS db.t3.micro) |
| Endpoint | `kosa-rds-replica.cf88aaksmeg8.ap-northeast-2.rds.amazonaws.com` |
| Replication type | **External source replication** (RDS의 native replica가 아님) |
| Binlog format | ROW (Galera 기본) |
| Replication user | `repl` (PXC에서 생성) |
| Network | VPN 위에서 (~6ms latency) |
| `ReadReplicaSourceDBInstanceIdentifier` | None (= external replica) |

### 다이어그램
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
        │ INSERT/UPDATE 쿼리는 온프레로 (VPN 경유 또는 write 분리)
        │
[EKS Pod (burst 시)]
```

---

## 🔍 고려한 대안들

### Q1. AWS RDS native replica vs External source replication

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **External (선택)** | 온프레 master 가능, 자체 통제 | 수동 설정, AWS 콘솔 UI에서 "replica" 안 보임 | ★★★★★ (온프레 master면 유일) |
| AWS native replica | 콘솔 UI 지원, automated promotion | source가 AWS RDS여야 가능 (온프레 안 됨) | ★ (불가) |
| **Aurora Global Database** | cross-region active-active | Aurora만, on-prem 안 됨 | ★ |
| 양방향 replication (master-master) | 양쪽 write | conflict 위험 ★★★★★ | ★ |

### Q2. Replication 방식 — async vs semi-sync vs sync

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Async (선택)** | 빠름, master 영향 X | replica lag 가능 (data loss 위험) | ★★★★ |
| Semi-sync | 적어도 1 replica가 받았다고 보장 | latency ↑ | ★★★ |
| Sync (Galera 같은) | 강한 일관성 | VPN 6ms 환경엔 부적합 (write 멈춤) | ★ |

### Q3. DMS (Database Migration Service) vs 직접 설정

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **직접 binlog (선택)** | 무료, 통제 | 수동 설정, 모니터링 직접 | ★★★★ |
| AWS DMS | GUI, 자동 모니터링 | 시간당 과금 ($0.018+/h), 학습 곡선 | ★★★ |

---

## 💡 왜 External Source Replication?

### 1. 🔧 **온프레 master = 데이터 주권**
> 🔥 **핵심**: PXC는 우리가 통제, RDS는 read-only 그림자.

- 모든 write는 PXC (강한 일관성, Galera)
- RDS는 read 분산용
- 온프레 DB가 진리

### 2. 💰 **RDS replica 비용 최소화**
- AWS RDS HA가 아니라 단일 replica (db.t3.micro) → ~$12/월
- 정작 source가 온프레라서 AWS RDS HA 무의미

### 3. ⚡ **EKS burst 시 latency ↓**
- EKS Pod (AWS) → 온프레 PXC = 6ms (VPN)
- EKS Pod → RDS replica = <1ms (같은 region)
- 읽기 부하 많을 때 6배 latency 차이

### 4. 🛡️ **DR 후보**
- 온프레 죽으면 RDS를 promote → master로 (수동)
- RTO 약 30분 (DNS 변경 + 앱 reconfig)

### 5. 📚 **학습 가치**
- MySQL replication 깊이 학습
- VPN 위 cross-cloud replication 패턴
- 면접 어필 ("진짜 하이브리드 데이터 흐름")

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

### 같은 일을 AWS native replica로 가설
- source도 AWS RDS여야 → 온프레 PXC를 RDS로 마이그레이션 필요
- 그러면 PXC HA 3-node = $300/월 + replica $15
- **우리 패턴이 $300 절감**

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| 온프레 master + AWS replica | RDS UI에 "replica" 인식 X (수동 모니터링) |
| 데이터 주권 | binlog lag 모니터링 직접 |
| 비용 ↓ | external replication 함정 (binlog format, log retention) |
| EKS burst 시 fast read | 양방향 write 불가 (단순 read replica) |

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **VPN 끊김** | binlog 전송 멈춤, replica lag 발생 | VPN 복구 후 catch-up (수분~수시간) |
| **PXC master 죽음** | replica 새 binlog 없음 (stale) | PXC 회복 후 replica 자동 catch-up |
| **RDS 죽음** | EKS Pod read 실패 → 온프레 PXC로 fallback 필요 (현재 미구현) | RDS reboot |
| **Replication 깨짐 (binlog 손실 등)** | replica drift | re-bootstrap (mysqldump 다시) |
| **binlog format 다름** | replication 멈춤 | source PXC에 `binlog_format=ROW` 강제 |

---

## 🚀 확장 가능성

### Option A: ⭐ RDS Multi-AZ로 (현재 Single-AZ)
- ✅ **장점**: AZ 죽어도 standby 자동 promotion
- 💰 **비용**: 2배 (~$30/월)
- 🎯 **추천 시점**: replica가 진짜 read-heavy 운영 진입

### Option B: ⭐ RDS write fallback 추가 (DR)
- 현재: RDS는 read-only
- 확장: 온프레 죽으면 RDS를 master로 promote
- 작업: 자동화 (스크립트) 또는 수동 절차 + DNS 전환
- 🎯 **추천 시점**: 진짜 DR 정책

### Option C: 양방향 (master-master)
- ❌ conflict 위험 ★★★★★ (비추)
- 🎯 **추천 시점**: 거의 안 함

### Option D: 다른 region에도 replica
- ✅ **장점**: 글로벌 사용자 latency ↓
- ❌ **단점**: 비용 2배
- 🎯 **추천 시점**: 글로벌 운영

### Option E: GTID 기반 (현재 log file/position?)
- ✅ **장점**: replica 전환 자동화 쉬움
- ❌ **단점**: PXC가 이미 GTID 사용 중인지 확인 필요
- 🎯 **추천 시점**: replica 전환 자동화

### Option F: 백업 통합 (RDS automated backup as DR)
- ✅ **장점**: 7일 PITR (AWS 자동)
- 💰 **비용**: storage의 100% 이내 무료
- 🎯 **추천 시점**: 즉시 (이미 default로 활성)

### 📊 확장 의사결정

| 신호 | 우선 옵션 |
|---|---|
| 진짜 운영 + read traffic ↑ | A |
| DR 정책 강화 | B + F |
| 글로벌 사용자 | D |

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 💾 자기 (`05-pxc-redis.md`) | PXC가 source |
| 🏛️ 아키텍처 (`03-aws-hybrid.md`) | VPN 위에서 replication |
| 🏛️ 아키텍처 (`04-burst-architecture.md`) | EKS Pod이 RDS read |
| 🔒 보안 | replication user 권한, binlog 암호화 |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. RDS가 native replica가 아닌데 어떻게 외부에서 source?**
A. RDS는 "external source replication" 옵션 지원 (수동 설정). PXC에 replication user 만들고 binlog 권한 부여, RDS에서 `CALL mysql.rds_set_external_master(...)` 같은 stored procedure 호출.

**Q2. VPN 끊기면 어떻게? data loss?**
A. binlog는 PXC에 retain됨 (default 7일). VPN 복구 후 RDS가 마지막 position부터 catch-up. 진짜 data loss는 PXC binlog 만료 + VPN 7일 이상 끊김 시. 우리는 monitoring으로 lag 감시.

**Q3. EKS Pod이 write도 RDS로 보내면?**
A. RDS는 read-only (replica). write 시도하면 `Read-only` 에러. 앱이 ProxySQL/Pinpoint 같은 라우터로 read는 RDS, write는 PXC로 분리해야. 현재 ticket-app은 단순화 위해 둘 다 PXC.

**Q4. RDS Multi-AZ 안 한 이유?**
A. 비용 2배 + 우리 용도가 단순 "read 캐시"라 single-AZ로 충분. 진짜 RDS가 primary 가능성이면 multi-AZ.

**Q5. binlog format 함정?**
A. PXC는 ROW format 강제 (Galera 요구). MySQL 기본은 STATEMENT 또는 MIXED. RDS replica가 STATEMENT 기대 시 mismatch. 그래서 source와 replica 둘 다 ROW.

**Q6. PXC가 3 node인데 어느 node가 binlog 보내나?**
A. PXC는 wsrep_node_address 기반으로 한 노드 (보통 server_id=1)가 binlog 발행. 그 노드 죽으면 다른 노드가 이어받음 (Galera가 동기화돼있으니 binlog position도 같음).
