# 챕터 07 — Ceph (개념 + 클러스터)

> KOSA 인프라 프로젝트 학습 시리즈
> 분량: 12~15 페이지
> 선수 챕터: 02 가상화/Proxmox, 04 Kubernetes 핵심

---

## 학습 후 알 수 있는 것

- **Ceph가 하나의 시스템에서 Block(RBD) + File(CephFS) + Object(RGW)를 모두 제공할 수 있는 이유**, 그 아래의 RADOS 레이어가 무엇인지 그림 그릴 수 있어요.
- **OSD / MON / MDS / MGR**이 각각 무엇을 책임지고, 왜 MON은 홀수(3, 5)대인지 설명할 수 있어요.
- **CRUSH 알고리즘**이 어떻게 "메타데이터 서버 없이" 데이터 배치 위치를 결정하는지 메커니즘 수준에서 이해해요.
- **BlueStore**가 FileStore 대비 왜 빠른지, OSD당 RAM 권장이 왜 4~8GB인지 근거를 댈 수 있어요.
- 우리 환경(별도 6노드 / 1TB×6 / 3-replica)이 왜 그렇게 결정됐는지, 그리고 왜 K8s에서 RBD를 우선 쓰고 CephFS는 나중에 추가하는 전략인지 설명할 수 있어요.
- **3-replica vs Erasure Coding** 트레이드오프를 숫자로 비교해서 토론할 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Ceph는 단일 클러스터에서 Block / File / Object 스토리지 인터페이스를 모두 제공하는, 메타데이터 서버 없이 CRUSH 알고리즘으로 데이터를 분산·복제하는 오픈소스 분산 스토리지 시스템입니다.**

### 1.2 등장 배경

기존 분산 스토리지의 한계:

- **NFS**: 단일 서버 중심 → SPOF (Single Point of Failure)
- **SAN**: 비싸고 폐쇄적
- **GlusterFS**: 파일만 지원 (블록/오브젝트 별도 솔루션 필요)
- **HDFS**: 빅데이터 전용, 일반 IO에 부적합

엔터프라이즈는 한 가지 워크로드만 운영하지 않아요. VM 디스크(블록), 공유 파일(파일), 백업/이미지(오브젝트)가 동시에 필요합니다. 그래서 보통 **3가지 시스템을 따로 운영**해야 했어요.

Ceph는 2006년 박사 논문에서 출발해 **"하나의 클러스터로 3가지 다 제공"** 을 목표로 만들어졌어요. 핵심 아이디어는 다음 둘:

1. **메타데이터 서버 없이 CRUSH로 위치 계산** — 메타 서버 병목/SPOF 없음
2. **RADOS라는 통일된 객체 저장 계층** 위에 RBD/CephFS/RGW를 얹기

2014년부터 Red Hat이 인수, 현재는 IBM 산하 Red Hat에서 주도하며 가장 성숙한 오픈소스 분산 스토리지로 자리잡았어요.

### 1.3 핵심 개념 + 용어 풀이

| 용어 | 한 줄 풀이 |
|---|---|
| **RADOS** | Ceph의 핵심 저장 계층. 모든 데이터를 객체로 저장. |
| **OSD** (Object Storage Daemon) | 디스크 1개를 담당하는 데몬. 데이터의 실제 저장/복제/리커버리 수행. |
| **MON** (Monitor) | 클러스터 멤버십·상태 합의(Paxos 기반). 보통 3~5대. |
| **MGR** (Manager) | 모니터링/대시보드/PG balancing. MON과 페어로 동작. |
| **MDS** (Metadata Server) | CephFS 전용 메타데이터 서버. RBD/RGW는 필요 없음. |
| **RGW** (RADOS Gateway) | S3/Swift 호환 REST API 게이트웨이. |
| **RBD** (RADOS Block Device) | 블록 디바이스 인터페이스 (`/dev/rbd0` 처럼 보임). |
| **CephFS** | POSIX 파일시스템 인터페이스. |
| **Pool** | RADOS 내부의 논리적 데이터 그룹. 풀별로 복제 수/CRUSH 룰 다름. |
| **PG** (Placement Group) | 객체와 OSD 사이의 중간 단위. 객체 → PG → OSD. |
| **CRUSH** (Controlled Replication Under Scalable Hashing) | "어떤 객체를 어떤 OSD에 둘지" 결정하는 해시 알고리즘. |
| **BlueStore** | 현재의 OSD 백엔드. 디스크에 직접 쓰기, WAL+DB+Data 분리 구조. |
| **FileStore** | 옛 OSD 백엔드. XFS 위에 동작, 성능↓. |
| **fsid** | 클러스터 고유 식별자(UUID). CSI 등 클라이언트가 이걸로 식별. |
| **CSI** | Container Storage Interface. K8s ↔ 스토리지 표준 규격. |

### 1.4 동작 원리 (내부 메커니즘)

**객체 쓰기 흐름 (RBD pool에 새 객체 저장)**:

```
[클라이언트]
   "obj42를 풀 team2-k8s-pvc-rbd에 저장하고 싶어"
       │
       ▼
[클라이언트가 직접 CRUSH 계산]
   hash(obj42) % pg_num = PG 17
   CRUSH(PG 17) = [OSD.3, OSD.5, OSD.1]  (3-replica)
       │
       ▼
[primary OSD = OSD.3]
   클라이언트 → OSD.3에 직접 쓰기
       │
       ▼
[OSD.3]
   - 로컬 BlueStore에 쓰기
   - 동시에 OSD.5, OSD.1에 복제 전송
   - 모두 ack 받으면 클라이언트에 ack
       │
       ▼
[클라이언트] 쓰기 완료
```

핵심 포인트:

- **메타데이터 서버 없이 클라이언트가 직접 위치를 계산**해요. 그래서 메타 서버 병목이 원천적으로 없음.
- 클러스터 토폴로지(어느 OSD가 어디 있는지)는 MON이 관리하는 **OSDmap/CRUSHmap**으로 알려져요. 클라이언트는 이걸 받아 계산만 합니다.
- 3-replica는 **동기 쓰기**예요. 3개 모두 ack 받아야 클라이언트에 응답. 그래서 강한 일관성.

### 1.5 주요 기능

| 기능 | 설명 |
|---|---|
| **3가지 인터페이스** | RBD(블록) / CephFS(파일) / RGW(오브젝트/S3) |
| **자동 복제** | 풀별 복제 수 설정. 보통 3-replica. |
| **자동 리커버리** | OSD/노드 다운 시 자동 재복제 (CRUSH가 새 위치 계산) |
| **Erasure Coding** | RAID5/6과 유사. 공간 효율↑, 성능↓ |
| **Snapshot / Clone** | RBD/CephFS 모두 지원 |
| **Multi-site replication** | 데이터센터 간 비동기 복제 |
| **Cache Tier** | SSD를 hot tier로, HDD를 cold tier로 |
| **K8s Native** | Ceph CSI driver로 K8s PVC와 직접 연동 |

### 1.6 다른 도구와 비교

| 항목 | **Ceph** (우리) | NFS | GlusterFS | Longhorn | MinIO |
|---|---|---|---|---|---|
| 인터페이스 | Block/File/Object | File | File | Block | Object (S3) |
| 분산 | 완전 분산 | 중앙 서버 | 분산 | K8s 노드 디스크 | 분산 |
| HA | 자동 (3-replica) | 별도 클러스터링 필요 | 가능 | 가능 | 가능 |
| 학습 곡선 | 가파름 | 쉬움 | 중 | 쉬움 | 쉬움 |
| 적합 워크로드 | 모든 것 | 공유 파일 한정 | 파일 | K8s PV 한정 | 백업/이미지 |
| 운영 인력 요구 | 높음 (전담 SRE 권장) | 낮음 | 중 | 낮음 | 낮음 |
| **우리 선택 이유** | 통합 + 이미 보유 | SPOF 위험 | 덜 활성화 | 노드 디스크 부담 | Block 불가 |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **온프레미스 K8s + 영구 스토리지** — Ceph가 사실상 표준
- **VM 디스크 / 컨테이너 PV / S3 동시 운영** — 한 시스템으로 통합
- **수십 ~ 수백 TB 규모** — 노드 추가만으로 선형 확장
- **HA가 컴플라이언스 요구사항** — 자동 복제 + 리커버리

### 2.2 업계 표준 구성, 대표 사용 기업/사례

- **CERN(유럽 입자물리연구소)**: 수십 PB 규모 Ceph. 가장 큰 공개 사례
- **DigitalOcean**: 자사 클라우드 블록 스토리지가 Ceph 기반
- **국내**: 카카오, NHN Cloud, 네이버 클라우드 플랫폼이 자사 스토리지에 Ceph 채택 사례 공개. SKT/KT/LGU+ 일부 내부 클라우드도 Ceph.
- **OpenStack 표준 백엔드**: Cinder/Glance/Manila/Swift 모두 Ceph 백엔드 지원
- **Proxmox 내장**: Proxmox 8.x 부터 Ceph가 GUI 통합 — 우리가 본 그 화면

### 2.3 왜 효율이 좋은가 (현업 관점)

- **하나의 시스템 = 운영 부담 1/3** — VM/PV/S3 따로 운영할 필요 없음
- **CRUSH로 메타 SPOF 제거** — NFS의 head 서버 같은 병목 없음
- **선형 확장** — 노드 추가가 단순. 옛 데이터는 자동 재분산
- **OSS** — 라이선스 비용 0, 상용 지원은 IBM/SUSE에서 구매 가능

### 2.4 시장 위치

- 오픈소스 분산 스토리지 사실상 1위. CNCF Sandbox(Rook)로 K8s native 운영도 표준화 중.
- 경쟁: **MinIO(S3 전용)**, **Longhorn(K8s 노드 디스크 전용)**, **OpenEBS(K8s native)**. 각각 적합 영역이 다름.
- 트렌드: Rook Operator로 K8s 안에서 운영하는 패턴 증가. 우리는 외부 클러스터(전통 방식).

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 대안 | 인터페이스 | 학습 가치 | 우리 환경 적합 | 최종 판단 |
|---|---|---|---|---|
| **Ceph (외부 6노드)** | RBD/CephFS/RGW | ★★★★★ | ★★★★★ (이미 보유) | ✅ |
| Proxmox 내장 Ceph | RBD 중심 | ★★★ | ★★ (Proxmox 자원 추가 부담) | ✗ |
| Longhorn (K8s) | RBD | ★★★ | ★★ (워커 디스크 부담) | ✗ |
| NFS (단일) | File | ★ | ★ (SPOF) | ✗ |
| MinIO (S3) | Object만 | ★★★ | ★★ (Block 없음) | ✗ |

### 3.2 왜 외부 Ceph (Proxmox 내장 안 쓴 이유)

이건 흔히 헷갈리는 부분이라 따로 정리할게요.

| 항목 | Proxmox 내장 Ceph | **외부 Ceph (우리)** |
|---|---|---|
| 노드 자원 | Proxmox 4대가 하이퍼바이저 + Ceph 동시 | Ceph 전용 6대로 분리 |
| 메모리 | 32GB에 VM + Ceph 같이 → 압박 | Ceph 노드는 OSD만 → 8GB 가능 |
| 장애 격리 | 하이퍼바이저 죽으면 OSD도 같이 죽음 | 분리 — 한 쪽만 영향 |
| 네트워크 | Proxmox 본딩과 충돌 가능 | 10GbE 전용 Spine-Leaf |
| 학습 가치 | Ceph 본질 학습 어려움 | 정공법, 엔터프라이즈 패턴 |

우리 32GB Proxmox 호스트에 Ceph까지 얹으면 메모리가 폭발해요. **분리가 정답**.

### 3.3 왜 K8s에서 RBD 위주, CephFS는 나중에

| 항목 | RBD (Block) | CephFS (File) |
|---|---|---|
| K8s Access Mode | **RWO** (Pod 1개 전용) | **RWX** (여러 Pod 공유) |
| 성능 | 빠름 | 메타데이터 거쳐서 ~30% 느림 |
| 추가 데몬 | 없음 | **MDS(Metadata Server) 필요** |
| 운영 복잡도 | 낮음 | 높음 |
| 적합 워크로드 | DB, Redis, Prometheus (단일 Pod 영속) | 다중 Pod 공유 파일, 로그 |

우리 1차 워크로드는 **Percona PXC × 3, Redis × 3, Prometheus, Grafana, ArgoCD** 같이 **전부 RWO**. RBD가 자연스러워요. 나중에 공유 파일 워크로드(예: 사용자 업로드 이미지) 들어오면 그때 CephFS 추가.

### 3.4 3-replica vs Erasure Coding

| 모드 | 1GB 데이터 → 사용 공간 | 디스크 효율 | 성능 | 권장 노드 수 |
|---|---|---|---|---|
| **3-replica** (우리) | 3GB | 33% | 빠름 | 3+ |
| EC 4+2 | 1.5GB | 67% | 느림 (parity 계산) | 9+ |
| EC 8+3 | 1.375GB | 73% | 더 느림 | 12+ |

우리 6노드는 EC 4+2도 기술적으론 가능하지만, **권장 노드 수의 하한선**이라 OSD 1개 실패 시 회복 안정성이 떨어져요. **3-replica가 정공법**.

### 3.5 현업 표준과의 정합성

- **외부 Ceph + K8s CSI**: OpenStack/Kubernetes 정석 패턴.
- **RBD 우선 + CephFS 옵션**: 카카오/네이버 사내 클라우드와 동일 전략.
- **BlueStore + 3-replica + Spine-Leaf 10GbE**: 엔터프라이즈 권장 베이스라인.

### 3.6 선택 근거 (트레이드오프)

| 선택 | 얻는 것 | 잃는 것 |
|---|---|---|
| **외부 Ceph 6노드** | 장애 격리, 메모리 부담↓ | 노드 6대 추가 운영 |
| **3-replica** | 안정성 + 빠른 회복 | 디스크 효율 33% |
| **RBD 우선** | 운영 단순, 성능↑ | RWX 워크로드 미지원 |
| **HDD 베이스** | 비용↓, 6TB Raw 확보 | NVMe 대비 IO ~10배 느림 |

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
                    Ceph 클러스터 (별도 6노드)
        ┌──────────────────────────────────────────────────┐
        │                                                  │
        │  ceph-01 ─┐                                      │
        │  ceph-02 ─┤  MON × 4 (10.10.10.11~14)            │
        │  ceph-03 ─┤  (Paxos quorum)                      │
        │  ceph-04 ─┘                                      │
        │                                                  │
        │  ceph-05 ─┐                                      │
        │  ceph-06 ─┘  추가 OSD 노드                       │
        │                                                  │
        │  OSD × 6: 노드당 1TB HDD × 1 = 6TB Raw           │
        │                                                  │
        │  Pools:                                          │
        │   - ceph-rbd-team2       (Proxmox VM 디스크)     │
        │   - team2-k8s-pvc-rbd    (K8s PVC, 3-replica)    │
        │                                                  │
        └──────────────────────────────────────────────────┘
                    │ 10GbE Spine-Leaf 패브릭
                    │ (Public + Cluster Network 권장 분리)
                    │
        ┌───────────┼────────────────┐
        ▼                            ▼
   ┌────────────────┐           ┌────────────────────────┐
   │ Proxmox 4대     │           │ K8s 워커 노드 (VM)     │
   │ (kosa1~4)       │           │ (k8s-w1~w3)            │
   │                 │           │                        │
   │ Pool 사용:      │           │ Pool 사용:             │
   │  ceph-rbd-team2 │           │  team2-k8s-pvc-rbd     │
   │ (VM 자체 디스크)│           │ (Pod의 PV)             │
   └────────────────┘           └────────────────────────┘
```

핵심:

- **두 개의 Pool**을 같은 클러스터에서 운영. 권한/quota 분리.
- Proxmox는 호스트 커널이 RBD를 직접 쓰고, K8s는 VM 안의 워커 노드가 CSI driver로 RBD를 씀.
- 같은 Ceph인데 클라이언트가 다르고 인증도 다름.

### 4.2 핵심 설정값과 근거

| 항목 | 값 | 근거 |
|---|---|---|
| Ceph 버전 | `v18+` (Reef) | LTS 라인 |
| OSD 백엔드 | **BlueStore** | FileStore 대비 ~30% 빠름, 현재 표준 |
| 노드 수 | 6대 | 3-replica + 노드 1대 다운 대비 여유 |
| OSD 디스크 | 1TB HDD × 6 = **6TB Raw** | 학습 환경, 발표용 시연 가능 분량 |
| 복제 수 | **3 (3-replica)** | 안정성 우선, EC는 9+ 노드 권장 |
| 가용 용량 | 6TB / 3 = **약 2TB** | replica overhead 반영 |
| MON 수 | 4대 (10.10.10.11~14) | quorum 3/4 — 1대 다운 OK |
| Pool (Proxmox) | `ceph-rbd-team2` | VM 디스크 |
| Pool (K8s) | `team2-k8s-pvc-rbd` | K8s PVC 전용 |
| K8s CSI user | `client.team2-k8s-csi` | 해당 pool만 r/w 권한 |
| K8s StorageClass | `team2-rbd-block` (default) | RBD provisioner |
| 네트워크 | 10GbE Spine-Leaf 패브릭 | 노드 간 복제/리커버리 트래픽 흡수 |

### 4.3 다른 컴포넌트와의 연결

```
[Proxmox kosa1~4]
   ─→ Pool: ceph-rbd-team2
        └─ VM 디스크 (k8s-cp1, k8s-w1, ... 모두)

[K8s 워커 노드 VM]
   ↑ 이 VM 자체가 위 ceph-rbd-team2 pool에 저장됨
   │
   └─ Pod 안에서 PVC 요청 ──→ ceph-csi-rbd ──→ Pool: team2-k8s-pvc-rbd
                                                  └─ csi-vol-xxx 이미지 자동 생성

[ArgoCD] / [Grafana] / [Percona PXC] / [Redis] / [Prometheus]
   └─ 모두 PVC로 team2-k8s-pvc-rbd 사용 (storageClass: team2-rbd-block)
```

**중첩 구조의 의미**: K8s 워커 VM 자체가 Ceph에 있고, 그 VM 안 Pod의 PV도 Ceph에 있어요. 두 레이어가 같은 Ceph를 보지만 **풀이 분리**돼서 권한·용량·장애 영향이 격리됩니다.

---

## 5. 실제 코드 / 설정 파일

### 5.1 Ceph 측 — 풀 + 유저 생성

`[ceph-mon]` 노드에서 실행:

```bash
ceph fsid
```

```bash
ceph mon dump
```

```bash
ceph osd pool create team2-k8s-pvc-rbd 64 64 replicated
```

```bash
rbd pool init team2-k8s-pvc-rbd
```

```bash
ceph auth get-or-create client.team2-k8s-csi \
  mon 'profile rbd' \
  osd 'profile rbd pool=team2-k8s-pvc-rbd' \
  -o /etc/ceph/ceph.client.team2-k8s-csi.keyring
```

**왜 이 옵션?**

- `64 64`: PG/PGP 수. 풀당 100~200 PG가 OSD에 분산되는 게 권장. 6 OSD × ~30 PG = 180 정도가 적절해서 64로 시작 (auto-scaler가 자동 조절).
- `replicated`: 3-replica 모드 (EC 풀이 아님).
- `profile rbd`: RBD 작업에 필요한 권한 셋만 부여. 다른 풀 접근 차단.
- `pool=team2-k8s-pvc-rbd`: **이 풀만** r/w. K8s가 다른 풀(예: ceph-rbd-team2 Proxmox 풀)을 못 건드림 → 권한 격리.

### 5.2 K8s 측 — ceph-csi-rbd Helm values

경로(생성): `/tmp/ceph-csi-rbd-values.yaml`

```yaml
csiConfig:
  - clusterID: "<5.1의 fsid>"
    monitors:
      - "10.10.10.11:6789"
      - "10.10.10.12:6789"
      - "10.10.10.13:6789"
      - "10.10.10.14:6789"

storageClass:
  create: true
  name: team2-rbd-block
  clusterID: "<5.1의 fsid>"
  pool: "team2-k8s-pvc-rbd"
  imageFeatures: "layering"
  reclaimPolicy: Delete
  isDefaultClass: true
  # Secret 이름을 기본값에서 바꿨으므로 4개 모두 명시 필수
  provisionerSecret: team2-rbd-csi-secret
  controllerExpandSecret: team2-rbd-csi-secret
  controllerPublishSecret: team2-rbd-csi-secret
  nodeStageSecret: team2-rbd-csi-secret

secret:
  create: true
  name: team2-rbd-csi-secret
  userID: team2-k8s-csi
  userKey: "<5.1의 keyring 값>"
```

**왜 이 옵션?**

- `monitors` 4개 모두 명시 — 1대 다운돼도 클라이언트가 다른 MON으로 fallback.
- `imageFeatures: "layering"` 만 활성: 모든 커널 버전에서 호환되는 최소 기능셋. exclusive-lock, object-map은 일부 커널에서 미지원.
- `reclaimPolicy: Delete`: PVC 삭제 시 RBD 이미지도 자동 삭제. Retain은 수동 정리 필요해서 학습 환경엔 부담.
- `isDefaultClass: true`: 다른 StorageClass 명시 없으면 자동으로 이걸 사용.
- `Secret 참조 4개 모두 명시`: 함정 1의 원인이었던 부분. 다음 절 참고.

### 5.3 Helm install

```bash
helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd --create-namespace \
  -f /tmp/ceph-csi-rbd-values.yaml
```

**왜 `upgrade --install`?**

- `install`만 쓰면 같은 이름 release 있을 때 "cannot re-use a name" 에러
- `upgrade --install`은 멱등 — 처음이면 install, 있으면 values만 갱신. CI/CD 안전

---

## 6. 실행 + 결과

### 6.1 Ceph 클러스터 상태

```bash
ssh root@10.10.10.12
```

```bash
ceph -s
```

기대 출력:

```
  cluster:
    id:     <fsid>
    health: HEALTH_OK

  services:
    mon: 4 daemons, quorum ceph-01,ceph-02,ceph-03,ceph-04
    mgr: ceph-01(active), standbys: ceph-02
    osd: 6 osds: 6 up, 6 in

  data:
    pools:   2 pools, 128 pgs
    objects: ...
    usage:   ... / 6 TiB
    pgs:     128 active+clean
```

`HEALTH_OK` 확인이 핵심.

### 6.2 K8s 측 CSI 동작 확인

```bash
kubectl -n ceph-csi-rbd get pods
```

```
csi-rbdplugin-aaaaa                  3/3   Running   (각 워커 노드)
csi-rbdplugin-bbbbb                  3/3   Running
csi-rbdplugin-ccccc                  3/3   Running
csi-rbdplugin-provisioner-xxxx       7/7   Running   (controller)
```

```bash
kubectl get storageclass
```

```
NAME                         PROVISIONER         AGE
team2-rbd-block (default)    rbd.csi.ceph.com    3d
```

### 6.3 테스트 PVC

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-rbd-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: team2-rbd-block
  resources:
    requests:
      storage: 1Gi
EOF
```

```bash
kubectl get pvc test-rbd-pvc
```

기대: `STATUS: Bound`.

Ceph 측에서 실제 이미지 확인:

```bash
ssh root@10.10.10.12 'rbd ls -p team2-k8s-pvc-rbd'
```

```
csi-vol-abc123...
```

K8s에서 만든 PVC가 Ceph 측에 실제 RBD 이미지로 잡혀있어요.

### 6.4 운영 명령 모음

| 목적 | 명령 |
|---|---|
| 클러스터 상태 | `ceph -s` |
| 풀 목록 | `ceph osd pool ls` |
| 풀별 사용량 | `ceph df` |
| OSD 상태 | `ceph osd tree` |
| RBD 이미지 목록 | `rbd ls -p team2-k8s-pvc-rbd` |
| 이미지 상세 | `rbd info team2-k8s-pvc-rbd/csi-vol-xxx` |
| 고아 이미지 삭제 | `rbd rm team2-k8s-pvc-rbd/csi-vol-xxx` |

---

## 7. 함정 + 디버깅

### 함정 1 — ceph-csi Secret 참조 4개 누락

**증상**: PVC가 영원히 `Pending`. Events:

```
failed to provision volume: rpc error: ... missing controllerExpandSecret
```

**원인 (메커니즘)**: Ceph CSI는 Secret을 **4가지 시점**에서 참조해요.

| 시점 | Secret 키 |
|---|---|
| PV 프로비저닝 | `provisionerSecret` |
| PVC 확장 | `controllerExpandSecret` |
| Pod에 attach | `controllerPublishSecret` |
| 노드에서 mount | `nodeStageSecret` |

Helm chart의 기본값은 `csi-rbd-secret` 이름을 가정해요. 우리는 `team2-rbd-csi-secret`으로 바꿨기 때문에 **4가지 모두 명시**해야 함. 하나라도 빠지면 그 시점에서 실패.

**해결**: 위 values.yaml처럼 4개 모두 명시.

```yaml
storageClass:
  provisionerSecret: team2-rbd-csi-secret
  controllerExpandSecret: team2-rbd-csi-secret
  controllerPublishSecret: team2-rbd-csi-secret
  nodeStageSecret: team2-rbd-csi-secret
```

**왜 이 함정이 발생하는가**: chart의 default가 단일 이름을 가정하다 보니, 이름을 바꾸는 순간 4곳 모두 명시해야 한다는 게 문서에 묻혀있어요. PV 프로비저닝은 됐는데 확장만 안 되거나, attach는 됐는데 mount가 안 되는 부분 실패 패턴으로 나타나면 거의 이 함정.

### 함정 2 — ConfigMap fsid가 placeholder 그대로

**증상**: csi-rbdplugin 로그에 `unable to get cluster ID` 또는 `clusterID not found in csiConfig`.

**원인**: values.yaml에 `clusterID: "<5.1의 fsid>"` 같이 placeholder 그대로 적용. ConfigMap에도 placeholder가 들어가 있음.

**해결**:

```bash
FSID=$(ssh root@10.10.10.12 'ceph fsid' | tr -d '\r\n')
sed -i "s/<5.1의 fsid>/$FSID/g" /tmp/ceph-csi-rbd-values.yaml
helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd -f /tmp/ceph-csi-rbd-values.yaml
kubectl -n ceph-csi-rbd delete pod -l app=ceph-csi-rbd-provisioner
```

placeholder 치환 후 Pod 재기동.

### 함정 3 — PV Released 상태로 안 빠짐 (finalizer)

**증상**: PVC 삭제했는데 PV가 `Released` 상태로 남아있고 안 사라짐. `rbd ls`에 이미지가 그대로.

**원인**: PV에 `kubernetes.io/pv-protection` finalizer 남아있고, CSI controller가 RBD 이미지 삭제를 반복 retry. 어떤 이유(예: Ceph 측 ConfigMap 잘못된 fsid)로 삭제 명령이 계속 실패하면 finalizer가 안 빠짐.

**해결**:

```bash
kubectl patch pv <PV-이름> --type='merge' \
  -p '{"metadata":{"finalizers":null}}'
```

```bash
ssh root@10.10.10.12 'rbd ls -p team2-k8s-pvc-rbd'
ssh root@10.10.10.12 'rbd rm team2-k8s-pvc-rbd/csi-vol-orphan'
```

**왜 이 함정이 발생하는가**: K8s의 finalizer는 "안전망"이에요. 외부 리소스(Ceph RBD 이미지) 정리가 끝나야 PV 객체를 삭제하도록 막아둔 거. 그런데 외부 정리가 영구적으로 실패하면(예: fsid 불일치) 영원히 안 빠집니다. 강제 제거가 답이지만, 그 뒤 Ceph 측 고아 이미지는 손으로 청소해야 해요.

### 함정 4 — Galera join 시간 vs PV 준비 시간

**증상**: PXC 첫 부팅 시 `pxc-1`이 PVC를 받자마자 갈레라 join 시작했는데, RBD attach가 늦어서 `Permission denied` 또는 `Connection reset`.

**원인**: RBD attach + filesystem mkfs + mount 까지 ~30초 걸림. 그동안 Pod이 시작은 됐는데 `/data` 마운트는 아직 안 돼서 MySQL이 빈 디렉토리에서 부팅 시도.

**해결**: `lifecycle.postStart` 또는 `initContainer`로 mount 완료 대기. 또는 Operator가 readiness probe로 처리. Percona Operator는 후자.

### 함정 5 — Ceph HEALTH_WARN: too few PGs / clock skew

**증상**: `ceph -s`에 `HEALTH_WARN`. 메시지가 `too few PGs per OSD` 또는 `clock skew detected on mon`.

**원인**:
- PG 수가 OSD 대비 너무 적음 (또는 많음). 우리는 6 OSD에 풀 2개 × 64 PG = 128 PG. 권장은 OSD당 100~200 PG → 600~1200. 약간 부족.
- MON 노드 간 시계 차이 > 50ms

**해결**:
- PG: `ceph osd pool set team2-k8s-pvc-rbd pg_autoscale_mode on` 켜두면 auto-scaler가 알아서.
- 시계: chrony/NTP 동기화 확인. `ssh ceph-01 'chronyc tracking'`.

학습 환경에선 HEALTH_WARN을 무시해도 동작 자체엔 문제 없는 경우가 많아요. 발표 직전엔 클리어 권장.

---

## 8. 더 깊이 공부할 자료

### 공식 문서
- Ceph 공식: https://docs.ceph.com/en/latest/
- Ceph CSI: https://github.com/ceph/ceph-csi
- CRUSH 알고리즘 논문: Sage Weil의 박사 논문 "Ceph: A Scalable, High-Performance Distributed File System" (2006)

### 책 / 영상
- *Mastering Ceph* (Packt, 3rd Edition)
- *Learning Ceph* (Packt) — 입문
- Ceph Days / Cephalocon 발표 (YouTube)

### 운영 학습
- **Rook Operator** — K8s 안에 Ceph 운영 (다음 단계)
- **Cephadm** — Ceph 공식 배포 도구
- **ceph-ansible** — Ansible 기반 배포

### 인증
- **Red Hat Certified Specialist in Ceph Cloud Storage** (EX260)
- IBM 산하 Red Hat 트레이닝

### 우리 프로젝트 관련 파일
- `/Users/sangjjang/kosa_infra_project/docs/learning/03_스토리지_Ceph.md` (이전 정리)
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 5 (CSI 설치)
- `/Users/sangjjang/kosa_infra_project/inventory.md` (Pool/User 표)

---

> 다음 챕터 미리보기 — 데이터베이스를 K8s 위에 어떻게 안전하게 올릴까요? Percona Operator로 PXC 3노드 + ProxySQL 2노드를 동기 복제로 묶고, Galera의 SST/IST를 이해합니다.
