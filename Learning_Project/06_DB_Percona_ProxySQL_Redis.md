# 06. DB & Cache — Percona, ProxySQL, Redis

> Layer 2 / 학습 2일 / 등급 🔴 (담당자)

---

## 1) Percona XtraDB Cluster (PXC)

### 정체

MySQL 호환 **멀티마스터 동기 복제** 클러스터. Galera Cluster 기반.

```
[PXC Node 1] ←─── certification-based replication ─── [PXC Node 2]
       ↑                                                  ↑
       └──────────────── [PXC Node 3] ←──────────────────┘
```

- 3대 모두 쓰기 가능 (master)
- 트랜잭션 commit 시 다른 노드에 즉시 동기
- 1대 다운 → 즉시 다른 노드로 접속 (페일오버 ~수초)

### 대안 비교

|               | **PXC**                     | MySQL Group Replication | Galera (원본)      | Vitess          |
| ------------- | --------------------------- | ----------------------- | ------------------ | --------------- |
| 라이센스      | 오픈소스                    | 오픈소스 (MySQL)        | 오픈소스 (MariaDB) | 오픈소스        |
| 멀티마스터    | ✅                          | ✅ (제한적)             | ✅                 | 샤딩            |
| Operator      | Percona                     | (없음)                  | (없음)             | Vitess Operator |
| 복잡도        | 중                          | 중                      | 중                 | 매우 높음       |
| **선택 이유** | Operator 성숙도 + 학습 자료 | -                       | -                  | 오버킬          |

### Percona Operator vs 수동 StatefulSet

|            | 수동 StatefulSet | **Percona Operator** |
| ---------- | ---------------- | -------------------- |
| 설정       | YAML 직접 작성   | CR로 선언            |
| 백업       | 직접 구현        | 내장 (PVC snapshot)  |
| 페일오버   | 직접 처리        | 자동                 |
| 업그레이드 | 위험             | rolling 안전         |
| 학습 가치  | DB 내부 이해     | 운영 자동화 이해     |

기술스택 명시: **Percona Operator**.

### PerconaXtraDBCluster CR 예시

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBCluster
metadata:
  name: kosa-pxc
  namespace: pii-protected
spec:
  crVersion: 1.14.0
  secretsName: kosa-pxc-secrets
  pxc:
    size: 3 # 3-node 클러스터
    image: percona/percona-xtradb-cluster:8.0
    resources:
      requests: { cpu: 500m, memory: 2Gi }
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: ceph-rbd
        resources:
          requests:
            storage: 50Gi
  proxysql:
    enabled: true
    size: 2
```

---

## 2) ProxySQL

### 풀어주는 문제

- 앱이 PXC 노드를 직접 알면? → 노드 추가/삭제 시 앱 코드 변경
- **ProxySQL** = MySQL 프록시. 앱은 ProxySQL만 알면 됨.

### 기능

- **R/W 분리** — SELECT는 reader, INSERT/UPDATE는 writer
- **Connection pool** — 앱이 매번 새로 연결 안 함
- **Query rules** — 정규식 기반 라우팅
- **Hostgroup** — 노드 그룹화

### Hostgroup 구성

```
hostgroup 10: writer  (PXC primary write target)
hostgroup 20: reader  (PXC slave-like read)
hostgroup 30: aws_replica (AWS RDS Read Replica)
```

### 라우팅 룰 예시

```sql
-- INSERT/UPDATE/DELETE → writer (10)
INSERT INTO mysql_query_rules
  (match_pattern, destination_hostgroup) VALUES ('^(INSERT|UPDATE|DELETE)', 10);

-- 이벤트 목록 SELECT → AWS replica (30) — 글로벌 latency 최소화
INSERT INTO mysql_query_rules
  (match_pattern, destination_hostgroup) VALUES ('^SELECT.*FROM events', 30);

-- 그 외 SELECT → reader (20)
INSERT INTO mysql_query_rules
  (match_pattern, destination_hostgroup) VALUES ('^SELECT', 20);
```

---

## 3) Redis Sentinel

### 정체

Redis 자체는 단일 마스터. **Sentinel** = 마스터 다운 감지 + 자동 페일오버 도구.

```
[Master] ←──── [Replica 1]
   ↑           ←──── [Replica 2]
   │
[Sentinel 1, 2, 3]  ← 마스터 감시
```

Master 다운 → Sentinel 과반수가 합의 → Replica 1 승격.

### Sentinel vs Cluster vs Standalone

|               | Standalone | **Sentinel**             | Cluster      |
| ------------- | ---------- | ------------------------ | ------------ |
| HA            | X          | ✅ (자동 페일오버)       | ✅ (샤딩+HA) |
| 데이터 분산   | X          | X (마스터 1개)           | ✅           |
| 복잡도        | 낮음       | 중                       | 높음         |
| **선택 이유** | -          | 우리 데이터 작음, 단순함 | 오버킬       |

### 우리 환경 사용처

- 세션 (JWT 토큰 인증)
- 티켓 카운터 (원자 DECR)
- Rate limit (분당 5회 등)

```python
# 티켓 예매 흐름
remaining = redis.decr(f"ticket_count:{event_id}")
if remaining < 0:
    redis.incr(f"ticket_count:{event_id}")    # 롤백
    return 409 "매진"

# DB에 INSERT
db.execute("INSERT INTO reservations ...")
```

DECR은 원자적 — 동시 요청이 와도 정확히 잔여 수만큼만 통과.

---

## 4) Hybrid 데이터 흐름

```
[온프레 K8s]                          [AWS]
  ProxySQL                              │
   ↓ write                              │
  PXC (3-replica) ── binlog 복제 ──→ RDS Read Replica
   ↑ read                              │
   │                                   │
   └─── 글로벌 사용자 SELECT ←─────────┘
```

쓰기는 온프레, 글로벌 읽기는 AWS RDS Replica (edge 효과).

---

## 5) 발표 어필

> _"Percona Operator로 PXC 3-replica를 운영하며 동기 멀티마스터 복제를 통해 단일 노드 장애에도
> 무중단입니다. ProxySQL이 R/W를 분리해 SELECT 부하를 read replica로 분산하며, 이벤트 목록 같은
> 글로벌 조회는 AWS RDS Read Replica로 라우팅하여 latency를 최소화했습니다. Redis는 Sentinel로 HA +
> 원자 DECR으로 티켓 동시성을 100% 차단합니다."_

---

## 다음 단원

[`07_IaC_Terraform_Ansible.md`](07_IaC_Terraform_Ansible.md)
