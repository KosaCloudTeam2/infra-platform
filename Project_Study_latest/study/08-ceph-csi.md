# 챕터 08: Ceph CSI Driver — StorageClass, PVC, 그리고 함정들

> KOSA 인프라 프로젝트 학습 시리즈 / Day 4 / 등급 🟡🟡<br> 선수 챕터: 03(스토리지 Ceph), 04(K8s
> 핵심), 07(Helm)

---

## 학습 후 알 수 있는 것

이 챕터를 끝까지 읽고 따라 해보고 나면 여러분은 이런 것들을 설명/실행할 수 있게 됩니다.

- **CSI(Container Storage Interface)가 왜 등장했고**, "K8s 안의 어떤 레이어"인지 한 문장으로 정리할
  수 있어요.
- `ceph-csi-rbd`와 `ceph-csi-cephfs`의 **차이를 워크로드 관점에서** 설명할 수 있어요.
- `StorageClass` → `PVC` → `PV` → `VolumeAttachment` 의 **4단 라이프사이클**을 그릴 수 있어요.
- 우리 환경의 `team2-rbd-block` StorageClass가 **왜 그렇게 이름 붙었는지**, **왜 default가 됐는지**
  설명할 수 있어요.
- ceph-csi의 4가지 Secret 참조(provisioner / controllerExpand / controllerPublish / nodeStage)를
  **왜 모두 명시해야 하는지** 이해해요.
- `fsid` placeholder 캐시, Released PV finalizer, stale STS PVC 같은 **실전 함정**을 만났을 때
  원인부터 짚을 수 있어요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

**Ceph CSI Driver**는 Kubernetes가 표준 CSI 인터페이스를 통해 Ceph 클러스터의 RBD/CephFS 볼륨을
동적으로 프로비저닝하고 Pod에 마운트할 수 있게 해주는 사이드카 + DaemonSet 컴포넌트 집합이에요.

### 1.2 등장 배경

Kubernetes 초기에는 스토리지 드라이버가 **kubelet 바이너리 안에 in-tree**로 들어가 있었어요. AWS
EBS, GCE PD, Ceph RBD, NFS... 전부 K8s 코어 코드베이스에 박혀 있었죠. 문제는 이런 거예요.

- 스토리지 벤더가 K8s 릴리스 사이클에 끌려다님 (벤더가 새 기능 내려면 K8s 메이저 버전 기다려야 함)
- K8s 코어가 자꾸 무거워짐 (벤더별 드라이버를 다 안고 있어야 함)
- 보안 패치도 K8s 릴리스에 묶임

그래서 2017년 K8s 1.9에서 **CSI(Container Storage Interface)** 표준이 alpha로 등장하고, 1.13에서
GA됐어요. 이제는 스토리지 드라이버가 **K8s 외부의 별도 Pod**로 동작해요. K8s는 정의된 gRPC API로만
드라이버랑 통신하니까 **K8s 코어와 드라이버 릴리스가 분리**된 거죠.

> 우리는 이 CSI 표준을 따르는 `ceph-csi-rbd` Helm 차트(v3.16.2)를 깔아서 Ceph 클러스터를 K8s에
> 붙였어요.

### 1.3 핵심 개념 + 용어 풀이

| 용어                     | 한 줄 설명                                                   | 우리 환경 예시                           |
| ------------------------ | ------------------------------------------------------------ | ---------------------------------------- |
| **CSI**                  | K8s ↔ 스토리지 드라이버 간 gRPC 표준 인터페이스              | rbd.csi.ceph.com                         |
| **CSI Driver**           | CSI 표준을 구현한 벤더 컴포넌트(Pod로 동작)                  | ceph-csi-rbd (Helm chart 3.16.2)         |
| **Provisioner**          | PVC 요청을 보고 PV/실제 볼륨을 만드는 컨트롤러 사이드카      | csi-rbdplugin-provisioner Deployment     |
| **Node Plugin**          | 노드에 볼륨을 attach/mount 하는 DaemonSet                    | csi-rbdplugin DaemonSet (각 워커 노드)   |
| **StorageClass(SC)**     | "어떤 종류의 스토리지를 어떻게 만들지" 정의하는 K8s 오브젝트 | team2-rbd-block                          |
| **PVC**                  | 사용자가 "1Gi 디스크 주세요" 라고 요청하는 객체              | ticket-app의 data PVC                    |
| **PV**                   | 실제로 만들어진 영구 볼륨 객체(클러스터 레벨)                | pvc-abc...의 PV                          |
| **VolumeAttachment**     | "이 PV가 이 노드에 attach 됐다"를 K8s가 기록하는 객체        | csi-...                                  |
| **RBD**                  | Ceph의 블록 디바이스 (RADOS Block Device)                    | team2-k8s-pvc-rbd 풀의 csi-vol-\* 이미지 |
| **Dynamic Provisioning** | PVC 만들면 PV가 자동 생성 (사전 PV 작성 불필요)              | 우리가 쓰는 방식                         |

### 1.4 동작 원리 (내부 메커니즘)

PVC 하나 만들어졌을 때 내부에서 무슨 일이 일어나는지 시간 순으로 그려볼게요.

```
[1] kubectl apply -f pvc.yaml
        │
        ▼
[2] kube-apiserver: PVC 객체 저장 + Pending 상태
        │
        ▼
[3] external-provisioner 사이드카(=csi-rbdplugin-provisioner Pod 안)
    Watch PVC events → 자기 StorageClass면 픽업
        │
        ▼
[4] CSI gRPC: CreateVolume(name, capacity, secret)
    ceph-csi 컨테이너가 받음
        │
        ▼
[5] ceph-csi가 모니터 IP + secret로 Ceph에 RBD 이미지 생성
    rbd create team2-k8s-pvc-rbd/csi-vol-<uuid> --size 1G
        │
        ▼
[6] PV 객체 자동 생성 (PVC와 binding)
        │
        ▼
[7] Pod 생성 → 스케줄링 → 노드 결정
        │
        ▼
[8] external-attacher: VolumeAttachment 객체 생성
        │
        ▼
[9] node-plugin DaemonSet의 kubelet 호출
    NodeStageVolume → rbd map (커널 모듈) → /dev/rbd0
        │
        ▼
[10] NodePublishVolume → bind mount → /var/lib/kubelet/pods/.../volumes/...
        │
        ▼
[11] Pod 컨테이너에 mount → 사용 가능
```

핵심은 **Provisioner는 Deployment(컨트롤 플레인)** , **Node Plugin은 DaemonSet(워커 모든 노드)**
이라는 점이에요. 볼륨 만들기는 컨트롤 플레인에서 한 번 일어나지만, mount는 Pod가 떠 있는 노드에서
일어나니까요.

### 1.5 주요 기능

- **Dynamic Provisioning**: PVC만 만들면 PV/실제 볼륨이 자동 생성
- **Volume Expansion**: PVC 사이즈만 늘리면 RBD 이미지 + 파일시스템 둘 다 늘려줌
  (`allowVolumeExpansion: true`)
- **Snapshot**: VolumeSnapshot CRD → RBD snapshot
- **Clone**: 기존 PVC를 dataSource로 새 PVC 생성
- **Topology aware**: 특정 zone/region 노드에만 attach (우리는 단일 zone이라 무의미)
- **ReadWriteOncePod**: 1.27+ 에서 같은 노드 안에서도 단일 Pod만 사용 가능

### 1.6 다른 도구와 비교

| 항목        | **Ceph CSI (우리)**               | AWS EBS CSI                 | Longhorn                   | NFS Subdir Provisioner |
| ----------- | --------------------------------- | --------------------------- | -------------------------- | ---------------------- |
| 위치        | 온프레미스                        | AWS                         | 온프레미스                 | 어디든                 |
| 백엔드      | Ceph 클러스터 (별도 6대)          | EBS                         | K8s 노드 로컬 디스크       | NFS 서버               |
| Access Mode | RWO (RBD), RWX (CephFS)           | RWO                         | RWO, RWX (NFS provisioner) | RWX                    |
| HA          | 3-replica 자동                    | AZ 단일, 다중 AZ는 EBS 한계 | replica로 HA               | NFS 서버가 SPOF        |
| 운영 부담   | Ceph 운영 학습곡선 가파름         | 매니지드(0)                 | K8s 안에서만 동작          | 매우 쉬움              |
| 적합        | 통합 스토리지 (Block/File/Object) | AWS 워크로드                | K8s 단일 클러스터          | 공유 파일만 필요할 때  |

> 우리는 **이미 Ceph 6대 클러스터가 있고**, K8s 외에도 Proxmox VM 디스크로 같은 Ceph를 쓰고 있어서
> 자연스럽게 Ceph CSI를 골랐어요.

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 필요한가

"K8s에 stateful 워크로드 올릴 때" 거의 무조건 필요해요. 구체적으로는 이런 경우들이에요.

- **DB on K8s**: Percona PXC, PostgreSQL Operator, Vitess. 우린 PXC가 여기 해당.
- **메시지 큐**: Kafka, RabbitMQ. KafkaTopic은 디스크가 곧 데이터예요.
- **검색 엔진**: Elasticsearch, OpenSearch. 인덱스가 디스크에 있어야 함.
- **모니터링 TSDB**: Prometheus(기본 디스크 보존), Thanos, VictoriaMetrics.
- **캐시 영속화**: Redis(AOF/RDB), Memcached는 보통 메모리만이라 예외.

상태 있는 워크로드를 K8s에 안 올리는 회사도 있지만(외부 RDS/Redis 사용), 온프레미스에선 외부
매니지드 서비스가 없으니 **CSI는 사실상 필수**예요.

### 2.2 업계 표준, 대표 사용 기업/사례

- **CNCF Storage Landscape**: Ceph는 CNCF Graduated 프로젝트 중 하나. ceph-csi는 Ceph 공식 K8s
  드라이버.
- **OpenShift Data Foundation (ODF)**: Red Hat이 OCS(OpenShift Container Storage)를 ODF로 리브랜딩한
  게 **내부적으로 Rook + Ceph + ceph-csi**. 즉 Red Hat 엔터프라이즈 K8s의 기본 스토리지가 이거예요.
- **Rook**: K8s 위에서 Ceph 자체를 운영하는 Operator. 우리는 Ceph가 K8s 외부(별도 6대)에 있어서
  Rook은 안 쓰지만, "K8s on K8s"로 다 우겨넣는 곳은 Rook을 씀.
- **DigitalOcean, OVH, Yandex Cloud** 같은 중급 클라우드들이 내부 블록 스토리지를 Ceph로 운영하는
  걸로 알려져 있어요.

### 2.3 왜 효율이 좋은가 (현업 관점)

- **단일 인터페이스로 멀티 백엔드**: 같은 K8s 매니페스트가 AWS에선 ebs-csi로, 온프레에선 ceph-csi로
  동작. PVC YAML은 그대로.
- **벤더 락인 회피**: in-tree 시절엔 K8s 버전 업그레이드가 스토리지 드라이버 업그레이드를 강제. 이제
  분리.
- **동적 프로비저닝의 운영비 절감**: 옛날 NFS 시절 "스토리지 팀에 디스크 요청 → 1주일" 패턴이 PVC
  하나로 30초.
- **자동 복구**: 노드 죽으면 K8s가 다른 노드에 Pod 재스케줄 → CSI가 자동 attach. 사람 개입 0.

### 2.4 시장 위치

- CSI 표준 자체는 **K8s에서 사실상 100%** (1.21+에서 in-tree 드라이버는 deprecated, 1.27+에서 다수
  제거).
- 온프레미스 K8s 스토리지 점유율은 정확한 통계 없지만, 커뮤니티 체감으론 **Ceph(Rook 포함) >
  Longhorn > Portworx > MinIO+CephFS** 순.
- 클라우드별 매니지드 K8s는 자기 CSI를 씀(AWS EKS = ebs-csi, GKE = pd-csi, AKS = azuredisk-csi).

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

K8s 스토리지로 고려한 옵션 5개를 표로 정리해볼게요.

| 옵션                    | 장점                                              | 단점                                         | 우리 환경 적합도   |
| ----------------------- | ------------------------------------------------- | -------------------------------------------- | ------------------ |
| **Ceph CSI RBD (선택)** | 이미 Ceph 6대 보유, 3-replica HA, 동적 프로비저닝 | 학습 곡선, 함정 많음                         | ★★★★★              |
| Ceph CSI CephFS         | RWX 가능                                          | MDS 데몬 추가, 메타데이터 풀 별도, 성능 느림 | 보너스로 추가 가능 |
| Longhorn                | 설치 쉬움, K8s 안에서만 동작                      | K8s 워커 노드 디스크 부담(메모리 32GB 빠듯)  | ★★                 |
| NFS provisioner         | 가장 쉬움                                         | NFS 서버 SPOF, 성능 낮음                     | ★                  |
| HostPath / local-pv     | 빠름                                              | Pod 이동 불가                                | DB에 못 씀         |

### 3.2 현업 표준과의 정합성

- **OpenShift Data Foundation**이 내부적으로 ceph-csi를 쓰니까, 우리 구성은 사실상 **엔터프라이즈
  표준 패턴**을 자체 구축한 셈이에요.
- AWS로 옮길 때 ebs-csi로 바꾸기만 하면 됨 → **CSI 표준의 이식성**을 데모로 보여줄 수 있어요.

### 3.3 선택 근거 (트레이드오프)

우리가 RBD를 고른 핵심 이유 3가지예요.

1. **이미 Ceph가 있다** — Proxmox VM 디스크가 이미 `ceph-rbd-team2` 풀에 들어가 있어요. K8s용으로 풀
   하나(`team2-k8s-pvc-rbd`) 더 만들면 끝. 새 스토리지 시스템을 도입할 필요가 없었어요.
2. **워크로드 거의 다 RWO** — PXC, Redis(persistence), Prometheus는 전부 단일 Pod이 디스크를
   점유하는 RWO 워크로드예요. RBD가 자연스러워요. CephFS의 RWX가 필요한 곳이 없었어요.
3. **추가 운영 부담 최소** — CephFS는 MDS(Metadata Server) 데몬을 추가로 띄워야 하고, 메타데이터
   풀도 따로 관리해야 해요. 6대 클러스터에 메모리/CPU 추가 부담. RBD는 OSD만 있으면 그냥 동작.

트레이드오프로 포기한 것:

- **RWX 못 씀**: 여러 Pod이 같은 디스크 공유하는 패턴(예: 멀티 Pod 로그 디렉토리)은 못 함. → 우리
  워크로드엔 필요 없음.
- **함정 많음**: Secret 4개 참조, fsid placeholder, finalizer 잔재 등... 이건 7장에서 자세히.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
                  Ceph 클러스터 (외부 별도 6대, 10GbE)
        ┌─────────────────────────────────────────────┐
        │  OSD × 6 (1TB HDD), Mon × 3+                │
        │                                             │
        │  Pool: ceph-rbd-team2     ← Proxmox VM 디스크│
        │  Pool: team2-k8s-pvc-rbd  ← K8s PVC용 (3-rep)│
        │                                             │
        │  User: client.team2-k8s-csi                 │
        │    └─ caps: mon 'profile rbd',              │
        │             osd 'profile rbd pool=team2-...'│
        └──────────────────┬──────────────────────────┘
                           │  (10.10.10.x:6789, monitor IP들)
        ┌──────────────────▼──────────────────────────┐
        │ K8s 클러스터 (VLAN 30: 172.16.23.0/24)      │
        │                                             │
        │ Namespace: ceph-csi-rbd                     │
        │ ├─ csi-rbdplugin-provisioner (Deployment 2) │ ← CreateVolume
        │ ├─ csi-rbdplugin (DaemonSet 3 = w1/w2/w3)   │ ← NodeStage/Publish
        │ ├─ Secret: team2-rbd-csi-secret             │
        │ └─ ConfigMap: ceph-csi-config (fsid+mons)   │
        │                                             │
        │ ClusterScoped:                              │
        │ └─ StorageClass: team2-rbd-block (default)  │
        └─────────────────────────────────────────────┘
```

### 4.2 핵심 설정값과 근거

| 항목                 | 값                     | 왜 이 값?                                                       |
| -------------------- | ---------------------- | --------------------------------------------------------------- |
| Helm chart 버전      | `ceph-csi-rbd 3.16.2`  | K8s 1.30 지원 최신 안정판                                       |
| Namespace            | `ceph-csi-rbd`         | 드라이버 격리, RBAC 관리 단순화                                 |
| Pool 이름            | `team2-k8s-pvc-rbd`    | 네이밍 컨벤션 `team2-<사용주체>-<용도>-<타입>`                  |
| StorageClass 이름    | `team2-rbd-block`      | 위와 동일 컨벤션 + "block"으로 RBD임을 명시                     |
| Default StorageClass | `isDefaultClass: true` | PVC에 storageClassName 안 적어도 동작 (UX)                      |
| imageFeatures        | `layering`             | 커널 RBD 클라이언트 호환성 최대 (다른 feature는 새 커널만 지원) |
| reclaimPolicy        | `Delete`               | 학습 환경: PVC 삭제 시 RBD 이미지도 삭제. 운영은 Retain 추천    |
| Secret 이름          | `team2-rbd-csi-secret` | Helm 기본값(`csi-rbd-secret`)에서 변경 → 함정 1 주의            |
| userID               | `team2-k8s-csi`        | `client.` 접두사 빼고                                           |

### 4.3 다른 컴포넌트와의 연결

```
[Percona PXC PVC]  ─┐
[Redis PVC]         ├─→  team2-rbd-block (default SC)
[Prometheus PVC]    │    │
[Grafana PVC]       ┘    ▼
                       ceph-csi-rbd provisioner
                         │
                         ▼
                       team2-k8s-pvc-rbd pool
                         │
                         ▼
                       csi-vol-<uuid> RBD 이미지 (× N개)
```

`ticket-app`은 stateless라 PVC 안 씀. 디스크 사용자는 PXC/Redis/Prometheus/Grafana만.

---

## 5. 실제 코드 / 설정 파일

### 5.1 Ceph 측 — Pool과 User 만들기

**위치:** `[ceph-mon]` (Ceph 모니터 노드)

```bash
# K8s 전용 RBD 풀 (3-replica, pg 64)
ceph osd pool create team2-k8s-pvc-rbd 64 64 replicated
rbd pool init team2-k8s-pvc-rbd

# K8s CSI 전용 user
ceph auth get-or-create client.team2-k8s-csi \
  mon 'profile rbd' \
  osd 'profile rbd pool=team2-k8s-pvc-rbd' \
  -o /etc/ceph/ceph.client.team2-k8s-csi.keyring
```

**왜 이 옵션?**

- `pg 64` = 풀 사이즈 추정 6TB / 권장 PG당 100MB 정도 = 60 ≈ 64. 너무 작으면 hot spot, 너무 크면
  메모리 낭비.
- `profile rbd` = mon에는 RBD 기본 권한만, osd는 **풀 한정**으로 권한 발급. K8s 폭주가 다른 풀에 못
  가게 격리.
- `-o keyring` = 결과를 파일로 저장. K8s에 넣을 키는 이 파일에서 추출.

### 5.2 K8s 측 — Helm values

**우리 파일 (예시):** `/tmp/ceph-csi-rbd-values.yaml`

```yaml
csiConfig:
  - clusterID: "abcdef12-3456-7890-abcd-..." # ← ceph fsid 결과 그대로
    monitors:
      - "10.10.10.11:6789"
      - "10.10.10.12:6789"
      - "10.10.10.13:6789"
      - "10.10.10.14:6789"

storageClass:
  create: true
  name: team2-rbd-block
  clusterID: "abcdef12-3456-7890-abcd-..." # ← 위 fsid와 동일해야 함
  pool: "team2-k8s-pvc-rbd"
  imageFeatures: "layering"
  reclaimPolicy: Delete
  isDefaultClass: true
  allowVolumeExpansion: true

  # ★ Secret 이름을 기본값에서 바꿨으므로 4개 모두 명시 (함정 1)
  provisionerSecret: team2-rbd-csi-secret
  controllerExpandSecret: team2-rbd-csi-secret
  controllerPublishSecret: team2-rbd-csi-secret
  nodeStageSecret: team2-rbd-csi-secret

secret:
  create: true
  name: team2-rbd-csi-secret
  userID: team2-k8s-csi # ← 'client.' 빼고
  userKey: "AQABcDxxxxxxxxxxxx==" # ← keyring 파일의 key 값
```

**왜 이 옵션? (라인별)**

- `clusterID`: ceph-csi는 한 K8s 클러스터에서 **여러 Ceph 클러스터**를 동시에 쓸 수 있게 설계됨. 그
  식별자가 fsid예요.
- `monitors`: 모니터 IP를 여러 개 명시. 한 대 다운돼도 다른 모니터로 자동 failover. 이거 잘못 박으면
  PVC가 영원히 Pending.
- `imageFeatures: layering`: RBD에는 layering, exclusive-lock, object-map, fast-diff 등 여러
  feature가 있는데, **layering만 켜야** 커널 4.x 이하에서도 mount 가능. 우리는 Ubuntu 24.04 노드라
  더 켜도 되지만 안전하게 기본값.
- `isDefaultClass: true`: PVC YAML에 `storageClassName` 생략하면 자동으로 이걸 씀. ticket-app DB
  Secret 같은 곳에서 매번 SC 이름 적기 귀찮으니까.
- **Secret 참조 4가지**: 이게 핵심 함정이라 8장에서 다시 봅니다.

### 5.3 테스트 PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: team2-rbd-test-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: team2-rbd-block
  resources:
    requests:
      storage: 1Gi
```

---

## 6. 실행 + 결과

### 6.1 Helm 설치

명령

```bash
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd --create-namespace \
  -f /tmp/ceph-csi-rbd-values.yaml
```

기대 출력

```
Release "ceph-csi-rbd" does not exist. Installing it now.
NAME: ceph-csi-rbd
LAST DEPLOYED: Wed May 13 ...
NAMESPACE: ceph-csi-rbd
STATUS: deployed
REVISION: 1
```

### 6.2 Pod 정상 기동 확인

명령

```bash
kubectl -n ceph-csi-rbd get pods
```

실제 출력 (우리 환경)

```
NAME                                          READY   STATUS    RESTARTS   AGE
csi-rbdplugin-2k4xs                           3/3     Running   0          2m
csi-rbdplugin-7m9qj                           3/3     Running   0          2m
csi-rbdplugin-x8h2p                           3/3     Running   0          2m
csi-rbdplugin-provisioner-7c4d5b8c9d-9f8r2    7/7     Running   0          2m
csi-rbdplugin-provisioner-7c4d5b8c9d-zk4m6    7/7     Running   0          2m
```

**해석:**

- `csi-rbdplugin-*` 3개 = DaemonSet (워커 w1/w2/w3에 각 1개)
- `csi-rbdplugin-provisioner-*` 2개 = Deployment (HA를 위해 2 replica, leader election)
- `7/7` = provisioner Pod 안에 사이드카가 7개나 들어 있어요. csi-provisioner, csi-attacher,
  csi-snapshotter, csi-resizer, csi-rbdplugin, liveness-prometheus...

### 6.3 StorageClass 확인

명령

```bash
kubectl get storageclass
```

기대 출력

```
NAME                         PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
team2-rbd-block (default)    rbd.csi.ceph.com   Delete          Immediate           true                   2m
```

`(default)` 표시 = `isDefaultClass: true` 가 잘 들어갔다는 뜻이에요.

### 6.4 PVC bound 검증

명령

```bash
kubectl apply -f team2-rbd-test-pvc.yaml
kubectl get pvc
```

기대 출력

```
NAME                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
team2-rbd-test-pvc    Bound    pvc-abc12345-...                           1Gi        RWO            team2-rbd-block   15s
```

### 6.5 Ceph 측에서도 이미지 생성됐는지

명령 (Ceph 모니터 노드에서)

```bash
rbd ls -p team2-k8s-pvc-rbd
```

기대 출력

```
csi-vol-9f8a3b2c-3d4e-5f6a-7b8c-9d0e1f2a3b4c
```

PVC ↔ RBD 이미지 매핑이 보이죠. CSI provisioner가 만든 거예요.

---

## 7. 함정 + 디버깅 (우리가 진짜 만난 것)

### 함정 1. Secret 참조 4개 누락 — PVC가 영원히 Pending

#### 증상

```bash
kubectl get pvc
# NAME                STATUS    ...
# team2-rbd-test-pvc  Pending

kubectl describe pvc team2-rbd-test-pvc
# Events:
#   Warning  ProvisioningFailed   ... failed to provision volume with StorageClass "team2-rbd-block":
#     rpc error: code = InvalidArgument desc = missing required field csiProvisionerSecretName
```

#### 원인

ceph-csi의 StorageClass는 내부적으로 **4단계 라이프사이클**에서 각각 Secret을 참조해요.

| 단계               | StorageClass 파라미터                               | 언제?                                            |
| ------------------ | --------------------------------------------------- | ------------------------------------------------ |
| provisioner        | `csi.storage.k8s.io/provisioner-secret-name`        | CreateVolume (PVC 생성)                          |
| controller expand  | `csi.storage.k8s.io/controller-expand-secret-name`  | 볼륨 확장                                        |
| controller publish | `csi.storage.k8s.io/controller-publish-secret-name` | attach (현재 RBD는 사용 안 함, 그래도 명시 권장) |
| node stage         | `csi.storage.k8s.io/node-stage-secret-name`         | NodeStageVolume (노드에 처음 mount)              |

Helm chart의 기본 Secret 이름은 `csi-rbd-secret`이에요. 우리는 `team2-rbd-csi-secret`으로 바꿨죠.
그러면 위 4개 파라미터가 **자동으로 새 이름으로 바뀌지 않아요**. values.yaml에 명시 안 하면 기본값
`csi-rbd-secret`을 그대로 박아버려요.

#### 해결

values.yaml에서 4개 다 명시:

```yaml
storageClass:
  provisionerSecret: team2-rbd-csi-secret
  controllerExpandSecret: team2-rbd-csi-secret
  controllerPublishSecret: team2-rbd-csi-secret
  nodeStageSecret: team2-rbd-csi-secret
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

CSI의 4단계는 **각각 다른 권한이 필요할 수 있다**는 설계 철학에서 나온 거예요. 예를 들어 어떤
시스템은 "볼륨 생성 권한"과 "노드 mount 권한"을 다른 사용자로 분리하고 싶을 수 있죠. 그래서 K8s가
4개 secret을 따로 받게 설계했어요.

하지만 ceph-csi는 실제로는 같은 user(`client.team2-k8s-csi`)로 다 처리하니까 같은 Secret을 4번
가리키게 되는 거예요. 디자인의 일반성 vs 우리 케이스의 단순성 사이의 마찰이죠.

---

### 함정 2. ConfigMap fsid placeholder 캐시

#### 증상

values.yaml에 `clusterID: "<5.1의 fsid>"` 같이 placeholder를 적어두고 `helm install`을 먼저 해버린
케이스. 그 후에 진짜 fsid로 바꾸고 `helm upgrade`해도 PVC 생성 시 이런 에러:

```
rpc error: code = InvalidArgument desc =
  clusterID <5.1의 fsid> not found in ceph-csi-config-map
```

#### 원인

ceph-csi-rbd 차트는 `csiConfig` 값을 K8s ConfigMap에 마운트해서 provisioner Pod에 전달해요. Pod이
이미 떠 있으면 ConfigMap이 바뀌어도 **Pod 안의 인메모리 캐시**가 옛 값을 기억할 수 있어요.

게다가 Helm upgrade가 ConfigMap을 변경해도 **Pod를 자동 재시작 안 시켜요**. checksum annotation이
없으면.

#### 해결

```bash
# 1) 진짜 fsid로 치환
sed -i 's/<5.1의 fsid>/abcdef12-.../g' /tmp/ceph-csi-rbd-values.yaml

# 2) Helm upgrade
helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd -f /tmp/ceph-csi-rbd-values.yaml

# 3) Provisioner Pod 강제 재시작 (ConfigMap 다시 읽도록)
kubectl -n ceph-csi-rbd rollout restart deployment csi-rbdplugin-provisioner
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s ConfigMap은 Pod의 volume으로 마운트되면 **kubelet이 주기적으로(약 60초) 동기화**해줘요. 파일
자체는 업데이트됨. 하지만:

- **앱이 파일을 한 번만 읽고 메모리에 캐싱**하면 ConfigMap 변경 안 보임 (ceph-csi가 이 케이스)
- **subPath 마운트**면 동기화 자체가 안 됨

해결책은 두 가지:

1. Pod 재시작 (위 방법)
2. checksum annotation으로 ConfigMap 해시를 Pod template에 박아서 변경 시 자동 rollout (Helm 베스트
   프랙티스)

ceph-csi 차트는 후자를 기본 제공 안 해요. 그래서 수동 restart 필요.

---

### 함정 3. Released PV가 finalizer로 안 빠짐

#### 증상

PVC 삭제했는데 PV가 한참 `Released` 상태로 남아 있음:

```bash
kubectl get pv
# pvc-abc...   1Gi   RWO   Delete   Released   default/team2-rbd-test-pvc   team2-rbd-block   30m
```

`kubectl delete pv pvc-abc...` 해도 끝없이 Terminating. `kubectl describe`에 finalizer가 남아
있어요:

```yaml
metadata:
  finalizers:
    - kubernetes.io/pv-protection
    - external-provisioner.volume.kubernetes.io/finalizer
```

#### 원인

`reclaimPolicy: Delete`인 PV는 PVC 삭제 시 ceph-csi가 RBD 이미지를 지우려고 시도해요. 그런데
이미지가 어떤 이유로든 못 지워지면(예: Ceph 측에서 watcher가 남아있거나, 이미지가 이미 수동
삭제됐거나) provisioner가 무한 retry. 그 사이 finalizer가 안 빠져요.

#### 해결

**(빠른 해결)** finalizer 강제 제거:

```bash
kubectl patch pv pvc-abc... --type='merge' \
  -p '{"metadata":{"finalizers":null}}'
```

**(근본 해결)** Ceph 측 정리도 같이:

```bash
# Ceph 모니터에서
rbd ls -p team2-k8s-pvc-rbd
rbd info team2-k8s-pvc-rbd/csi-vol-<orphan>
rbd rm team2-k8s-pvc-rbd/csi-vol-<orphan>
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s finalizer는 "삭제하기 전에 누군가 정리 작업을 해야 한다"는 마커예요. 정리가 끝나면 그 컨트롤러가
자기 finalizer를 빼주고, 모든 finalizer가 빠진 후에야 객체가 진짜 삭제돼요.

`external-provisioner.volume.kubernetes.io/finalizer`는 ceph-csi의 external-provisioner 사이드카가
박는 거예요. "내가 RBD 이미지 정리 끝낼 때까지 PV 못 지움" 의 의미. RBD 정리가 영원히 안 끝나면 PV도
영원히 안 지워지죠.

운영에선 `--type='merge' ... finalizers:null` 보다 **Retain reclaim policy**로 가서 사람이
명시적으로 지우는 게 안전해요. 학습 환경이라 Delete로 두지만요.

---

### 함정 4. 옛 StatefulSet의 stale PVC

#### 증상

PXC 클러스터를 재구성하려고 PXC CR을 새 SC(`team2-rbd-block`)로 바꿨는데, PVC가 자꾸 옛
SC(`ceph-rbd`)로 만들어지면서 Pending:

```bash
kubectl describe pvc datadir-kosa-pxc-pxc-0 -n pii-protected
# Events:
#   Warning  ProvisioningFailed   ...
#     storageclass.storage.k8s.io "ceph-rbd" not found
```

#### 원인

PXC CR이 만드는 **StatefulSet의 `volumeClaimTemplate`** 이 옛 SC 이름을 그대로 기억하고 있어요.
StatefulSet은 한 번 만들어진 후 volumeClaimTemplate가 **immutable**. PXC CR을 바꿔도 STS의 템플릿은
안 바뀌어요.

게다가 STS가 살아있는 동안 자기 Pod이 죽으면 자동 재생성 → 옛 템플릿으로 PVC 만들기 → 옛 SC 참조 →
Pending → 무한 루프.

#### 해결

```bash
# 1) STS 통째로 삭제 (Operator가 재생성하려고 하면 강제로)
kubectl delete sts -n pii-protected --all --force --grace-period=0

# 2) PVC도 다 정리
kubectl delete pvc -n pii-protected --all

# 3) finalizer 안 빠지는 PVC 있으면
for pvc in $(kubectl get pvc -n pii-protected -o name); do
  kubectl patch $pvc -n pii-protected --type='merge' \
    -p '{"metadata":{"finalizers":null}}'
done

# 4) PXC CR도 재생성 (storageClassName immutable이라)
kubectl get pxc kosa-pxc -n pii-protected -o yaml > /tmp/pxc.yaml
# vi로 status, resourceVersion, uid 등 metadata 정리
kubectl delete pxc kosa-pxc -n pii-protected
sleep 5
kubectl apply -f /tmp/pxc.yaml
```

#### ★ 왜 이 함정이 발생하는가 (메커니즘)

K8s 객체에는 **`immutable` 필드**가 곳곳에 있어요. StatefulSet의 `volumeClaimTemplate`, PVC의
`storageClassName`, Pod의 `nodeSelector` 일부 등. 이건 의도된 설계예요. "이미 만들어진 디스크의 SC를
바꾸면 데이터가 어디 있는지 모호해진다"는 이유.

문제는 이게 K8s API 레벨의 제약이라 **CR이 STS를 만들어주는 Operator**도 우회 못 한다는 거예요.
Operator는 STS를 새로 만들지 못하니까(이미 있음), CR 변경이 STS에 반영 안 됨. → 사람이 STS/PVC 다
지우고 다시 만들게 해야 함.

이게 stateful 워크로드 운영의 매운맛이에요. **DB의 SC 한 번 정하면 끝까지 가져가야 함**, 또는
마이그레이션 시 풀 리셋 각오해야 함.

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- [CSI Spec (kubernetes-csi/spec)](https://github.com/container-storage-interface/spec/blob/master/spec.md)
  — gRPC 인터페이스 원문
- [ceph-csi GitHub](https://github.com/ceph/ceph-csi) — 우리가 쓴 드라이버의 소스
- [Ceph CSI Docs](https://docs.ceph.com/en/latest/cephadm/services/csi/) — 공식 가이드
- [Kubernetes CSI Sidecars](https://kubernetes-csi.github.io/docs/sidecar-containers.html) — 7개
  사이드카 각각이 뭘 하는지

### Blog / Talk

- [How CSI works (Daniel Mangum)](https://danielmangum.com/posts/how-csi-works/) — 시각화 좋음
- [Rook + Ceph 발표 (KubeCon)](https://www.youtube.com/results?search_query=rook+ceph+kubecon) —
  다양한 영상
- [Percona on Kubernetes (Storage 관점)](https://www.percona.com/blog/percona-kubernetes-operators/)
  — 우리 PXC 운영 컨텍스트

### 우리 프로젝트 내 관련 문서

- `/Users/sangjjang/kosa_infra_project/docs/learning/03_스토리지_Ceph.md` — Ceph 기초
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 5 — 실제 설치 절차
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md` — 함정 표

### 한 단계 더

- **VolumeSnapshot CSI**: PVC를 스냅샷 → 다른 PVC로 복원. 백업 시나리오.
- **Ceph CSI CephFS**: RWX가 필요해지면 같은 패턴으로 CephFS 드라이버 추가.
- **Rook**: K8s 안에서 Ceph 자체를 운영하는 Operator. K8s on K8s 시나리오.

---

## 다음 챕터 미리보기

다음 챕터 9에서는 **Percona XtraDB Cluster (PXC + Operator + ProxySQL)** 을 다뤄요. 이번 챕터에서
만든 `team2-rbd-block` StorageClass가 곧 PXC의 데이터 디스크 백엔드가 되거든요. Galera 동기 복제의
원리, K8s Operator 패턴, ProxySQL의 R/W 분기, 그리고 우리가 진짜 만난 함정 5가지(`WATCH_NAMESPACE`,
immutable storageClassName, stale STS, root 비밀번호 변경, 앱 user 별도 관리)를 풀어볼 예정이에요.
