# 챕터 09: Percona XtraDB Cluster — PXC + Operator + ProxySQL

> KOSA 인프라 프로젝트 학습 시리즈 / Day 5 / 등급 🟡🟡🟡<br> 선수 챕터: 04(K8s 핵심), 07(Helm),
> 08(Ceph CSI)

---

## 학습 후 알 수 있는 것

- **MySQL의 복제 모델**을 비동기 / 반동기 / 동기 세 가지로 구분하고, **Galera 기반 동기 복제**가
  어떤 보장을 주는지 설명할 수 있어요.
- Percona XtraDB Cluster(PXC)와 MySQL Group Replication(GR), Vitess가 **어떤 문제를 푸는지** 비교할
  수 있어요.
- **K8s Operator 패턴**(CRD + Controller)이 stateful 시스템(DB)을 K8s 위에 올릴 때 왜 필요한지,
  `WATCH_NAMESPACE`가 뭐 하는지 이해할 수 있어요.
- **ProxySQL**의 R/W splitting, Hostgroup, 쿼리 룰 동작을 설명할 수 있어요.
- 우리 환경의 5가지 함정 — `WATCH_NAMESPACE`, immutable storageClassName, stale STS, Secret 기반
  root 비밀번호 관리, 앱 user 별도 생성 — 의 **원인과 해결**을 머리에 새길 수 있어요.
- 발표 시 "왜 RDS 안 쓰고 PXC?", "왜 GR 안 쓰고 Galera?" 에 답할 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Percona XtraDB Cluster(PXC)** 는 MySQL 호환 데이터베이스에 **Galera 기반 동기 복제**를 더해, 모든
노드가 동시에 읽기/쓰기 가능한 멀티 마스터 클러스터를 제공하는 오픈소스 DB 시스템이에요.

세 컴포넌트를 묶어 부르는 게 우리 구성이에요.

- **PXC**: 데이터 노드 (3대, MySQL + Galera)
- **Percona Operator**: K8s에서 PXC를 선언적으로 관리하는 CRD/Controller
- **ProxySQL**: 앱과 PXC 사이의 고성능 SQL 프록시 (R/W 분기, failover)

### 1.2 등장 배경

MySQL의 기본 복제는 **비동기(async)** 예요. 마스터에서 커밋 끝나면 바이너리 로그를 슬레이브에
흘려보내는데, 슬레이브가 적용하기 전에 마스터가 죽으면 **데이터 손실**이 발생할 수 있어요. 5.7부터
**반동기(semi-sync)** 가 나왔지만 슬레이브 1개가 ACK만 하면 끝이라 여전히 약점이 있었죠.

이 문제를 해결한 게 **Galera Cluster** 라는 라이브러리예요. 코덱십(Codership)이 만든 wsrep API 기반
동기 복제 엔진. 트랜잭션을 커밋하기 전에 **모든 노드가 인증(certification)** 한 후에야 커밋이
끝나요. 이 Galera를 MySQL/MariaDB에 통합한 게:

- **MariaDB Galera Cluster** (MariaDB 측)
- **Percona XtraDB Cluster (PXC)** (Percona 측)

둘 다 사실상 같은 Galera 엔진을 쓰고, **API 호환되는 다른 MySQL 빌드**예요. 우리는 PXC 8.0.36-28.1을
사용해요.

K8s 시대로 넘어오면서 "DB 3대를 사람이 셋업하고 손으로 SST 모니터링"하는 시대가 끝났어요. Percona가
**Percona Operator for MySQL**을 내놨고, CR(`PerconaXtraDBCluster`) 하나 만들면 STS, Service,
ConfigMap, Secret, PVC 다 자동으로 만들어줘요.

### 1.3 핵심 개념 + 용어 풀이

| 용어                | 설명                                                        | 우리 환경                              |
| ------------------- | ----------------------------------------------------------- | -------------------------------------- |
| **Galera Cluster**  | 동기 복제 라이브러리 (wsrep API)                            | PXC 8.0.36에 내장                      |
| **wsrep**           | Write Set REPlication, Galera의 API 이름                    | `wsrep_cluster_size` 변수 등으로 확인  |
| **SST**             | State Snapshot Transfer, 새 노드 들어올 때 전체 데이터 복사 | xtrabackup-v2 메서드                   |
| **IST**             | Incremental State Transfer, 잠깐 떨어진 노드가 부분 동기화  | gcache 안의 변경만 전송                |
| **gcache**          | 변경 이력을 보관하는 메모리 캐시                            | 128MB(기본). IST 가능 범위 결정        |
| **Multi-Master**    | 모든 노드가 R/W 가능                                        | 우리 PXC 3대 모두 가능                 |
| **Operator**        | K8s에서 도메인 지식을 코드로 표현한 컨트롤러                | percona-xtradb-cluster-operator 1.14.0 |
| **CR**              | Custom Resource, Operator가 watch하는 YAML                  | `kind: PerconaXtraDBCluster`           |
| **WATCH_NAMESPACE** | Operator가 어떤 ns의 CR을 볼지 결정                         | `pxc-operator,pii-protected`           |
| **ProxySQL**        | MySQL용 L7 프록시                                           | 2 replicas, hostgroup 10/20/30         |
| **Hostgroup**       | ProxySQL의 백엔드 그룹                                      | 10=writer, 20=reader, 30=offline       |

### 1.4 동작 원리 (내부 메커니즘)

#### Galera 동기 복제 흐름

```
[Client]  BEGIN; INSERT INTO seat (...) VALUES (...);  COMMIT;
                                  │
                                  ▼
                         [PXC Node A] (local apply)
                                  │
                                  ▼ wsrep: 변경 집합(write set) 생성
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        ▼                         ▼                         ▼
   [Node B]                  [Node C]                  [Node A]
   certification             certification             certification
        │                         │                         │
        └─────────────────────────┼─────────────────────────┘
                                  ▼
                       모든 노드가 OK → 커밋 진행
                                  │
                                  ▼
                       Client에 COMMIT 성공 응답
```

이 순서가 **동기 복제**의 의미예요. Client가 COMMIT 성공 응답을 받았다는 건 **이미 3노드 모두에 적용
가능한 상태로 확인됐다**는 보장이에요.

비동기 복제와 비교하면:

| 항목               | 비동기 (MySQL 기본)                 | 동기 (Galera/PXC)                                       |
| ------------------ | ----------------------------------- | ------------------------------------------------------- |
| 커밋 성공 시점     | 마스터에 쓴 직후                    | 모든 노드가 인증 완료                                   |
| 데이터 손실 가능성 | 있음 (슬레이브 적용 전 마스터 사망) | 없음 (인증 자체가 클러스터 합의)                        |
| 쓰기 지연          | 빠름                                | 네트워크 RTT만큼 느림                                   |
| 쓰기 확장          | 마스터 1대 한계                     | 멀티 마스터지만 충돌 가능 → 사실상 1개 노드에 집중 권장 |

#### Operator의 동작

```
[YAML 파일: PerconaXtraDBCluster CR]
        │
        ▼ kubectl apply
[K8s API Server]
        │
        ▼ etcd 저장 + event 발생
[Percona Operator Pod]
        │
        ├─ Reconcile loop (10초 주기)
        │
        ▼
    "현재 상태 vs 원하는 상태" 비교
        │
        ├── PXC STS 없음 → 생성
        ├── ProxySQL STS 없음 → 생성
        ├── PVC 부족 → 생성
        ├── Secret 없음 → 자동 생성 (root, monitor, xtrabackup ...)
        ├── Service 없음 → 생성 (pxc, pxc-unready, proxysql)
        ├── PXC가 3대인데 CR이 5대로 바뀜 → 스케일 아웃
        ├── 비밀번호 Secret 변경됨 → MySQL에 ALTER USER
        └── ...
```

Operator의 본질은 **"사람이 손으로 하던 운영 절차를 K8s reconcile loop로 자동화"** 한 거예요.
비밀번호 회전, 백업, SST 후처리, 무중단 업그레이드까지 다 코드 안에 들어 있어요.

#### ProxySQL의 R/W 분기

```
[App] ─→ proxysql:3306
            │
            ├── 쿼리 파싱 (간단 정규식)
            │
            ├── SELECT?
            │    └─ hostgroup 20 (reader) → 라운드 로빈
            │
            ├── UPDATE/INSERT/DELETE/BEGIN/CALL?
            │    └─ hostgroup 10 (writer) → 단일 노드
            │
            └── 트랜잭션 안?
                 └─ writer로 고정 (트랜잭션 일관성)
```

쿼리 룰은 `mysql_query_rules` 테이블에 정의해요. 우리는 기본 룰 + 일부 SELECT 강제 라우팅을
추가했어요.

### 1.5 주요 기능

- **동기 복제(Galera)**: 데이터 손실 0
- **읽기 확장**: 3노드 어디서나 SELECT 가능
- **자동 failover**: 노드 죽어도 ProxySQL이 hostgroup 30으로 빼고 라우팅 계속
- **자동 SST**: 새 노드 들어오면 xtrabackup으로 자동 동기화
- **Percona Toolkit 통합**: pt-online-schema-change, pt-table-checksum 등
- **PMM(Percona Monitoring and Management)** 연동: DB 전용 모니터링
- **백업/복원 CR**: `PerconaXtraDBClusterBackup` / `PerconaXtraDBClusterRestore`
- **무중단 마이너 버전 업그레이드**: rolling update

### 1.6 다른 도구와 비교

| 항목         | **PXC (우리)**         | MySQL Group Replication           | Vitess                      | AWS RDS Multi-AZ         | MongoDB Replica Set          |
| ------------ | ---------------------- | --------------------------------- | --------------------------- | ------------------------ | ---------------------------- |
| 복제 방식    | 동기 (Galera)          | "사실상 동기" (consensus)         | 비동기 + Sharding           | 동기 (단일 AZ → 다른 AZ) | 비동기 (oplog)               |
| Multi-Master | O                      | O (8.0+)                          | O (per shard)               | X (단일 마스터)          | X (Primary 1개)              |
| Sharding     | X                      | X                                 | O (핵심 기능)               | X (수직 확장)            | X (별도 sharded cluster)     |
| K8s Operator | Percona Operator       | InnoDB Cluster Operator (덜 성숙) | Vitess Operator             | (매니지드)               | Percona Operator for MongoDB |
| 운영 부담    | 중 (Operator 덕분에 ↓) | 중                                | 높음 (Vitess 토폴로지 학습) | 0                        | 중                           |
| 학습 곡선    | 낮음 (MySQL 호환)      | 낮음                              | 가파름                      | 0                        | 낮음                         |
| 적합 규모    | 중소~대규모 OLTP       | 중소~대규모 OLTP                  | 초대규모 (수십 TB+)         | AWS 종속                 | NoSQL                        |

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 필요한가

- **온프레미스에서 MySQL HA를 직접 운영**해야 할 때. 매니지드 DB가 없으니 클러스터 형태가 필요.
- **데이터 손실 0 보장**이 필요할 때 (결제, 좌석 예약, 재고 등). 비동기 복제로는 못 함.
- **읽기 트래픽이 무거워서** 리더 노드만으로 부족할 때. 멀티 마스터로 읽기 분산.
- **K8s 위에서 DB를 운영**할 때. Operator가 없는 옛날 MariaDB Galera는 STS 직접 짜야 해서 빡셈.

### 2.2 업계 표준, 대표 사용 기업/사례

- **카카오, NHN**, 라인 등 한국 대형 IT의 다수 서비스가 **MariaDB Galera 또는 PXC**를 운영해요.
  (PXC와 MariaDB Galera는 같은 Galera 엔진 기반)
- **Percona** 자체는 MySQL 컨설팅/지원 시장에서 Oracle 다음 가는 점유율. PXC가 그 회사의 플래그십
  제품.
- **OpenStack 컨트롤 플레인 DB** 가 전통적으로 Galera 기반(MariaDB Galera)이에요. 클라우드 인프라
  자체가 Galera 위에서 도는 셈.
- **AWS Aurora**가 내부적으로 비슷한 아이디어(스토리지 분리 + 멀티 라이터)지만 클로즈드. Aurora 못
  쓰는 환경에서 PXC가 그 자리를 차지.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **읽기 부하 분산**: ProxySQL이 SELECT를 3노드에 라운드 로빈. 워커 1대 죽어도 2/3 노드가 살아 있음.
- **데이터 무결성**: 동기 복제라 "마스터 죽었는데 슬레이브에 데이터 없음" 같은 비동기 복제의 악몽이
  없음.
- **운영 자동화**: Operator가 백업 스케줄, root 비밀번호 회전, 노드 교체 다 해줌. 옛날 "DBA 24/7
  대기" 시대에서 벗어남.
- **이식성**: MySQL 와이어 프로토콜 100% 호환. 앱 코드 한 줄도 안 바꾸고 일반 MySQL → PXC 전환 가능.

### 2.4 시장 위치

- **MySQL 생태계**에서 HA 솔루션 3대장 = MySQL GR / Galera (MariaDB/PXC) / Vitess.
- GitHub Star: percona-xtradb-cluster-operator는 7~8백 개대, 활발한 릴리스(분기마다).
- Percona는 IPO 안 했지만 **유료 지원 매출 안정적**, AWS도 일부 EKS Addon으로 Percona Operator 인증.
- 중국 PingCAP의 TiDB가 NewSQL로 부상 중이지만, 기존 MySQL 호환 워크로드는 여전히 PXC/Galera 우위.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 옵션                                 | 장점                                     | 단점                                         | 우리 환경 적합도 |
| ------------------------------------ | ---------------------------------------- | -------------------------------------------- | ---------------- |
| **PXC + Operator + ProxySQL (선택)** | 동기 복제, K8s 네이티브 운영, MySQL 호환 | 함정 많음(WATCH_NAMESPACE 등)                | ★★★★★            |
| MySQL Group Replication on K8s       | 공식 Oracle 솔루션                       | InnoDB Cluster Operator가 덜 성숙, 8.0+ 필수 | ★★★              |
| Vitess                               | 무한 sharding                            | 토폴로지 복잡, 우리 규모 오버스펙            | ★                |
| AWS RDS Aurora                       | 매니지드 0운영                           | 온프레미스 안 됨, 비용                       | X (온프레 단계)  |
| MariaDB Galera (raw)                 | 무료, 동일 엔진                          | K8s Operator 약함, 수동 운영                 | ★★               |
| Vanilla MySQL + Manual Replica       | 가장 단순                                | HA 직접 구현 = 사고 위험                     | ★                |

### 3.2 현업 표준과의 정합성

- 한국 대형 IT(카카오/NHN 등) 다수가 **MariaDB Galera**를 쓰는데, **Galera 엔진 자체는 PXC와 동일**.
  발표 시 "현업 동일 기술 스택" 어필 가능.
- **K8s에 DB 올리기**는 Percona/Crunchy/Zalando 등 Operator를 통한 게 베스트 프랙티스. Raw STS로
  직접 짜는 건 옛날 방식.

### 3.3 선택 근거 (트레이드오프)

#### 왜 PXC (MySQL GR이나 RDS 대신)?

1. **온프레미스에 RDS가 없음** → 매니지드는 옵션 아님.
2. **MySQL GR Operator는 덜 성숙** → MySQL 공식의 InnoDB Cluster Operator는 1.x로 들어왔지만
   백업/PMM 통합 등에서 Percona 따라잡지 못 함.
3. **Galera 운영 노하우의 시장 풍부** → 한국어 자료, StackOverflow Q&A 등 절대량이 압도적.
4. **이미 Ceph CSI로 RWO 디스크가 준비됨** → STS 기반 DB 운영의 인프라 조건 충족.

#### 왜 namespace 분리 (pxc-operator vs pii-protected)?

```
namespace: pxc-operator     ← Operator Pod이 사는 곳
namespace: pii-protected    ← PXC + ProxySQL Pod이 사는 곳 (DB 데이터 = PII)
```

이건 의도된 보안 설계예요.

- **PII(개인정보) 격리**: DB는 회원 정보 등 PII를 담음. `pii-protected` 네임스페이스에
  NetworkPolicy로 강한 제한 가능.
- **Operator 권한 최소화**: Operator는 자기 ns에 있고, 필요한 권한만 다른 ns에 RoleBinding으로 위임.
- **다중 PXC 인스턴스**: 미래에 staging/prod 분리 시 Operator 1개 + ns 여러 개가 깔끔.

대신 트레이드오프로 **WATCH_NAMESPACE 설정의 함정**이 생겨요(7장 함정 1).

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
┌────────────────────────────────────────────────────────────┐
│ Namespace: pxc-operator                                    │
│ ┌────────────────────────────────────────┐                 │
│ │ Deployment: percona-xtradb-cluster-    │                 │
│ │             operator (1.14.0)          │                 │
│ │   env: WATCH_NAMESPACE=                │                 │
│ │     "pxc-operator,pii-protected"       │                 │
│ └────────────────┬───────────────────────┘                 │
└──────────────────┼─────────────────────────────────────────┘
                   │ watch CR
                   ▼
┌──────────────────────────────────────────────────────────────┐
│ Namespace: pii-protected                                     │
│                                                              │
│ ┌──────────────────────────┐                                 │
│ │ PerconaXtraDBCluster CR  │ ← 사용자가 만드는 YAML          │
│ │  name: kosa-pxc          │                                 │
│ │  pxc: { size: 3 }        │                                 │
│ │  proxysql: { size: 2 }   │                                 │
│ │  storageClassName:       │                                 │
│ │    team2-rbd-block       │                                 │
│ └────────┬─────────────────┘                                 │
│          │ Operator가 reconcile                              │
│          ▼                                                   │
│ ┌──────────────────────────────────────────┐                 │
│ │ STS: kosa-pxc-pxc      (3 replicas)      │                 │
│ │  ├─ kosa-pxc-pxc-0 (PVC datadir 8Gi)     │                 │
│ │  ├─ kosa-pxc-pxc-1 (PVC datadir 8Gi)     │                 │
│ │  └─ kosa-pxc-pxc-2 (PVC datadir 8Gi)     │                 │
│ │                                          │                 │
│ │ STS: kosa-pxc-proxysql (2 replicas)      │                 │
│ │  ├─ kosa-pxc-proxysql-0 (PVC 1Gi)        │                 │
│ │  └─ kosa-pxc-proxysql-1 (PVC 1Gi)        │                 │
│ │                                          │                 │
│ │ Service: kosa-pxc          (headless)    │                 │
│ │ Service: kosa-pxc-unready  (headless)    │                 │
│ │ Service: kosa-pxc-proxysql (ClusterIP)   │                 │
│ │                                          │                 │
│ │ Secret: kosa-pxc-secrets                 │                 │
│ │   keys: root, xtrabackup, monitor,       │                 │
│ │         clustercheck, proxyadmin, ...    │                 │
│ └──────────────────────────────────────────┘                 │
└──────────────────────────────────────────────────────────────┘
              │ DNS: kosa-pxc-proxysql.pii-protected.svc...
              ▼
┌──────────────────────────────────────────────────────────────┐
│ Namespace: kosa-tickets                                      │
│  Deployment: ticket-app (FastAPI)                            │
│   env from Secret: ticket-db-credentials                     │
│     DB_HOST: kosa-pxc-proxysql.pii-protected.svc...          │
│     DB_USER: kosa_app                                        │
│     DB_PASSWORD: ...                                         │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 핵심 설정값과 근거

| 항목               | 값                                               | 근거                                               |
| ------------------ | ------------------------------------------------ | -------------------------------------------------- |
| PXC 버전           | 8.0.36-28.1                                      | 2024 안정판, Operator 1.14가 지원하는 최신         |
| PXC 노드 수        | 3                                                | Galera 최소 권장(쿼럼 2/3). 5는 워커 메모리 부족   |
| ProxySQL 노드 수   | 2                                                | HA만 보장하면 됨. ProxySQL은 stateless에 가까움    |
| StorageClass       | `team2-rbd-block`                                | 챕터 08에서 default로 설정한 SC                    |
| 데이터 디스크      | 8Gi (학습용)                                     | 운영은 50Gi+ 권장. 우리는 좌석 100개 + 예약 데모용 |
| Operator namespace | `pxc-operator`                                   | Operator 격리                                      |
| PXC namespace      | `pii-protected`                                  | DB 격리(PII 보호)                                  |
| WATCH_NAMESPACE    | `pxc-operator,pii-protected`                     | 두 ns 모두 감시 (함정 1)                           |
| root 비밀번호      | Secret `kosa-pxc-secrets.root` (kosa1004 학습용) | Operator가 Secret 기반으로 관리                    |

### 4.3 다른 컴포넌트와의 연결

```
ticket-app ─→ kosa-pxc-proxysql.pii-protected.svc.cluster.local:3306
                       │
                       ▼ ProxySQL 분기
                ┌──────┴───────┐
                ▼              ▼
            writer HG10    reader HG20
            (kosa-pxc-pxc-0)  (kosa-pxc-pxc-1,2)

ceph-csi-rbd ──→ PVC: datadir-kosa-pxc-pxc-0,1,2
                       │
                       ▼
                Ceph: team2-k8s-pvc-rbd/csi-vol-*

Prometheus ──→ Operator의 metrics endpoint, PMM exporter (옵션)
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 Operator 설치 (Helm)

**위치:** `[bastion]`

```bash
helm repo add percona https://percona.github.io/percona-helm-charts
helm install percona-operator percona/pxc-operator \
  -n pxc-operator --create-namespace \
  --set watchAllNamespaces=false \
  --set "watchNamespace=pxc-operator,pii-protected"
```

**왜 이 옵션?**

- `watchAllNamespaces=false`: 전체 ns watch는 cluster-wide RBAC이 필요해서 권한 광범위해짐. 우리는
  2개 ns만 필요.
- `watchNamespace=...`: 두 ns 콤마로 묶음. 이게 deployment env의 WATCH_NAMESPACE에 들어가요.

### 5.2 PXC CR (PerconaXtraDBCluster)

**우리 파일 경로 (예시):** `/Users/sangjjang/kosa_infra_project/manifests/pxc/kosa-pxc.yaml`

```yaml
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBCluster
metadata:
  name: kosa-pxc
  namespace: pii-protected
spec:
  crVersion: 1.14.0
  secretsName: kosa-pxc-secrets
  allowUnsafeConfigurations: false

  pxc:
    size: 3
    image: percona/percona-xtradb-cluster:8.0.36-28.1
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        memory: 2Gi
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: team2-rbd-block # ★ immutable 필드
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 8Gi
    affinity:
      antiAffinityTopologyKey: "kubernetes.io/hostname" # 노드 분산

  proxysql:
    enabled: true
    size: 2
    image: percona/proxysql2:2.5.5
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: team2-rbd-block
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 1Gi

  backup:
    image: percona/percona-xtradb-cluster-operator:1.14.0-pxc8.0-backup
    schedule:
      - name: daily
        schedule: "0 3 * * *"
        keep: 5
        storageName: s3-or-rgw-storage # (옵션)
```

**왜 이 옵션? (라인별)**

- `crVersion: 1.14.0`: Operator 버전과 맞춤. 다르면 reconcile 안 함.
- `allowUnsafeConfigurations: false`: 3 미만, 짝수 노드 등 unsafe 구성 차단.
- `pxc.size: 3`: Galera 최소 권장 (쿼럼 2/3).
- `image: ...8.0.36-28.1`: Operator 1.14가 공식 지원하는 PXC 버전.
- `storageClassName: team2-rbd-block`: **immutable** — 한 번 정하면 못 바꿈 (함정 2).
- `antiAffinityTopologyKey: hostname`: PXC Pod 3개가 다른 노드에 분산 (한 노드 죽어도 2/3 살아남)
- `proxysql.size: 2`: ProxySQL HA. stateless에 가까워서 2개로 충분.

### 5.3 ticket-app DB Secret

```bash
kubectl create secret generic ticket-db-credentials -n kosa-tickets \
  --from-literal=DB_HOST=kosa-pxc-proxysql.pii-protected.svc.cluster.local \
  --from-literal=DB_PORT=3306 \
  --from-literal=DB_NAME=kosa_tickets \
  --from-literal=DB_USER=kosa_app \
  --from-literal=DB_PASSWORD=kosa1004
```

**왜 ProxySQL DNS를 박는가?**

- 앱은 ProxySQL만 보면 됨. PXC 노드 1개가 죽어도 ProxySQL이 가려서 R/W 라우팅 해줘요.
- 만약 앱이 PXC 직접 보면, PXC 노드 죽었을 때 앱이 connection refused. 앱 코드에 retry 로직 다
  박아야 함.

---

## 6. 실행 + 결과

### 6.1 CR 적용

명령

```bash
kubectl apply -f /Users/sangjjang/kosa_infra_project/manifests/pxc/kosa-pxc.yaml
```

기대 출력

```
perconaxtradbcluster.pxc.percona.com/kosa-pxc created
```

### 6.2 상태 확인

명령

```bash
kubectl get pxc -n pii-protected
```

실제 출력 (약 10분 후, SST까지 끝났을 때)

```
NAME       ENDPOINT                                       STATUS   PXC   PROXYSQL   AGE
kosa-pxc   kosa-pxc-proxysql.pii-protected.svc.local      ready    3     2          12m
```

### 6.3 Pod 확인

명령

```bash
kubectl get pods -n pii-protected
```

기대 출력

```
NAME                    READY   STATUS    RESTARTS   AGE
kosa-pxc-pxc-0          1/1     Running   0          11m
kosa-pxc-pxc-1          1/1     Running   0          9m
kosa-pxc-pxc-2          1/1     Running   0          7m
kosa-pxc-proxysql-0     2/2     Running   0          11m
kosa-pxc-proxysql-1     2/2     Running   0          11m
```

해석:

- PXC Pod은 순서대로 뜸 (pxc-0 → pxc-1 → pxc-2). pxc-0이 Galera 부트스트랩 → 1, 2가 SST로 동기화. 첫
  부팅 5~10분, 이후 SST 3~5분씩.
- ProxySQL은 PXC가 ready 되기 전에도 미리 떠 있지만 백엔드 정상화는 PXC 다음.

### 6.4 Galera 클러스터 size 검증

명령

```bash
kubectl exec kosa-pxc-pxc-0 -n pii-protected -- \
  mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
```

기대 출력

```
+--------------------+-------+
| Variable_name      | Value |
+--------------------+-------+
| wsrep_cluster_size | 3     |
+--------------------+-------+
```

`3` 이 나와야 3노드 동기 복제 정상.

### 6.5 동기 복제 데모 (PXC 직접)

명령

```bash
# pxc-0에 INSERT
kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- \
  mysql -ukosa_app -pkosa1004 kosa_tickets \
  -e "INSERT INTO seat (seat_no, status) VALUES ('DEMO', 'available');"

# pxc-1에서 즉시 조회
kubectl exec kosa-pxc-pxc-1 -n pii-protected -- \
  mysql -ukosa_app -pkosa1004 kosa_tickets \
  -e "SELECT * FROM seat WHERE seat_no='DEMO';"

# pxc-2에서도 조회
kubectl exec kosa-pxc-pxc-2 -n pii-protected -- \
  mysql -ukosa_app -pkosa1004 kosa_tickets \
  -e "SELECT * FROM seat WHERE seat_no='DEMO';"
```

기대 출력 — 3노드 모두 동일한 1행 반환. **이게 동기 복제의 위력**이에요. 비동기였다면 pxc-1/2가 못
받았을 수 있음.

### 6.6 ProxySQL 진단

명령

```bash
kubectl exec -it kosa-pxc-proxysql-0 -n pii-protected -- \
  mysql -h127.0.0.1 -P6032 -uproxyadmin -p
```

mysql 안에서:

```sql
SELECT hostgroup_id, hostname, port, status FROM mysql_servers;
```

기대 출력

```
+--------------+----------------------+------+--------+
| hostgroup_id | hostname             | port | status |
+--------------+----------------------+------+--------+
| 10           | kosa-pxc-pxc-0.kosa..| 3306 | ONLINE |
| 20           | kosa-pxc-pxc-0.kosa..| 3306 | ONLINE |
| 20           | kosa-pxc-pxc-1.kosa..| 3306 | ONLINE |
| 20           | kosa-pxc-pxc-2.kosa..| 3306 | ONLINE |
+--------------+----------------------+------+--------+
```

`10 = writer hostgroup` (pxc-0이 단일 라이터), `20 = reader hostgroup` (3노드 모두 읽기). 노드
죽으면 `30 = offline hostgroup` 으로 빠짐.

---

## 7. 함정 + 디버깅 (우리가 진짜 만난 것)

### 함정 1. WATCH_NAMESPACE가 Operator의 ns만 → CR이 무시됨

#### 증상

`pii-protected`에 PXC CR을 만들었는데 STS도, Pod도, Service도 안 생김. Events 비어 있음. Operator
로그엔 아무 메시지 없음.

```bash
kubectl logs -n pxc-operator deployment/percona-xtradb-cluster-operator
# (PXC CR 관련 로그 0)
```

#### 원인

Operator는 기본적으로 **자기 namespace의 CR만** 감시해요. `WATCH_NAMESPACE` 환경변수 값이 그걸 결정.

```yaml
env:
  - name: WATCH_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace # ← 자기 ns만
```

`pxc-operator` ns 안의 CR만 보니까, `pii-protected` ns에 있는 CR은 안 보이는 거예요.

#### 해결

**(옵션 A — 비추) 단일 ns 통합**: PXC도 `pxc-operator`에 두기. 보안 분리 깨짐.

**(옵션 B 권장) WATCH_NAMESPACE를 multi-namespace로**:

```bash
# 1) Operator deployment 수정
kubectl edit deployment -n pxc-operator percona-xtradb-cluster-operator
```

```yaml
# valueFrom 부분 통째로 지우고 value로 교체
env:
  - name: WATCH_NAMESPACE
    value: "pxc-operator,pii-protected"
```

```bash
# 2) Role을 pii-protected에도 복제
kubectl get role -n pxc-operator -o yaml | \
  sed "s/namespace: pxc-operator/namespace: pii-protected/g" | \
  kubectl apply -f -

# 3) RoleBinding으로 Operator의 SA에 권한 부여
kubectl create rolebinding pxc-operator-binding \
  -n pii-protected \
  --serviceaccount=pxc-operator:percona-xtradb-cluster-operator \
  --role=percona-xtradb-cluster-operator
```

**(옵션 C 비추 — cluster-scope) `WATCH_NAMESPACE=""`** : 모든 ns 감시. 대신 **ClusterRole +
ClusterRoleBinding 필요**. namespace-scoped Role만 있으면 RBAC forbidden → Operator
CrashLoopBackOff.

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s Operator SDK의 **Manager** 객체는 어떤 namespace의 리소스를 watch할지 시작 시점에 정해요. 이건
informer cache를 효율적으로 운영하기 위함인데, 부작용으로 "다른 ns의 CR은 아예 모름"이 됩니다.

Helm 차트 기본값은 보수적으로 **자기 ns만** 감시. 보안 측면에선 좋지만 (Operator의 권한 최소화),
namespace 분리를 시도하면 첫 함정으로 만나게 돼요.

이 패턴은 cert-manager, ArgoCD, Prometheus Operator 등 거의 모든 Operator에 공통이에요. "ns 분리하면
watch + RBAC 함께 옮겨야 함" 패턴.

---

### 함정 2. PXC CR의 storageClassName은 immutable

#### 증상

PXC 클러스터를 `ceph-rbd` (옛 SC)로 만든 상태에서 `team2-rbd-block`으로 바꾸려고 CR을
`kubectl apply`:

```
The PerconaXtraDBCluster "kosa-pxc" is invalid:
spec.pxc.volumeSpec.persistentVolumeClaim.storageClassName:
  Invalid value: "team2-rbd-block": field is immutable
```

#### 원인

`storageClassName`은 PVC의 immutable 필드예요. K8s API 레벨의 제약이라 Operator가 우회 못 함. 한 번
PVC가 만들어지면 해당 SC로 못 바꿔요.

#### 해결 (CR 재생성)

```bash
# 1) 현재 CR을 파일로 추출
kubectl get pxc kosa-pxc -n pii-protected -o yaml > /tmp/pxc.yaml

# 2) vi로 정리
# - metadata: resourceVersion, uid, generation, creationTimestamp, managedFields 삭제
# - status: 통째로 삭제
# - storageClassName: ceph-rbd → team2-rbd-block (pxc + proxysql 2군데)

# 3) CR 삭제
kubectl delete pxc kosa-pxc -n pii-protected

# 4) STS도 잔재 정리 (함정 3 참고)
kubectl delete sts -n pii-protected --all --force --grace-period=0
kubectl delete pvc -n pii-protected --all

# 5) 5초 대기 후 재생성
sleep 5
kubectl apply -f /tmp/pxc.yaml
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s는 PVC의 일부 필드를 immutable로 못 박았어요. 이유:

- **데이터 일관성**: SC를 바꾸면 PV가 가리키는 백엔드 스토리지가 달라지는데, 그 사이 데이터
  마이그레이션을 자동화하는 건 불가능. 사람이 직접 해야 함.
- **인덱싱**: PV ↔ PVC 매핑이 SC 단위로 인덱싱되어 있어서 중간에 바꾸면 매핑 깨짐.

Operator도 이 제약을 못 넘어요. **DB 운영의 진리: 한 번 SC 정하면 끝**. 운영 환경 들어가기 전에 SC
이름과 백엔드 신중히 결정하세요.

---

### 함정 3. 옛 STS + PVC 잔재가 옛 SC를 계속 참조

#### 증상

함정 2 해결한답시고 CR 재생성했는데, 또 옛 SC로 PVC가 만들어지고 Pending.

#### 원인

CR을 지워도 **STS는 즉시 안 지워질 수 있어요**(Operator가 GC하기 전 race condition). 살아있는 STS는
자기 volumeClaimTemplate로 계속 PVC 만들어요. 옛 SC 이름으로.

#### 해결

함정 2의 4단계에서 STS+PVC 강제 정리하는 게 핵심:

```bash
kubectl delete sts -n pii-protected --all --force --grace-period=0
kubectl delete pvc -n pii-protected --all

# finalizer로 안 빠지면
for pvc in $(kubectl get pvc -n pii-protected -o name); do
  kubectl patch $pvc -n pii-protected --type='merge' \
    -p '{"metadata":{"finalizers":null}}'
done
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s의 ownerReferences/GC는 비동기예요. Owner(CR) 지워도 자식(STS)이 즉시 사라지지 않을 수 있어요.
특히 finalizer가 걸려있으면 더 오래 남아요.

게다가 STS의 `volumeClaimTemplate`도 immutable. 결국 CR 재생성 시나리오는 **"CR 삭제 → STS 삭제 →
PVC 삭제 → 모두 비어있는지 확인 → CR 재생성"** 의 4단계를 명시적으로 거쳐야 안전해요.

---

### 함정 4. mysql에서 직접 ALTER USER 해도 비밀번호가 곧 되돌아감

#### 증상

운영 중 root 비밀번호 바꾸려고:

```sql
ALTER USER 'root'@'%' IDENTIFIED BY 'new_password';
```

1~2분 후 다시 접속하면 옛 비밀번호로 돌아와 있음.

#### 원인

Percona Operator는 모든 시스템 user(`root`, `monitor`, `xtrabackup`, `clustercheck`, `proxyadmin`,
`operator`, `replication`)의 비밀번호를 **Secret `kosa-pxc-secrets`** 에서 관리해요. Reconcile
loop가 주기적으로 "Secret 값 = MySQL 실제 비밀번호?" 비교해서 다르면 `ALTER USER`로 되돌려요.

→ MySQL에서 직접 바꾸면 Operator가 "원래 상태와 다름" 으로 인식하고 되돌리는 거예요.

#### 해결 (Secret patch)

```bash
NEW_PW="strong_password_here"
PW_B64=$(echo -n "$NEW_PW" | base64 -w0)

kubectl patch secret kosa-pxc-secrets -n pii-protected --type='json' \
  -p="[{\"op\":\"replace\",\"path\":\"/data/root\",\"value\":\"$PW_B64\"}]"

# Operator가 1~2분 내 반영
sleep 90

# 검증
kubectl exec kosa-pxc-pxc-0 -n pii-protected -- \
  mysql -uroot -p"$NEW_PW" -e "SELECT 'OK' AS test;"
```

다른 시스템 user도 같은 패턴, `/data/root` → `/data/monitor` 등.

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Operator 패턴의 본질은 **"선언적 상태 관리"** 예요. Secret이 진실의 원천(source of truth), MySQL
안의 실제 비밀번호는 그 결과(reconciled state). 진실의 원천이 안 바뀌면 결과도 결국 원천에 수렴해요.

이건 **GitOps 철학과 동일**해요. ArgoCD가 manifest를 진실로 보고 K8s 상태를 거기 수렴시키는 것처럼,
Percona Operator는 Secret을 진실로 보고 MySQL을 거기 수렴시켜요.

운영 교훈: stateful Operator를 쓸 때는 **항상 CR/Secret에 변경**하고, 데이터 플레인(DB 자체)을 직접
건드리지 마세요.

---

### 함정 5. 앱용 user는 Operator가 관리 안 함 — 직접 만들어야

#### 증상

앱(ticket-app)이 DB 접속 시 access denied. Secret엔 `DB_USER=kosa_app`, `DB_PASSWORD=kosa1004`로
박혀 있는데도.

#### 원인

Percona Operator는 **시스템 user만** 관리해요(root, monitor, xtrabackup 등). 앱 워크로드용
user(`kosa_app`)는 안 만들어줘요. 사람이 직접 만들어야 해요.

게다가 PXC는 Galera 클러스터라 한 노드에 만들어도 자동으로 다 복제되긴 하지만, 권한 부여 방향과
hostgroup 매칭에 주의해야 해요.

#### 해결

```bash
kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -uroot -pkosa1004
```

```sql
CREATE DATABASE kosa_tickets CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER 'kosa_app'@'%' IDENTIFIED BY 'kosa1004';
GRANT SELECT, INSERT, UPDATE, DELETE ON kosa_tickets.* TO 'kosa_app'@'%';

FLUSH PRIVILEGES;
```

> 보안 팁: 운영에선 `'%'` 대신 ProxySQL Pod의 CIDR 또는 K8s ClusterIP CIDR만 허용. 학습 환경이라 `%`
> 사용.

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Operator의 책임 범위는 **"인프라 운영에 필요한 user"** 까지예요. xtrabackup이 백업 떠야 하니
xtrabackup user, ProxySQL이 모니터링해야 하니 monitor user... 이것들은 Operator가 자동 생성하고 자동
회전.

앱 user는 **앱의 책임**. Operator는 앱의 도메인 모델을 모르니까요. 어떤 권한이 필요한지(SELECT만?
GRANT? procedure?)는 앱 개발자만 알아요. 그래서 앱 user는 사람(또는 앱의 init container)이 만들고,
비밀번호도 별도 Secret으로 관리해요.

이건 PXC만 그런 게 아니라 거의 모든 DB Operator 공통 패턴이에요 (PostgreSQL Operator, MongoDB
Operator 동일).

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- [Percona Operator for MySQL](https://docs.percona.com/percona-operator-for-mysql/pxc/index.html) —
  우리가 쓴 Operator
- [Galera Cluster Documentation](https://galeracluster.com/library/documentation/) — wsrep, SST, IST
  원리
- [ProxySQL Wiki](https://github.com/sysown/proxysql/wiki) — 쿼리 룰, hostgroup, configuration

### Blog / Talk

- [Percona Blog: PXC 8.0 Best Practices](https://www.percona.com/blog/category/mysql/pxc/) — 실전
  운영 팁
- [MySQL Replication 비교 (Vitess vs GR vs Galera)](https://vitess.io/docs/concepts/) — Vitess 측
  관점이지만 통찰 좋음
- [K8s에서 Stateful 운영 (KubeCon)](https://www.youtube.com/results?search_query=kubecon+stateful+operator)
  — Operator 패턴 일반론

### 우리 프로젝트 내 관련 문서

- `/Users/sangjjang/kosa_infra_project/DB_Schema.md` — 우리 스키마와 CR 예시
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 6.3 — 실제 함정 5개 절차
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md` — 함정 분배

### 한 단계 더

- **PMM(Percona Monitoring and Management)** : DB 전용 모니터링. 슬로우 쿼리, 잠금, replication lag
  시각화.
- **xtrabackup + RGW**: 백업을 Ceph RGW(S3 호환)로. 우리 인프라에 추가 가능.
- **Multi-region Async**: PXC는 동일 DC만 권장. 멀티 리전은 비동기 replica 별도 구성.
- **MySQL Vault / External Secrets**: Secret을 HashiCorp Vault나 AWS Secrets Manager로 외부화.

---

## 다음 챕터 미리보기

다음 챕터 10에서는 **Redis Sentinel** 을 다뤄요. 우리 ticket-app은 좌석 상태 캐시와 분산 락(예매
충돌 방지)에 Redis를 쓰는데, "캐시 마스터 1대 죽으면 어떡하지?"를 풀어주는 게 Sentinel이에요. PXC와
다르게 Redis는 비동기 복제 + Sentinel이라는 다른 HA 패턴을 쓰니까, **동기 vs 비동기** 의
트레이드오프를 한 번 더 비교해볼 좋은 챕터예요. bitnami/redis Helm 차트로 3노드 Sentinel을 띄우는
과정과, "전통 VM 3대 셋업 반나절 → Helm 3분"의 위력을 보여드릴게요.
