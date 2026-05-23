# 06. PXC → AWS RDS External Replication (OLAP 분리 전용)

> ⭐ **한 줄 요약**: 온프레 PXC가 master고 AWS RDS는 **external read replica**다. RDS의 역할은 **burst Pod의 read 가속이 아니라 OLAP(관리자 대시보드/분석 쿼리) 격리**다. 운영 트래픽(OLTP)은 전부 온프레 PXC + Redis로 처리하고, 분석 워크로드만 RDS Replica에서 돌려서 OLTP 영향을 0으로 만든다.

---

## 🎯 우리가 한 선택 — 그리고 한 번 바뀐 이유

이 문서는 **RDS Replica의 역할을 두 번 정의**했다. 한 번은 "burst 받쳐주는 인프라"로, 다시 한 번은 "OLAP 전용"으로. 왜 바뀌었는지 솔직하게 정리한다.

### 처음 설계 (지금 폐기)

처음엔 RDS Replica가 **EKS burst Pod의 read를 받쳐주는 인프라**라고 정당화했다. EKS Pod의 cache MISS read가 VPN을 타고 온프레 PXC로 가면 latency가 크고 VPN 대역폭도 점유한다는 논리였다.

### 다시 보면 — 이 정당화는 약했다

세 가지 조건을 따져보니 burst 받쳐주는 용도로서의 RDS는 거의 불필요했다.

**첫째, 전용선 가정.** 우리 프로젝트는 학습용 IPsec VPN을 쓰지만, 설계 자체는 **AWS Direct Connect나 KT 전용선** 가정이다. 그러면 latency가 1~2ms (LAN 수준)고 대역폭도 충분해서 "VPN이 느리니까 RDS가 필요" 라는 근거가 무너진다.

**둘째, Redis가 이미 95% read 흡수.** ticket-app의 access pattern은 user/seat 조회가 대부분인데, 이건 Redis cache hit ratio가 90%+ 나온다. 즉 DB까지 오는 read는 전체 트래픽의 5~10% 수준. 그 정도면 온프레 PXC reader 3 노드가 충분히 받는다.

**셋째, EKS Pod도 온프레 Redis 공유.** EKS ticket-app이 온프레 Redis (172.16.23.59 master)를 직접 쓰도록 구성하면, AWS burst Pod도 같은 cache 혜택을 받는다. 별도 캐시 layer 안 깔아도 됨.

이 세 조건 하에서 "RDS Replica가 EKS Pod의 cache MISS를 받쳐준다"는 정당화는 거의 의미가 없어졌다.

### 새 정의 — OLAP 분리

그래서 RDS Replica의 역할을 **운영(OLTP)과 완전 분리된 분석(OLAP) 전용 DB**로 재정의했다.

| 트래픽 | 경로 | DB |
|---|---|---|
| 일반 사용자 read (Redis hit) | Redis | - |
| 일반 사용자 read (Redis MISS) | ProxySQL → PXC reader | PXC |
| 일반 사용자 write | ProxySQL → PXC writer | PXC |
| AWS burst Pod read | 전용선/VPN → ProxySQL → PXC + Redis | PXC + Redis |
| AWS burst Pod write | 전용선/VPN → ProxySQL → PXC writer | PXC |
| **관리자 대시보드** | **admin-app → RDS Replica 직결** | **RDS** |
| **Grafana 분석** | **Grafana → RDS Replica 직결** | **RDS** |
| **외부 BI (가정)** | **→ RDS Replica** | **RDS** |

→ **운영 path는 RDS를 안 거치고, RDS는 분석 path 전용**.

### 데이터 흐름

```
[온프레 PXC]
  ├─ pxc-0 (master, server_id=1)
  ├─ pxc-1 (Galera sync)
  └─ pxc-2 (Galera sync)
       │
       │ binlog stream (TCP 3306)
       │ VPN/전용선
       ↓
[AWS RDS Replica server_id=2426772]
  └─ kosa-rds-replica (read-only, in VPC 10.20.10.54)
        ↑
        │ admin_ro SELECT만 (분석 쿼리)
        │
        ├── [admin-app Pod] (admin namespace) ⭐ 신규
        └── [Grafana Pod] (monitoring namespace) ⭐ 신규
```

EKS ticket-app Pod은 이 그림에서 **빠짐**. burst Pod은 별도 path (전용선 → PXC + Redis)로 동작.

---

## 🔍 고려한 대안들 (재정의 후)

### Q1. RDS Replica를 burst path에 두는 vs 분석 path에만 두는

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| Burst path에 두기 (구 설계) | EKS Pod cache MISS 빠름 | 전용선이면 차이 미미, 정당화 약함 | ★ |
| **분석 path 전용 (현 설계)** | OLAP/OLTP 명확 분리, 정당화 강함 | EKS Pod의 read는 전용선 한 번 더 거침 | ★★★★★ |
| 둘 다 쓰기 (혼합) | 두 가치 다 얻음 | 트래픽 복잡, 어디로 가는지 불명확 | ★★ |

현 설계 (분석 전용)가 명확하다. **OLTP는 PXC 하나, OLAP는 RDS 하나** — 트래픽 흐름이 한눈에 보인다.

### Q2. 관리자 대시보드 — admin-app vs Grafana만

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **admin-app + Grafana 둘 다 (선택)** | 운영 CRUD + 분석 시각화 동시 | 코드 2개 | ★★★★★ |
| Grafana만 (분석만) | 코드 0, 빠른 셋업 | CRUD 액션 불가 | ★★★ |
| admin-app만 | CRUD + 분석 통합 | 차트 라이브러리 직접 | ★★★ |

**Grafana**는 분석 panel을 SQL 한 줄로 만들 수 있어 빠른 시연 가치. **admin-app**은 실제 운영 액션(예약 취소, 환불 등)에 필요. 둘이 역할이 달라 같이 가는 게 자연스럽다.

### Q3. AWS RDS native replica vs External source replication

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **External (선택)** | 온프레 master 가능, 자체 통제 | 수동 설정, AWS UI에서 "replica" 안 보임 | ★★★★★ |
| AWS native replica | 콘솔 UI 지원, automated promotion | source가 AWS RDS여야 가능 (온프레 X) | ★ (불가) |

우리 시나리오 (온프레가 source)에선 External 외에 옵션 없음.

### Q4. Replication 방식 — async vs semi-sync vs sync

| 대안 | 장점 | 단점 | 적합도 |
|---|---|---|---|
| **Async (선택)** | 빠름, master 영향 X | replica lag 가능 (수 초) | ★★★★★ |
| Semi-sync | 적어도 1 replica가 받았다고 보장 | latency ↑ | ★★ |
| Sync (Galera 같은) | 강한 일관성 | 전용선 1ms도 write throughput ↓ | ★ |

분석 쿼리는 수 초 lag을 충분히 허용. async가 정답.

---

## 📖 용어 정리 — OLTP vs OLAP

이 문서의 핵심 개념이라 먼저 풀어둔다.

### OLTP (Online Transaction Processing)

**"운영 트랜잭션"** 처리. 사용자가 클릭할 때마다 발생하는 짧고 빠른 쿼리들.

```sql
-- OLTP 예시
SELECT * FROM seat WHERE id = 12345          -- 좌석 1개 조회
INSERT INTO seat (reserved_by) VALUES (...)  -- 예약 1건
UPDATE seat SET status='reserved' WHERE ...  -- 상태 1건 변경
SELECT * FROM user WHERE email='...'         -- 로그인 시 user 1명 조회
```

특징:
- 처리 시간 1~10ms
- 스캔하는 row 수 1~수백
- 초당 수천 query (높은 동시성)
- Lock 짧게 (row-level)
- 사용자가 직접 응답 기다림 → 빠른 응답 필수

### OLAP (Online Analytical Processing)

**"분석 쿼리"**. 관리자/분석가가 가끔 보는 무거운 집계 쿼리들.

```sql
-- OLAP 예시
-- 매출 추이
SELECT DATE(reserved_at), COUNT(*), SUM(price)
FROM seat
WHERE reserved_at > '2026-01-01'
GROUP BY DATE(reserved_at)

-- 공연별 점유율 TOP 10
SELECT show_id, COUNT(*) * 100.0 / total AS pct
FROM seat JOIN show ON ...
GROUP BY show_id
ORDER BY pct DESC LIMIT 10

-- 시간대별 예약 heatmap
SELECT HOUR(reserved_at), DAYOFWEEK(reserved_at), COUNT(*)
FROM seat
GROUP BY 1, 2
```

특징:
- 처리 시간 1초 ~ 수 분
- 스캔하는 row 수 수만 ~ 수백만
- 초당 1~10 query (낮은 동시성)
- Lock 길게 (table/partition-level)
- 비동기 (관리자가 기다려도 OK), 약간 stale 데이터 허용

### HTAP (Hybrid Transactional/Analytical Processing)

OLTP + OLAP을 **한 시스템에서 동시에 처리**하는 차세대 패턴. TiDB, Snowflake Unistore, MySQL HeatWave 같은 신규 솔루션이 표방. 단점은 신생 + 비싸서 우리 같은 학습/중소 환경엔 부적합. **분리 (separate OLTP DB + OLAP DB) 패턴이 여전히 정석**.

---

## 💡 왜 OLAP 분리가 정당한가 (RDS의 진짜 정당화)

### 1. OLTP가 OLAP 쿼리에 마비되지 않도록 ⭐ 가장 중요

같은 DB에 두 워크로드를 섞으면 **무거운 OLAP 쿼리 하나가 가벼운 OLTP 쿼리 수천 개를 멈추게** 한다. 시나리오로 풀어보자.

```
[같은 PXC에 둘 다 보낸 시나리오]

09:00:00 일반 사용자: SELECT WHERE id=25     → 1ms
09:00:01 일반 사용자: SELECT WHERE id=26     → 1ms
09:00:02 관리자: SELECT 매출 GROUP BY DATE   → 30초 lock 시작 🔥
09:00:03 일반 사용자: SELECT WHERE id=27     → 30초 대기 ⚠️
09:00:04 일반 사용자: SELECT WHERE id=28     → 30초 대기 ⚠️
...
09:00:32 관리자 쿼리 완료, 모든 대기 OLTP 다시 실행
         그동안 사용자 천 명이 응답 대기 → 사이트 다운처럼 보임 🔥🔥
```

관리자가 매출 대시보드를 한 번 새로고침했더니 **운영 사이트 전체가 30초 멈춤**. 진짜 운영 사고로 이어진 사례 많다. 특히 티켓 오픈 같은 critical 순간에 발생하면 신뢰도 손실 크다.

**분리하면 어떻게 되나**:

```
운영 DB (PXC):           관리자 매출 대시보드 영향 0
  ↑ 일반 사용자가 1ms로 응답 받음 (관리자가 뭘 하든)

분석 DB (RDS Replica):   30초 lock 잡혀도 운영 무관
  ↑ 관리자만 사용 (응답 30초 대기해도 OK)
```

OLTP는 OLTP끼리, OLAP는 OLAP끼리 — **서로 영향 0**. 이게 분리의 가장 큰 정당화.

### 2. 최적화 방향이 정반대

같은 데이터를 봐도 두 워크로드는 DB 튜닝이 정반대 방향이다.

| 튜닝 | OLTP | OLAP |
|---|---|---|
| Index 종류 | row 빠르게 찾는 **B-tree** | range scan용 **columnstore** |
| Memory | hot row 캐싱 (buffer pool) | sort/hash 작업 공간 |
| 디스크 | SSD **random IOPS** 우선 | sequential read **throughput** 우선 |
| Schema | **정규화** (write 빠르게) | **denormalized** (read 빠르게) |
| Lock | row-level (짧게) | table/partition-level OK (길게) |
| 통계 갱신 | 자주 (write 영향) | 가끔 (read 영향) |

같은 DB에 두 워크로드면 **둘 다 어중간하게 튜닝**된다. 분리하면 각자 최적화 가능. 예: 운영 PXC는 buffer pool ↑, 분석 RDS는 work_mem ↑ + 큰 instance.

### 3. 권한 분리 (보안)

```sql
-- 운영 user (kosa_app): INSERT/UPDATE/DELETE 가능 — 위험
GRANT SELECT, INSERT, UPDATE, DELETE ON kosa_tickets.* TO 'kosa_app'@'%';

-- 분석 user (admin_ro): SELECT만 — 안전
GRANT SELECT ON kosa_tickets.* TO 'admin_ro'@'%';
```

OLTP DB에 두 user를 둘 때 위험:
- admin 코드에 SQL injection이나 bug 있으면 **운영 데이터 망가질 수 있음**
- admin 권한 탈취 시 운영 영향

OLAP DB로 분리하면:
- admin user는 **운영 DB 자체 접근 불가**
- admin DB는 binlog로 다시 복구 가능 (read-only이라 복구도 단순)
- **최소 권한 원칙**의 깔끔한 시연

### 4. SLA가 다름

| | 운영 (ticket-app) | 분석 (관리자 대시보드) |
|---|---|---|
| 다운 허용 시간 | **0초** (사용자 즉시 영향) | **1시간 OK** (관리자만 영향) |
| 응답 시간 요구 | **< 100ms 필수** | 수 초 ~ 수 분 OK |
| 데이터 신선도 | **실시간** (방금 예약 즉시 반영) | 수 초 ~ 분 stale OK |
| 트래픽 패턴 | 초당 수천 query | 분당 수 query |

→ **두 워크로드의 SLA 요구가 다르니 인프라도 다르게**:
- 운영 DB: HA 3-node Galera (강한 일관성, zero downtime) — **고비용**
- 분석 DB: single AZ replica (다운 1시간 OK니까 비용 ↓) — **저비용**

같은 인프라로 두 SLA를 다 만족시키면 과도하게 비싸지거나 (둘 다 HA) 부족해진다 (둘 다 단일). 분리하면 각자 맞는 grade로 운영.

### 5. 운영 grade 패턴과 일치

진짜 운영급 회사의 데이터 계층은 보통 이렇다:

```
운영 DB (OLTP): 응답성/정합성 중심 (PXC, Aurora primary)
분석 DB (OLAP): 무거운 집계/리포팅 (Read Replica, Redshift, Snowflake)
```

우리도 이 패턴을 그대로 따른다. 회사가 진짜 운영급으로 가도 동일한 구조라 학습 가치 ↑.

### 6. DR fallback (보조 가치)

전용선이 끊겨도 RDS는 살아있고, 마지막 binlog position까지의 데이터를 보유. 진짜 DR 시나리오에선 RDS를 promote해서 일시적 read-only 서비스 유지 가능. 주 정당화는 아니지만 부수 효과.

### 7. 학습/시연 가치

binlog 복제, replication lag, ProxySQL routing, OLTP/OLAP 분리 패턴 — 이게 다 시연 포인트. 면접에서 "데이터 계층을 어떻게 설계했나요?" 질문에 풍부하게 답 가능.

---

## 💼 우리 ticket-app 케이스 — 구체적 예시

이론만 보면 추상적이라 우리 ticket-app의 실제 시나리오로 풀어본다.

### 관리자가 보고 싶은 OLAP 쿼리들

```sql
-- 1) "이번 달 매출은?"
SELECT DATE(reserved_at), COUNT(*), SUM(price) 
FROM seat 
WHERE reserved_at > '2026-05-01' 
GROUP BY DATE(reserved_at)
-- → row 수천~수만 스캔, 1~10초

-- 2) "공연별 점유율 TOP 10?"
SELECT show_id, COUNT(*) * 100.0 / total
FROM seat ... JOIN ...
GROUP BY show_id
ORDER BY 2 DESC LIMIT 10
-- → JOIN + GROUP BY + ORDER BY, 5~30초

-- 3) "시간대별 예약 패턴?"
SELECT HOUR(reserved_at), DAYOFWEEK(reserved_at)
FROM seat WHERE reserved_at IS NOT NULL
GROUP BY 1, 2
-- → 전체 테이블 스캔, 10~60초

-- 4) "최근 24h 신규 회원 vs 신규 예약 추이"
-- 두 테이블 JOIN + DATE 집계 → 수십 초
```

### 만약 이게 PXC로 가면?

티켓 오픈 시점 (예: 인기 공연 예매 시작 직후):

```
14:00:00 [티켓 오픈]
14:00:05 사용자 1000명 동시 좌석 조회 → PXC 정상 처리 (1ms/query)
14:00:10 관리자가 "현재 점유율 어때?" 새로고침
         → 점유율 쿼리 PXC에 도착 → 30초 lock
14:00:11 사용자 좌석 클릭 → 30초 대기 ⚠️
14:00:12 사용자 좌석 클릭 → 30초 대기 ⚠️
14:00:30 사용자들 "사이트 멈췄나요?" 문의 폭주
14:00:40 관리자 쿼리 끝, 모든 대기 처리
         이미 사용자 수백명 이탈
```

→ **관리자 1명의 새로고침이 사용자 수백~수천 명에게 직접 영향**.

### 분리 후 (현 설계)

```
14:00:00 [티켓 오픈]
14:00:10 관리자가 "현재 점유율?" 새로고침
         → RDS Replica에 도착 → 30초 lock (RDS 안)
14:00:11 사용자 좌석 클릭 → PXC 1ms ✓
14:00:12 사용자 좌석 클릭 → PXC 1ms ✓
14:00:40 관리자 쿼리 결과 받음
         사용자 영향 0
```

티켓 오픈 같은 critical 순간에 관리자가 마음대로 분석 쿼리 돌려도 운영 영향 없음. **이게 분리의 진짜 가치**.

### 한 줄 요약 (발표용)

> "OLAP 쿼리는 무거워서 OLTP 쿼리를 30초 멈출 수 있다. 분리하면 서로 영향 0."

면접에서 "왜 OLTP/OLAP 분리해요?" 물으면 이 한 문장 + 위 예시 하나만 들면 끝.

---

## 💰 비용 분석

### AWS RDS

| 항목 | 비용 |
|---|---|
| db.t4g.micro (2 vCPU, 1GB) — OLAP만 처리니 다운사이즈 가능 | $0.013/h × 720 = **$9.4/월** |
| Storage 20GB gp3 | $0.115/GB × 20 = $2.3/월 |
| 백업 storage (RDS 자동) | 무료 (storage 100% 이내) |
| VPN 데이터 전송 (binlog) | $0.09/GB × ~5GB = $0.5/월 |
| **합계** | **약 $12/월** |

`db.t3.micro` ($12) → `db.t4g.micro` ($9.4)로 다운사이즈해도 충분. burst supporting 용도가 아니라 분석 쿼리만 받으니까 더 작아도 됨.

### admin-app 비용

```
admin-app Pod: 100m CPU, 128MiB RAM (작음)
→ K8s 워커 노드 amortize → 추가 비용 거의 0
```

---

## ⚖️ Trade-off

| 얻은 것 | 잃은 것 |
|---|---|
| OLTP/OLAP 명확 분리 | RDS UI에 "replica" 인식 X (수동 모니터링) |
| 무거운 분석 쿼리가 운영 영향 0 | binlog lag 모니터링 직접 |
| admin user 최소 권한 | 분석 데이터 약간 stale (수 초~분) |
| OLAP 워크로드 자유롭게 추가 가능 | external replication 함정 (binlog format, log retention) |

가장 큰 trade-off는 **분석 데이터의 약간의 stale**. RDS는 async replication이라 수 초 lag이 있을 수 있다. 매출 집계 등은 실시간이 아니어도 OK라 대부분 문제 안 됨. 진짜 실시간 분석이 필요하면 별도 stream processing (Kafka, Kinesis) 패턴이 필요.

---

## ⚠️ SPoF + 회복

| 시나리오 | 영향 | 회복 |
|---|---|---|
| **VPN/전용선 끊김** | binlog 전송 멈춤, replica lag 발생 | 복구 후 catch-up (수분~수시간) |
| **PXC master 죽음** | replica 새 binlog 없음 (stale) | PXC 회복 후 replica 자동 catch-up |
| **RDS 죽음** | **admin/Grafana 분석만 영향, 운영 영향 0** | RDS reboot |
| **Replication 깨짐** | replica drift | re-bootstrap (mysqldump 다시) |
| **binlog format 다름** | replication 멈춤 | source PXC에 `binlog_format=ROW` 강제 |

**중요 — RDS가 죽어도 ticket-app 운영은 정상 동작**. burst path와 분리됐기 때문. 관리자가 잠시 대시보드를 못 볼 뿐. 이게 OLAP 분리의 명확한 이점.

---

## 🚀 확장 가능성

### Option A: ⭐ admin-app + Grafana 분석 대시보드 (현재 진행 중)

OLAP 분리 패턴의 완성. 5개 분석 위젯 + admin CRUD.

### Option B: Materialized view / Summary table

무거운 집계 쿼리를 매번 돌리지 않고 nightly CronJob으로 미리 계산:

```sql
CREATE OR REPLACE TABLE daily_revenue AS
SELECT DATE(reserved_at), COUNT(*), SUM(...) 
FROM seat
WHERE reserved_at IS NOT NULL
GROUP BY DATE(reserved_at);
```

대시보드 응답 ms 단위. 진짜 운영급 패턴.

### Option C: 외부 BI (Tableau, Metabase, Superset) 연결

RDS Read Replica는 표준 MySQL이라 BI 도구가 다 붙음. admin_ro user로 read-only 분석 환경 제공.

### Option D: RDS Multi-AZ로 (현재 Single-AZ)

분석 트래픽 critical해지면 HA. 비용 2배.

### Option E: 다른 region에도 replica

글로벌 사용자 latency ↓. 비용 ↑.

### 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 분석 대시보드 기본 | A (admin-app) ⭐ |
| 무거운 집계 자주 | B (materialized view) |
| 외부 분석가 협업 | C (BI 도구) |
| 분석 DB SLA 중요 | D (Multi-AZ) |
| 글로벌 분석가 | E (cross-region) |

---

## 🔗 다른 파트와의 연결

이 RDS replication은 PXC (`05-pxc-redis.md`)의 source 역할과 직결된다. 아키텍처 측면에선 VPN/전용선 위에서 동작하니 `architecture/03-aws-hybrid.md`와 연결되고, **burst 아키텍처 (`architecture/04-burst-architecture.md`)와는 분리된 별도 path**로 그려진다 — 이 분리가 OLTP/OLAP 분리의 시각화 핵심. 보안 측면에선 admin_ro 최소 권한 user가 `security/05-secrets-rbac.md`와 연결.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. RDS Read Replica를 왜 깔았어요?**

A. **OLTP와 OLAP 분리**입니다. 관리자 대시보드 (매출, 점유율 같은 무거운 집계 쿼리)를 운영 DB(PXC)에 보내면 OLAP 쿼리 하나가 OLTP를 마비시킬 수 있어서요. RDS에 OLAP만 격리하면 운영 영향 0입니다. 이게 Read Replica의 정통한 use case고, 운영급 패턴과 일치합니다. **참고로 EKS burst Pod의 read 가속 용도는 아닙니다** — 전용선 가정이라 latency 차이가 미미하고, Redis가 95%+ 흡수하니 PXC가 충분히 받습니다.

**Q2. RDS가 native replica가 아닌데 어떻게 외부에서 source가 되나요?**

A. **RDS의 external source replication 옵션**을 사용합니다. (1) PXC에 replication user (`repl`) 만들고 binlog 권한 부여, (2) RDS에서 `CALL mysql.rds_set_external_master(...)` stored procedure로 외부 source 설정. RDS UI엔 "replica" 표시 안 되지만 binlog stream을 직접 받아옵니다.

**Q3. 분석 데이터가 stale 하면 안 되는 경우엔?**

A. RDS는 async replication이라 수 초~수십 초 lag이 정상입니다. 대부분 분석 (매출, 점유율, TOP 예약자)은 실시간 ±1분 데이터로 충분합니다. 진짜 실시간이 필요한 케이스 (예: 라이브 대시보드)면 Kafka/Kinesis 같은 stream processing 또는 PXC에서 직접 read (단 OLTP에 부담)을 고려합니다.

**Q4. admin-app은 ProxySQL을 안 거치고 RDS 직결이라던데?**

A. **의도적인 분리**입니다. ProxySQL은 운영 트래픽(OLTP)의 connection pooling + read/write split을 담당합니다. admin-app의 분석 쿼리가 ProxySQL을 거치면 (1) 운영 connection pool과 섞임, (2) ProxySQL 장애 시 admin도 영향. RDS 직결이면 **failure isolation**이 명확하고, admin_ro user의 최소 권한도 ProxySQL 설정 없이 적용됩니다.

**Q5. EKS burst Pod도 RDS read하면 latency 좋잖아요?**

A. **전용선 가정이면 latency 차이가 거의 없습니다**. EKS Pod → 전용선 → 온프레 PXC reader = 2~3ms. EKS Pod → 같은 VPC RDS = 1ms. 차이 미미한데 인프라 복잡도 ↑ (운영 path와 분석 path가 섞임). 그래서 burst Pod도 온프레 PXC를 쓰고, RDS는 OLAP 전용으로 깔끔히 분리했습니다.

**Q6. VPN/전용선 끊기면 데이터 손실?**

A. **data loss는 거의 없습니다**. binlog는 PXC에 7일 retain되므로 복구 후 RDS가 마지막 position부터 catch-up합니다. 단, **분석 데이터가 며칠치 stale될 수 있음** — 운영 트래픽은 영향 0이라 사업적 손실 없음. 진짜 위험은 7일+ 단절로 binlog 만료되는 경우인데 그땐 re-bootstrap (mysqldump 다시) 필요.

**Q7. binlog format 함정은 뭔가요?**

A. **PXC는 ROW format 강제** (Galera 요구사항)인데, MySQL 기본은 STATEMENT 또는 MIXED입니다. RDS replica가 STATEMENT를 기대하면 mismatch로 replication이 멈춥니다. source PXC와 replica RDS 둘 다 `binlog_format=ROW`로 명시해야 합니다.

**Q8. RDS Multi-AZ 안 한 이유는요?**

A. **분석 워크로드라 SLA 요구가 낮음 + 비용 2배**. 매출 대시보드가 1시간 안 보여도 사업 영향 미미. 운영 path에서 분리됐기 때문에 RDS down이 critical 사고 아님. 진짜 분석가가 실시간 대시보드 의존하기 시작하면 Multi-AZ 검토.
