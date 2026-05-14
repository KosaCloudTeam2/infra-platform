# 챕터 10: Redis Sentinel — 캐시도 HA가 필요해요

> KOSA 인프라 프로젝트 학습 시리즈 / Day 5 / 등급 🟡🟡<br> 선수 챕터: 04(K8s 핵심), 07(Helm),
> 08(Ceph CSI), 09(PXC)

---

## 학습 후 알 수 있는 것

- **Redis가 무엇이고**, 어떤 자료구조를 in-memory로 제공하는지 핵심만 짚어요.
- **Sentinel이 왜 등장했는지**, master 죽었을 때 어떻게 자동 failover를 일으키는지 설명할 수 있어요.
- **Redis Sentinel vs Redis Cluster**의 차이를 "샤딩 vs HA"로 정리해서 답할 수 있어요.
- **bitnami/redis Helm 차트**가 어떻게 3-Pod Sentinel 구성을 자동화하는지 보여드려요.
- "VM 3대로 며칠 걸리던 셋업을 Helm으로 3분만에"의 **실질적 차이**가 어디서 오는지 설명할 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Redis Sentinel**은 Redis master-replica 구성에 모니터링과 자동 failover, 클라이언트 디스커버리를
더해주는 **별도 데몬 시스템**이에요.

### 1.2 등장 배경

Redis는 원래 **단일 프로세스 in-memory KV 스토어**로 출발했어요. 빠르고 단순한 게 매력. 하지만 단일
프로세스 = 그 프로세스 죽으면 캐시 전체 다운. 메모리 데이터는 다 사라짐(persistence 켜도 직전 변경분
손실 가능).

대안으로 master-replica 비동기 복제가 들어왔어요. master에 쓰면 replica에 흘러가는 방식. **문제는
master 죽었을 때 누가 새 master 결정?** 사람이 손으로?

→ 이 자동화를 위해 **Redis Sentinel** 이 2012년에 나왔어요. Sentinel 데몬이 별도로 돌면서:

1. 모든 노드 상태 모니터링
2. master 죽었다고 판단하면 replica 중 새 master 선출 (쿼럼 합의)
3. 클라이언트에 "새 master는 X" 라고 알려줌

### 1.3 핵심 개념 + 용어 풀이

| 용어               | 한 줄 설명                                                                 | 우리 환경                            |
| ------------------ | -------------------------------------------------------------------------- | ------------------------------------ |
| **Redis**          | In-memory KV 스토어 (문자열, 리스트, 해시, 셋, 정렬셋, Stream, Pub/Sub 등) | bitnami chart 기반                   |
| **master/replica** | 1 write 노드 + N read 노드 (비동기 복제)                                   | master 1 + replica 2                 |
| **Sentinel**       | master 헬스체크 + 자동 failover 데몬                                       | 3개 Sentinel (Pod에 사이드카로 함께) |
| **quorum**         | failover 의결에 필요한 Sentinel 수                                         | 3 중 2                               |
| **AOF / RDB**      | Redis의 영속화 방식 (Append-Only File / RDB snapshot)                      | persistence enabled                  |
| **MyId**           | Sentinel의 고유 식별자                                                     | Pod별 자동                           |
| **mymaster**       | Sentinel이 모니터링하는 master의 논리적 이름                               | bitnami 기본값 그대로 사용           |
| **Bitnami chart**  | VMware가 메인테인하는 Helm 차트 모음                                       | `bitnami/redis`                      |

### 1.4 동작 원리 (내부 메커니즘)

#### 평상시

```
[App] ─→ Sentinel에 "mymaster의 현재 master 주소 알려줘"
              │
              ▼
       Sentinel: "kosa-app-redis-node-0:6379"
              │
              ▼
[App] ─→ kosa-app-redis-node-0:6379 (master, R/W)
              │
              ├── 비동기 복제 ──→ kosa-app-redis-node-1 (replica, R)
              └── 비동기 복제 ──→ kosa-app-redis-node-2 (replica, R)
```

각 Pod 안에는 **redis 컨테이너 + sentinel 컨테이너** 2개가 같이 돌아요(bitnami chart 기본 구조).

#### Failover 시나리오

```
[T0] kosa-app-redis-node-0 (master) 정상
       │
       ▼
[T1] 노드 OS 죽음 → kubelet이 Pod 못 띄움
       │
       ▼
[T2] Sentinel 1, 2, 3 모두 "node-0이 응답 안함" 감지 (PING 실패)
       │
       ▼
[T3] Sentinel끼리 협의: "정말 죽었나? 쿼럼(2/3) 동의?"
       │
       ▼  쿼럼 도달
[T4] Sentinel이 replica 중 새 master 선출 (오프셋 우선)
       node-1을 새 master로 promote
       │
       ▼
[T5] node-2를 새 master(node-1)의 replica로 재설정
       │
       ▼
[T6] App이 Sentinel에 "현재 master?" → "node-1" 응답 받음
       앱은 자동으로 새 master로 connection 재연결
```

전체 시간: 보통 **10~30초**. 비동기 복제라 직전 변경분 일부 손실 가능성 있음.

### 1.5 주요 기능

- **자동 failover**: master 죽으면 replica 승격
- **Notification**: Pub/Sub으로 클러스터 이벤트 알림 (`+sdown`, `+odown`, `+switch-master` 등)
- **Configuration provider**: 앱이 master 주소를 hard-code 안 해도 됨, Sentinel에 물어봄
- **Reconfiguration**: failover 후 모든 replica를 새 master에 재연결

### 1.6 다른 도구와 비교

| 항목     | **Redis Sentinel (우리)**              | Redis Cluster           | Memcached | Hazelcast          | Apache Ignite   |
| -------- | -------------------------------------- | ----------------------- | --------- | ------------------ | --------------- |
| 종류     | KV 캐시 + HA                           | KV 캐시 + Sharding + HA | KV 캐시   | 분산 데이터 그리드 | 인메모리 컴퓨팅 |
| 샤딩     | X (단일 데이터셋)                      | O (16384 슬롯)          | X         | O                  | O               |
| HA       | Sentinel                               | Cluster 내장            | 없음      | 내장               | 내장            |
| 자료구조 | 풍부 (list/hash/set/sorted set/stream) | 동일                    | 문자열만  | 풍부               | 풍부            |
| Pub/Sub  | O                                      | O                       | X         | O                  | O               |
| 사용처   | 중소~중규모 캐시                       | 대규모 캐시 (수십 GB+)  | 단순 캐시 | 엔터프라이즈       | OLTP/OLAP 혼합  |

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 필요한가

거의 모든 웹 서비스에 등장해요. 대표 패턴:

- **세션 저장소**: 로그인 세션을 stateless 앱 서버 여러 대가 공유. JWT 대안.
- **캐시**: DB 조회 결과 캐싱. 우리 ticket-app도 좌석 상태 캐시에 사용 가능.
- **Rate limiting**: API 호출 횟수 제한 (`INCR + EXPIRE` 패턴).
- **분산 락**: 예매 동시성 제어 (`SETNX` 또는 RedLock 알고리즘).
- **Leaderboard**: 정렬 셋(ZSET)으로 실시간 랭킹.
- **Pub/Sub**: 가벼운 이벤트 버스 (Kafka 안 쓸 때).
- **Queue**: `LPUSH/BRPOP`으로 큐 구현.

이런 워크로드에서 **Redis 마스터 1대만 운영하면 SPOF**. 그래서 HA 필수.

### 2.2 업계 표준, 대표 사용 기업/사례

- **Redis** 자체는 KV 캐시 시장 절대 1위. DB-Engines 랭킹에서 in-memory 카테고리 부동의 1위.
- **Twitter, GitHub, Stack Overflow, Pinterest, Instagram** 등이 공개적으로 Redis 사용을 밝힘.
- 한국에서도 **카카오, 네이버, 쿠팡** 등의 서비스가 Redis로 캐시/세션 운영.
- 매니지드: **AWS ElastiCache, GCP Memorystore, Azure Cache for Redis** — 거의 모든 클라우드에
  매니지드 Redis 있음.
- HA 패턴 선택: **Sentinel(중소)** vs **Cluster(대규모)** vs **매니지드(클라우드)** 가 보편적.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **마이크로초 응답시간**: in-memory + RESP 프로토콜로 디스크 DB의 1000배 빠름.
- **자동 failover의 단순성**: Sentinel은 stateless에 가까워서 운영 부담 적음. Pacemaker/Corosync
  같은 옛날 클러스터 솔루션보다 훨씬 가볍.
- **개발 친화성**: 자료구조 풍부 → 앱 로직을 Redis에 위임 가능. 예: 분산 락을
  `SET key value NX EX 10` 한 줄로.
- **운영비**: 매니지드 Redis vs 자체 Sentinel. 매니지드는 시간당 ~$0.05+ × 노드 수. 우리 온프레는
  0원.

### 2.4 시장 위치

- Redis는 BSD 라이선스에서 2024년 SSPL로 전환되며 fork(Valkey)가 발생. Valkey는 Linux Foundation
  산하로 출발. 우리가 쓴 bitnami 차트는 여전히 Redis 기반.
- CNCF 프로젝트는 아니지만 **K8s 생태계 표준 캐시**로 자리잡음.
- Helm Hub에서 가장 많이 설치되는 차트 Top 10 안에 항상 있음.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 옵션                                | 장점                        | 단점                               | 우리 환경 적합도 |
| ----------------------------------- | --------------------------- | ---------------------------------- | ---------------- |
| **Redis Sentinel (bitnami) (선택)** | 3 Pod로 HA, Helm 한 줄 설치 | 샤딩 없음 (단일 데이터셋)          | ★★★★★            |
| Redis Cluster                       | 무한 샤딩, HA 내장          | 슬롯 관리 복잡, 우리 규모 오버스펙 | ★★               |
| Memcached                           | 매우 단순                   | HA 없음, 자료구조 빈약             | ★                |
| AWS ElastiCache                     | 매니지드 0운영              | 온프레미스 안 됨                   | X                |
| Redis Standalone (master 1대만)     | 가장 단순                   | SPOF, 데모/PoC만 가능              | X                |

### 3.2 현업 표준과의 정합성

- 캐시 규모가 **GB 단위(수십 GB 이내)** 라 Sentinel이 표준. 100GB+ 되면 Cluster로 전환.
- K8s + Sentinel 조합은 bitnami 차트 덕분에 **사실상 디폴트 선택**.

### 3.3 선택 근거 (트레이드오프)

#### 왜 Sentinel (Cluster 대신)?

1. **데이터 규모 작음**: 좌석 100개 + 세션 몇 백 개 수준. 단일 노드 메모리(수백 MB)로 충분. 샤딩
   불필요.
2. **운영 단순성**: Sentinel 3개는 합의 알고리즘 단순. Cluster는 슬롯 재분배, 노드 추가/제거 절차가
   복잡.
3. **앱 클라이언트 단순**: Sentinel-aware 클라이언트면 충분. Cluster는 키 슬롯 계산 + redirect
   처리가 필요.

#### 왜 bitnami chart (수동 설치 대신)?

다음 4장에서 비교해볼게요.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
Namespace: kosa-app
┌───────────────────────────────────────────────────────────┐
│                                                           │
│  StatefulSet: kosa-app-redis-node (3 replicas)            │
│                                                           │
│  ┌─────────────────────┐  ┌─────────────────────┐         │
│  │ kosa-app-redis-     │  │ kosa-app-redis-     │  ...    │
│  │ node-0 (Pod)        │  │ node-1 (Pod)        │         │
│  │                     │  │                     │         │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │         │
│  │  │ redis         │  │  │  │ redis         │  │         │
│  │  │ container     │  │  │  │ container     │  │         │
│  │  │ (port 6379)   │  │  │  │ (port 6379)   │  │         │
│  │  │ master OR     │  │  │  │ replica       │  │         │
│  │  │ replica       │  │  │  │               │  │         │
│  │  └───────────────┘  │  │  └───────────────┘  │         │
│  │                     │  │                     │         │
│  │  ┌───────────────┐  │  │  ┌───────────────┐  │         │
│  │  │ sentinel      │  │  │  │ sentinel      │  │         │
│  │  │ container     │  │  │  │ container     │  │         │
│  │  │ (port 26379)  │  │  │  │ (port 26379)  │  │         │
│  │  └───────────────┘  │  │  └───────────────┘  │         │
│  │                     │  │                     │         │
│  │  PVC: redis-data-   │  │  PVC: redis-data-   │         │
│  │   kosa-app-redis-   │  │   kosa-app-redis-   │         │
│  │   node-0 (8Gi)      │  │   node-1 (8Gi)      │         │
│  └─────────────────────┘  └─────────────────────┘         │
│                                                           │
│  Service: kosa-app-redis-headless     (Pod 직접 디스커버리)│
│  Service: kosa-app-redis              (Sentinel 26379 LB) │
│                                                           │
└───────────────────────────────────────────────────────────┘
```

### 4.2 핵심 설정값과 근거

| 항목                | 값                             | 근거                             |
| ------------------- | ------------------------------ | -------------------------------- |
| Helm chart          | `bitnami/redis`                | K8s 생태계 표준, 활발한 메인테인 |
| Architecture        | `replication`                  | master-replica + Sentinel 모드   |
| sentinel.enabled    | `true`                         | HA 핵심                          |
| Replica count       | 3                              | Sentinel 쿼럼 2/3 위한 최소      |
| master persistence  | enabled, SC `team2-rbd-block`  | 재시작 후 데이터 복구 가능       |
| replica persistence | enabled, SC `team2-rbd-block`  | 동일                             |
| 비밀번호            | Sealed Secret 또는 외부 Secret | 학습 환경은 평문, 운영은 sealed  |
| Service type        | ClusterIP (기본)               | K8s 내부 앱이 쓰니까 LB 불필요   |
| Resource limit      | 메모리 256Mi (학습용)          | 좌석/세션 데이터셋 작음          |

### 4.3 다른 컴포넌트와의 연결

```
ticket-app ──→ kosa-app-redis.kosa-app.svc.cluster.local:6379
   │              │
   │              ▼ (Sentinel-aware client)
   │       Sentinel에 master 위치 질의
   │              │
   │              ▼
   │       redis://kosa-app-redis-node-0:6379 (master)
   │
   └─→ kosa-pxc-proxysql.pii-protected.svc...:3306 (DB)

ceph-csi-rbd ──→ PVC: redis-data-* (3개)
                  │
                  ▼
              Ceph: team2-k8s-pvc-rbd/csi-vol-*

Prometheus ──→ redis-exporter 사이드카 (옵션)
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 Helm values (간소화)

**우리 파일 (예시):** `/Users/sangjjang/kosa_infra_project/manifests/redis/values.yaml`

```yaml
architecture: replication

auth:
  enabled: true
  password: "kosa1004" # 학습용. 운영은 Sealed Secret

sentinel:
  enabled: true
  quorum: 2

master:
  persistence:
    enabled: true
    storageClass: team2-rbd-block
    size: 8Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      memory: 256Mi

replica:
  replicaCount: 2 # master 1 + replica 2 = 3 Pod
  persistence:
    enabled: true
    storageClass: team2-rbd-block
    size: 8Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      memory: 256Mi
```

**왜 이 옵션? (라인별)**

- `architecture: replication` : bitnami가 master + replica + sentinel 모드를 자동으로 셋업하게
  트리거. 단독 모드는 `standalone`, 샤딩은 별도 chart(`bitnami/redis-cluster`).
- `sentinel.enabled: true` : Sentinel 사이드카를 모든 Redis Pod에 자동 주입. master
  헬스체크/failover 활성화.
- `sentinel.quorum: 2` : Pod 3개 중 2개가 동의하면 failover 진행. 3개 다 동의 필요로 하면 1대 다운
  시 failover 못 함.
- `master.persistence.storageClass: team2-rbd-block` : 챕터 08에서 만든 default SC. PVC가 자동으로
  RBD 이미지 생성.
- `replica.replicaCount: 2` : master 1 + replica 2 = **총 3 Pod**. bitnami 의 master Pod은
  statefulSet의 ordinal 0번이 됨. 사실상 architecture replication에서 replicaCount는 "replica 노드
  수" 의미.
- `memory: 256Mi` : 좌석 100개 + 세션 수백 개 데이터셋 → 수 MB 면 충분. 256Mi는 메모리 fragmentation
  대비.

### 5.2 ticket-app에서 사용 예시 (Python)

```python
# requirements.txt
# redis>=5.0
# pydantic

from redis import Sentinel

sentinel = Sentinel(
    [("kosa-app-redis.kosa-app.svc.cluster.local", 26379)],
    socket_timeout=0.5,
    password="kosa1004",
)

# master 자동 디스커버리
master = sentinel.master_for("mymaster", password="kosa1004")

# 분산 락 (예매 충돌 방지)
ok = master.set(f"seat:lock:{seat_no}", user_id, nx=True, ex=10)
if not ok:
    raise HTTPException(409, "이미 다른 사용자가 예매 중")
```

> 코드는 Sentinel과 통신하고, Sentinel이 현재 master 주소를 알려줘요. master가 failover로 바뀌면
> 클라이언트가 자동 재연결.

---

## 6. 실행 + 결과

### 6.1 Helm 설치

명령

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install kosa-app-redis bitnami/redis \
  -n kosa-app --create-namespace \
  -f /Users/sangjjang/kosa_infra_project/manifests/redis/values.yaml
```

기대 출력

```
NAME: kosa-app-redis
LAST DEPLOYED: ...
NAMESPACE: kosa-app
STATUS: deployed
REVISION: 1
NOTES:
** Please be patient while the chart is being deployed **

Redis can be accessed via the Sentinel hostname:
  kosa-app-redis.kosa-app.svc.cluster.local

For client redirection use the Sentinel:
  kosa-app-redis.kosa-app.svc.cluster.local:26379 (mymaster)
```

### 6.2 Pod 확인

명령

```bash
kubectl get pods -n kosa-app -l app.kubernetes.io/name=redis
```

기대 출력

```
NAME                    READY   STATUS    RESTARTS   AGE
kosa-app-redis-node-0   2/2     Running   0          2m
kosa-app-redis-node-1   2/2     Running   0          2m
kosa-app-redis-node-2   2/2     Running   0          1m
```

`2/2` 의 의미 = Pod 안에 컨테이너 2개 (redis + sentinel) 모두 정상.

### 6.3 현재 master 누군지 확인

명령

```bash
kubectl exec -n kosa-app kosa-app-redis-node-0 -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

기대 출력

```
1) "kosa-app-redis-node-0.kosa-app-redis-headless.kosa-app.svc.cluster.local"
2) "6379"
```

### 6.4 Sentinel 클러스터 상태

명령

```bash
kubectl exec -n kosa-app kosa-app-redis-node-0 -- \
  redis-cli -p 26379 sentinel masters
```

기대 출력 (요약)

```
 1) name
 2) mymaster
 3) ip
 4) <node-0 hostname>
 ...
17) num-slaves
18) "2"           ← replica 2개 인식
19) num-other-sentinels
20) "2"           ← 다른 Sentinel 2개 인식
21) quorum
22) "2"
```

3 Sentinel이 서로 인식하고 합의 가능 상태.

### 6.5 Failover 데모

명령 (master 죽이기)

```bash
kubectl delete pod kosa-app-redis-node-0 -n kosa-app
```

직후 watch

```bash
kubectl exec -n kosa-app kosa-app-redis-node-1 -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name mymaster
```

10~30초 후 기대 출력

```
1) "kosa-app-redis-node-1.kosa-app-redis-headless.kosa-app.svc.cluster.local"
2) "6379"
```

→ master가 node-0에서 node-1로 자동 승격됐어요. App이 Sentinel-aware하면 자동으로 새 master로
connection 갱신.

이후 node-0이 K8s에 의해 다시 뜨면, 자동으로 node-1의 replica로 합류해요.

### 6.6 데이터 영속화 확인

명령

```bash
# 마스터에 값 쓰기
kubectl exec -n kosa-app kosa-app-redis-node-1 -- \
  redis-cli -a kosa1004 SET demo "hello from kosa"

# Pod 모두 재시작
kubectl delete pod -n kosa-app -l app.kubernetes.io/name=redis

# 다시 떴을 때 값 살아있는지
kubectl exec -n kosa-app kosa-app-redis-node-0 -- \
  redis-cli -a kosa1004 GET demo
# "hello from kosa"
```

PVC가 RBD 이미지에 저장돼서 Pod이 다 죽었다 살아나도 값 유지.

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 함정 1. master persistence + replica persistence 불일치

#### 증상

처음 Helm install 시 `master.persistence.enabled: true` 만 켜고 `replica.persistence`는 false로 둠.
그 결과 master 데이터는 살아있지만 replica는 매번 새 마스터에서 풀 sync. SST 부하 + master CPU 폭증.

#### 원인

bitnami chart는 master/replica 설정을 별도 섹션으로 받아요. 한쪽만 enable하면 비대칭 구성이 됨. 다음
그림처럼:

```
master  → PVC O → 재시작해도 데이터 유지
replica → PVC X → 재시작하면 빈 상태 → master에서 풀 sync 재요청
```

#### 해결

values.yaml의 master와 replica 양쪽 모두 persistence 켜기 (5.1 예시).

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Redis replication은 **psync** 프로토콜을 써요. replica가 살아있던 시점 이후의 변경분만 받는 부분
동기화. 그런데 replica가 재시작되면 자기 offset이 0으로 리셋되고, master 측 백로그 범위를 벗어나면
**풀 sync(전체 RDB 덤프 → 전송)** 로 떨어져요.

→ 데이터셋이 크고 replica가 자주 재시작되면 master에 풀 sync 부하 폭증. persistence를 켜서 replica가
살아있던 offset을 유지하게 해야 풀 sync 회피.

---

### 함정 2. Sentinel quorum과 replica 수 불일치

#### 증상

운영 중 Sentinel Pod이 1대 평생 NotReady. Failover가 안 일어남.

#### 원인

`sentinel.quorum: 2` 인데 실제 Sentinel 살아있는 게 1대뿐. 쿼럼 도달 못 함.

K8s 노드 두 대가 동시에 fail 하면 (예: 노드 호스트 OOM으로 evict) Sentinel Pod도 두 개 죽음. 남은
1개로는 합의 못 함.

#### 해결

- **podAntiAffinity로 Pod 분산** (bitnami 기본값으로 들어 있긴 함, 다시 확인)
- 자원 충분히 잡기 (`requests.memory`)
- 노드 6대 운영의 의미: K8s 워커가 충분히 분산되어야 Sentinel도 분산됨

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

쿼럼 기반 합의 시스템(Raft, Paxos, Sentinel)은 모두 "절반 이상" 이라는 수학적 보장이 필요해요. 3대 →
쿼럼 2 → 1대 다운까지 견딤. 2대 다운하면 합의 불가능.

5대로 늘리면 2대까지 견디지만 비용 증가. 우리 규모는 3대 + 노드 분산 잘 챙기는 게 정답.

---

### 함정 3. App이 Sentinel-aware 하지 않으면 효과 0

#### 증상

App이 `redis://kosa-app-redis-node-0:6379` 로 직접 master 박아 두면, failover 후 node-0이 죽었을 때
app도 같이 죽음.

#### 원인

Sentinel의 핵심 기능 중 하나가 **"클라이언트에게 현재 master를 알려주기"**. 하지만 App이 Sentinel
프로토콜을 모르고 단순히 master 호스트만 박아두면 의미 없음.

#### 해결

App 코드에서 Sentinel-aware 라이브러리 사용:

- Python: `redis.Sentinel`
- Java: Jedis의 `JedisSentinelPool`
- Node.js: `ioredis` (Sentinel 옵션)
- Go: `go-redis`의 `NewFailoverClient`

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

Sentinel은 별도 포트(26379)에서 자기 프로토콜로 동작해요. 6379는 일반 Redis 데이터 포트. App이
6379로만 접속하면 Sentinel과 대화 자체를 안 함 → failover 통지 못 받음.

해결책은 App에서 두 가지 중 하나:

1. Sentinel-aware 클라이언트 → Sentinel에 master 주소 질의 → 그 주소로 데이터 접속
2. 매개 프록시(HAProxy 등)가 Sentinel 통지를 받아서 백엔드 자동 갱신

bitnami chart는 1번 가정. ticket-app이 1번 라이브러리 쓰면 됨.

---

## "VM 3대 셋업 반나절 → Helm 3분" 의 진짜 의미

좀 더 풀어볼게요. Helm 한 줄로 끝나는 것들이 옛날에는 얼마나 걸렸는지.

#### 옛날 방식 (VM 3대 + Sentinel 수동)

1. VM 3대 프로비저닝 (1~2시간)
2. 각 VM에 Redis 설치, 버전 맞추기 (30분)
3. `redis.conf` 작성: bind, port, replicaof, masterauth, requirepass (30분)
4. systemd unit 만들기 + 부팅 시 시작 (15분)
5. Sentinel용 `sentinel.conf` 작성: monitor mymaster <ip> 6379 2 (30분)
6. Sentinel systemd unit + 시작 (15분)
7. firewall: 6379, 26379, 17000 (replica peer) 열기 (15분)
8. 모니터링: keepalive 안 되면 어떻게 알지? (1시간+)
9. failover 시 DNS 갱신 or 로드밸런서 갱신 자동화 (반나절+)
10. 디버깅: split-brain, master discovery 실패, ... (∞)

**총 반나절~며칠**.

#### Helm 방식

```
helm install kosa-app-redis bitnami/redis -n kosa-app -f values.yaml
```

**3분**. 위 모든 단계가 chart 안에 내장되어 있고, K8s가 운영해줘요.

핵심은 **"운영 절차의 코드화"** 예요. bitnami chart는 수많은 사람의 운영 노하우(이미 검증된)를
YAML로 박제한 결과물이에요. 우리는 그 합의된 베스트 프랙티스를 즉시 가져다 쓰는 거죠.

이게 K8s + Helm 시대의 본질이에요. **인프라가 코드가 되면, 운영 시간이 기하급수적으로 줄어요.**

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- [Redis Sentinel Documentation](https://redis.io/docs/management/sentinel/) — 원조 문서
- [bitnami/redis Helm chart](https://github.com/bitnami/charts/tree/main/bitnami/redis) — 우리가 쓴
  차트의 values 전체 옵션
- [Redis Replication](https://redis.io/docs/management/replication/) — psync, RDB, AOF 등 복제
  메커니즘

### Blog / Talk

- [Redis Sentinel vs Cluster — 언제 무엇](https://blog.bytebytego.com/) (검색 키워드로 활용)
- [RedLock 알고리즘](https://redis.io/docs/manual/patterns/distributed-locks/) — 분산 락 best
  practice
- [Sentinel 운영 case study](https://redis.io/docs/management/sentinel-clients/) — 클라이언트 구현
  가이드

### 우리 프로젝트 내 관련 문서

- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 6.4 — Redis 설치 절차
- `/Users/sangjjang/kosa_infra_project/inventory.md` — Redis 인스턴스 정보

### 한 단계 더

- **Redis Stack**: RedisJSON, RedisSearch, RedisGraph 등 모듈을 묶은 배포판. 검색 엔진 대체 가능.
- **Redis Cluster**: 데이터셋이 100GB+ 가면 전환 시점. 우리 chart에서 architecture 바꿀 일 생기면
  검토.
- **Valkey**: 2024 fork. 향후 라이선스 이슈 시 대안. 와이어 프로토콜 호환.
- **Persistent Memory (Intel Optane 단종 후) / KeyDB / DragonflyDB**: Redis 성능 최적화 변종들.

---

## 다음 챕터 미리보기

다음 챕터 11에서는 **Prometheus + Grafana** 를 다뤄요. 지금까지 만든 PXC, Redis, Ceph CSI, K8s 노드,
ticket-app... 이 모든 것의 메트릭을 수집하고 시각화하는 게 Prometheus와 Grafana예요. CNCF Graduated
프로젝트 두 개를 묶은 `kube-prometheus-stack` Helm 차트로 25개 이상의 사전 대시보드를 한 번에 띄울
거예요. Pull 모델, ServiceMonitor, PromQL 기초도 함께 봐요. 발표 시연용 그래프(부하 테스트 시 Pod
2→10 폭증)도 여기서 만들어요.
