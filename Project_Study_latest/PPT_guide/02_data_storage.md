# Part 2. 데이터 & 스토리지 — 발표자 B

- 슬라이드: 09~16 (총 8장)
- 발표 시간: 약 7분 (슬라이드당 약 50초) — 가장 무거운 파트
- 톤: 다크 메인 + 라이트 포인트 1장 (16번 Ceph 성능 검증)
- 역할: OLTP/OLAP 분리 + Ceph 분산 스토리지 + PXC/Redis/Harbor

## 파트 전체 흐름

```
OLTP/OLAP 분리 → WHY Ceph → Ceph 클러스터 → RBD/RGW 듀얼
  → PXC (OLTP DB) → Redis (캐시·대기열) → Harbor (이미지)
  → 성능 검증 (라이트)
```

## 핵심 메시지 1줄

"운영 데이터는 온프레 single source of truth, 분석은 AWS RDS로 분리 — 6 노드 Ceph가 모든 K8s 데이터의 기반"

## 발표 진입 멘트

"안녕하세요. 데이터·스토리지 담당 ○○입니다. 우리 프로젝트의 데이터 계층은 두 갈래로 나뉩니다. 운영 데이터는 온프레미스에 두고, 분석용 읽기 부하는 AWS로 분리하는 OLTP/OLAP 분리 패턴을 적용했습니다."

---

## 09. 데이터 layer 큰 그림 — OLTP vs OLAP 분리 [다크] ⭐최신 반영

### 한 메시지
운영 트래픽은 온프레 PXC, 분석 쿼리는 AWS RDS Replica로 완전 격리

### 들어갈 내용
- 메인 다이어그램 (좌·우 2갈래):

**좌 — 운영 path (OLTP)**:
```
ticket-app (온프레/EKS)
  → ProxySQL
  → PXC 3-node Galera
```

**우 — 분석 path (OLAP)**:
```
admin-app (admin namespace)
  → admin_ro user (SELECT only)
  → AWS RDS Read Replica (10.20.10.54)
Grafana (monitoring ns)
  → admin_ro
  → RDS data source
```

### 왜 분리하는가 (5가지 근거)
1. **Lock 격리** — 무거운 OLAP query 30초가 OLTP 1ms를 멈추지 않음
2. **최적화 방향 정반대** — OLTP는 B-tree index, OLAP은 columnstore
3. **권한 분리** — admin은 read only, 운영 user만 write
4. **SLA가 다름** — OLTP는 100ms 응답, OLAP은 수 초 OK
5. **운영 grade 패턴 일치** — Aurora + Redshift 같은 정통 분리 패턴

### 강조 수치
- replication lag: `Seconds_Behind_Master: 0` (검증됨)

### 발표 멘트
"데이터 계층의 핵심 설계는 OLTP와 OLAP 분리입니다. 사용자 트래픽은 온프레미스 PXC로 가고, 관리자 대시보드와 Grafana 같은 분석 쿼리는 AWS RDS Read Replica로 보냅니다. 이유는 5가지인데 가장 중요한 건 Lock 격리입니다. 관리자가 매출 통계 한 번 새로고침하면서 30초짜리 GROUP BY를 던지면, 그 사이 사용자 수백 명의 예약 요청이 멈출 수 있습니다. 운영 등급 회사들은 이미 다 분리합니다 — Aurora + Redshift, MySQL primary + Read Replica 같은 패턴입니다."

---

## 10. WHY Ceph — 분산 스토리지 선택 [다크]

### 한 메시지
6 노드 + 블록·오브젝트 동시 필요 → Ceph가 자연 선택

### 들어갈 내용
- 4 카드 비교 (가로 또는 2x2):
  - **Local disk** — K8s PV 불가능
  - **NAS** — 단일 노드 SPoF
  - **SAN** — 비싸고 별도 장비
  - **SDS (Ceph)** ⭐ — 6 노드 분산, RBD+RGW 동시
- 결론 카드: "K8s 워크로드 + Harbor 이미지 = Ceph만의 답"

### 강조 수치
- 6 노드 클러스터
- 6 OSD / 6 TB Raw
- 가용 용량: 3-replica 시 2TB

### 발표 멘트
"스토리지 선택지가 4가지 있었습니다. local disk는 K8s 워크로드가 노드 이동하면 데이터를 못 따라가서 탈락, NAS는 단일 노드 SPoF, SAN은 별도 장비 비용. 우리는 6 노드 짜리 별도 클러스터를 받았고, K8s PV와 Harbor S3 백엔드를 동시에 요구하는 환경이라 SDS인 Ceph가 가장 자연스러운 선택이었습니다."

---

## 11. Ceph 클러스터 아키텍처 [다크]

### 한 메시지
6 OSD / BlueStore / 10G Spine-Leaf 패브릭

### 들어갈 내용
- 메인 다이어그램: Spine-Leaf 토폴로지
  - Spine 2대 (10G)
  - Leaf 5대 (10G ECMP)
  - 6 Ceph 노드 (각 1TB HDD × 1)
- 라벨:
  - Public Network / Cluster Network 분리
  - CRUSH + 3-replica
  - BlueStore 백엔드

### 핵심 수치
- 6 OSD / 6TB Raw → 2TB 가용 (3-replica)
- 또는 EC 4+2 시 4TB (단, 6 노드는 EC 최소)

### 발표 멘트
"Ceph 클러스터는 6대 별도 노드입니다. 각 노드에 1TB HDD 하나씩 — 총 6 OSD, 6TB Raw입니다. 데이터 백엔드는 BlueStore로 디스크에 직접 쓰는 차세대 방식이고, 노드 간 트래픽은 Spine-Leaf 10G 패브릭을 사용합니다. Public Network와 Cluster Network를 분리해서 클라이언트 트래픽과 복제 트래픽이 서로 간섭하지 않도록 했습니다. 3-replica 정책이라 가용 용량은 2TB입니다."

---

## 12. RBD + RGW 듀얼 활용 [다크]

### 한 메시지
같은 Ceph 클러스터에서 블록(K8s PV)과 오브젝트(S3) 동시

### 들어갈 내용
- 좌·우 2분할 다이어그램

**좌 — RBD (블록)**:
```
StorageClass team2-k8s-pvc-rbd
  → PVC → PV → Pod 마운트
사용처:
- PXC (3 node, 각 노드 PVC)
- Redis (3 node, 각 노드 PVC)
- Jenkins (8GB)
- Harbor metadata (DB, Redis, Trivy)
- Prometheus TSDB
```

**우 — RGW (S3)**:
```
RGW endpoint http://10.10.10.11:7480
사용처:
- Harbor 이미지 blob (bucket: harbor-registry)
- bucket 사전 생성 + harbor user
- 200GB / 10M objects quota
```

### 발표 멘트
"같은 Ceph 클러스터에서 두 가지 접근 방식을 동시에 씁니다. 첫 번째는 RBD 블록 — K8s의 PersistentVolume으로 사용해서 PXC, Redis, Jenkins, Prometheus 같은 StatefulSet 워크로드의 데이터를 저장합니다. 두 번째는 RGW S3 — Harbor가 컨테이너 이미지 blob을 S3 형식으로 저장합니다. 이게 가능한 이유는 Ceph가 RADOS 위에 여러 인터페이스를 제공하기 때문입니다. CephFS도 있지만 현재 RWX 요구사항이 없어서 미사용입니다."

---

## 13. PXC + RBD — OLTP DB [다크] ⭐신규

### 한 메시지
StatefulSet 3 replica + RBD RWO PVC + Galera 동기 복제로 무손실 보장

### 들어갈 내용
- 메인 다이어그램:
```
ProxySQL (앞단, hg10 default)
   ↓
pxc-0 ←→ pxc-1 ←→ pxc-2   (Galera sync replication)
   ↓        ↓        ↓
PVC-0    PVC-1    PVC-2   (team2-k8s-pvc-rbd, RWO)
   ↓        ↓        ↓
       Ceph RBD pool
```

### 핵심 구성
- **PXC**: Percona XtraDB Cluster (Galera 기반 MySQL 멀티 마스터)
- **K8s StatefulSet**: 3 replica
- **각 Pod**: 안정적 ID (pxc-0/1/2) + 안정적 PVC
- **PVC StorageClass**: team2-k8s-pvc-rbd (RWO RBD)
- **ProxySQL**: 앞단에서 read 분산
- **binlog_format**: ROW (Galera + RDS replica 호환)

### 동작
- Write → 3 노드 동기 복제 → 일관성 보장
- Read → ProxySQL 라우팅
- 1 노드 down → quorum 2 유지 (서비스 무중단)

### 함정
- `volumeClaimTemplates` immutable → ArgoCD ignoreDifferences 필요
- 동기 복제는 latency 민감 → 모든 노드 같은 Spine-Leaf 레그에

### 발표 멘트
"운영 DB는 Percona XtraDB Cluster, 줄여서 PXC입니다. Galera 기반 MySQL 멀티 마스터 동기 복제 솔루션이고, K8s StatefulSet으로 3 replica 띄웠습니다. 각 Pod는 자신의 안정적 PVC를 갖고 Ceph RBD에 저장합니다. 앞단에 ProxySQL을 둬서 read 부하를 분산하고, 한 노드가 죽어도 나머지 2개로 quorum을 유지해서 서비스가 끊기지 않습니다."

---

## 14. Redis Sentinel HA — 캐시 + 대기열 [다크] ⭐신규

### 한 메시지
3 노드 + quorum 2 → 자동 failover ~30초, EKS burst Pod와도 공유

### 들어갈 내용
- 메인 다이어그램:
```
Sentinel 1 (kosa-redis-node-0)  ←→  Sentinel 2  ←→  Sentinel 3
       ↓                              ↓                ↓
   Redis master              Redis replica      Redis replica
        ↑                              ↑                ↑
        └──────── 172.16.23.59:6379 ─────────┘
                          ↑
            온프레 ticket-app ←──── EKS burst Pod (VPN으로 공유)
```

### 핵심 구성
- Helm chart: `bitnami/redis` (Sentinel mode)
- 3 노드 (kosa-redis-node-0/1/2)
- 각 노드 = redis + sentinel 컨테이너 (sidecar)
- quorum 2 → master down 시 자동 failover ~30초
- PVC = RBD (각 노드별 RWO)
- master IP: 172.16.23.59 (EKS burst Pod도 직접 사용)

### 사용처
- **ticket-app 대기열** — LPUSH / RPOP / LLEN
- 세션 캐시
- HPA 메트릭 캐시
- **EKS burst Pod도 공유** — VPN 통해 같은 master 접근

### 검증
- `ckquorum mymaster` → "OK 3 usable Sentinels"
- master kill → 30초 안에 다른 노드로 승격
- EKS Pod cache HIT 6.6ms (40배 빠름)

### 함정
- bitnami specific image tag (예: 8.6.3)는 2025년 이후 docker hub에서 제거 → `latest` 또는 Harbor 미러
- **2 노드 + quorum 2는 SPoF** (1대 죽으면 quorum 깨짐) → 3 노드 최소 필수

### 발표 멘트
"Redis는 Sentinel HA로 구성했습니다. 3 노드에 각각 redis + sentinel을 사이드카로 띄우고 quorum 2로 설정했습니다. master 죽으면 30초 안에 다른 노드가 승격됩니다. 사용처는 ticket-app의 대기열 — LPUSH/RPOP로 FIFO 대기열을 만들었고, 세션 캐시도 여기 둡니다. 한 가지 흥미로운 점은 EKS burst Pod도 VPN 통해 같은 master IP를 사용한다는 겁니다. 캐시 일관성을 양쪽 환경에서 유지하기 위한 설계입니다."

---

## 15. Harbor (Ceph RGW S3 백엔드) [다크]

### 한 메시지
이미지 blob을 Ceph RGW S3로 → 수평 확장 + 단일 디스크 의존 X

### 들어갈 내용
- 메인 다이어그램:
```
Docker push harbor.kosa.team2/library/kosa-tickets:N
   ↓
Harbor (k8s-sys1 노드)
   ↓
   ├── 이미지 blob → Ceph RGW (10.10.10.11:7480)
   │                 ↓ bucket harbor-registry
   │                 6 OSD 분산 저장
   │
   └── 메타데이터 → Ceph RBD PVC (DB / Redis / Trivy)
```

### 핵심 구성
- Helm chart: harbor/harbor 1.16.0 (Harbor v2.12)
- Namespace: harbor
- 배치 노드: k8s-sys1 (workload-type=system)
- 이미지 blob: Ceph RGW S3 bucket
- 메타데이터: Ceph RBD PVC

### 함정 / 노하우
- `disableredirect: true` — RGW가 client에 다시 redirect 보내는 URL이 내부 IP라 외부 client 불가
- `v4auth: true` — SigV4 강제
- **bucket 수동 생성** 필요 (Harbor가 자동 생성 안 함)

### Burst 연결 한 줄
"burst 시 EKS 노드도 같은 Harbor에서 이미지 pull → 양쪽 K8s가 동일 이미지 보장"

### 발표 멘트
"Harbor는 컨테이너 레지스트리인데, 이미지 blob을 Ceph RGW S3에 저장합니다. 단일 디스크에 의존하지 않고 6 OSD에 분산 저장돼서 수평 확장 가능합니다. 메타데이터인 DB와 Redis는 Ceph RBD PVC에 저장합니다. 구축 과정에서 가장 큰 함정이 disableredirect 설정이었습니다 — RGW가 client에게 다시 접속할 URL을 보내는데 그게 내부 IP라서 외부 client는 도달할 수 없습니다. 이 옵션을 true로 줘서 해결했습니다."

---

## 16. Ceph 성능 검증 [라이트 ⭐]

### 한 메시지
HDD가 병목, 네트워크는 멀쩡 — SSD WAL/DB 분리로 4~8배 개선 가능

### 들어갈 내용 (라이트 톤)

**측정 결과 표**:
| 항목 | 측정값 |
|---|---|
| RBD 4K randwrite (cache 포함) | 1,700 IOPS |
| RBD 4K randwrite (cache 우회) | 99 IOPS |
| **RBD 1M seqwrite** | **35 MB/s** ⭐ |
| RADOS 4K randwrite | 99 IOPS |
| iperf3 노드 간 | 9.4 Gbps (= 1,175 MB/s) |
| Pod-Pod (Calico IPIP) | 5.34 Gbps |

**계층별 한계 표**:
| 계층 | 한계 |
|---|---|
| 10G NIC | 1,250 MB/s |
| 6 HDD 합 (100 MB/s × 6) | 600 MB/s |
| 3-replica 적용 | 200 MB/s |
| WAL/DB 같은 HDD (seek thrashing) | 70~100 MB/s |
| **실측** | **35 MB/s** |

**개선 1순위**: SSD WAL/DB 분리
- 노드당 100GB SSD × 6 ≈ 30만원
- 예상 효과: seq write 4~8배, randwrite 5~15배

### 발표 멘트
"성능 검증입니다. RBD 1M sequential write가 35 MB/s, 4K random은 100 IOPS도 안 나옵니다. 처음엔 네트워크 문제인가 했는데 iperf 측정하니 9.4 Gbps 잘 나옵니다. 네트워크는 멀쩡, HDD가 병목입니다. 계층별로 한계를 따져보면 10G NIC은 1,250 MB/s 가능, HDD 6장 합치면 600 MB/s, 3-replica 거치면 200 MB/s, 마지막으로 WAL과 DB가 같은 HDD에 있어서 seek thrashing이 일어나 35 MB/s까지 떨어집니다. 개선 1순위는 SSD WAL/DB 분리입니다 — 노드당 100GB SSD 6장이면 30만원이고 seq write가 4~8배 빨라집니다."

### 다음 발표자에게 패스
"여기까지 데이터 layer 설계와 성능 검증이었습니다. 다음으로 이 위에서 코드가 어떻게 배포되는지 CI/CD 담당 ○○님이 이어가겠습니다."
