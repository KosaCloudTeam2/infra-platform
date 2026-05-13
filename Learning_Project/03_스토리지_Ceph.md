# 03. 스토리지 — Ceph

> Layer 1 / 학습 1일 / 등급 🟡

---

## 학습 목표

- Ceph가 하나의 시스템에서 Block/File/Object 모두 제공하는 원리
- RBD vs CephFS vs RGW — 언제 무엇을?
- BlueStore와 CRUSH map 개념
- K8s에서 Ceph CSI driver로 동적 PV 사용

---

## 1) Ceph의 3가지 인터페이스

```
[애플리케이션]
   │
   ├─ Block Storage (RBD)     ← 우리가 K8s PV로 사용
   │   "디스크처럼" — VM 이미지, K8s PVC
   │
   ├─ File Storage (CephFS)
   │   "파일시스템처럼" — 여러 Pod이 공유 mount
   │
   └─ Object Storage (RGW)
       "S3처럼" — REST API로 객체 저장
   │
[Ceph Cluster (RADOS)]
   │
[OSD 노드 × N]   ← 6대 (각 1TB HDD)
```

하나의 클러스터 = 세 가지 모두 가능. 우리는 **RBD 위주, CephFS 일부**.

---

## 2) Ceph vs 대안

| 항목          | **Ceph**                 | NFS       | GlusterFS | Longhorn         | MinIO       |
| ------------- | ------------------------ | --------- | --------- | ---------------- | ----------- |
| 종류          | 통합 (Block/File/Object) | File      | File      | Block            | Object      |
| 분산          | 완전 분산                | 중앙 서버 | 분산      | K8s 노드 디스크  | 분산        |
| HA            | 자동 (3-replica)         | 별도      | 가능      | 가능             | 가능        |
| 학습 곡선     | 가파름                   | 쉬움      | 중        | 쉬움             | 쉬움        |
| **선택 이유** | 통합 + 이미 보유         | 단일 SPOF | 덜 활성화 | 노드 디스크 부담 | Block 안 됨 |

---

## 3) BlueStore (OSD 백엔드)

이전: FileStore (XFS + journal) — 성능 ↓ 현재: **BlueStore** — 로컬 디스크에 직접 쓰기 (XFS 안
거침). 30% 빠름.

OSD당 권장 RAM: 4~8GB (메타데이터 캐시).

---

## 4) CRUSH 알고리즘

데이터 배치 규칙. "어떤 OSD에 어떤 데이터?"를 결정.

- 데이터 분산 (hot spot 없음)
- 장애 도메인 인식 (다른 rack/host에 replica)
- 노드 추가 시 자동 재분배 (rebalance)

---

## 5) replicas vs erasure coding

| 모드                 | 예시                  | 디스크 효율 | 적합              |
| -------------------- | --------------------- | ----------- | ----------------- |
| **3-replica** (우리) | 데이터 1GB → 3GB 사용 | 33%         | 고성능, 자주 읽음 |
| EC 4+2               | 데이터 4GB → 6GB 사용 | 67%         | 대용량 archive    |

6노드 환경에선 EC도 가능하지만 권장 9+ 노드. 학습용은 3-replica로.

---

## 6) K8s에서 Ceph 사용 — CSI driver

CSI = Container Storage Interface. K8s가 다양한 스토리지를 표준 방식으로 쓰게 해줌.

```
[Pod] PVC 요청
  ↓
[K8s] StorageClass (team2-rbd-block)
  ↓
[Ceph CSI driver] (DaemonSet + Deployment)
  ↓
[Ceph 클러스터] RBD 볼륨 생성
  ↓
Pod에 mount
```

### 자주 하는 오해: "CSI 대신 CephFS 쓰면 안 돼?"

**CSI와 CephFS는 같은 레이어가 아님.** 대체 관계가 아니라 **직교(orthogonal)** 관계.

```
┌─────────────────────────────────────────────┐
│  Kubernetes (Pod, PVC, StorageClass)        │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│  CSI (Container Storage Interface)          │ ← K8s 표준 "프로토콜"
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────┼──────────┬─────────────┐
        ▼          ▼          ▼             ▼
   ceph-csi-rbd  ceph-csi-  aws-ebs-csi   gcp-pd-csi
                 cephfs
        │          │
        ▼          ▼
┌─────────────────────────────────────────────┐
│  Ceph 클러스터 (RBD / CephFS / RGW)         │ ← Ceph "스토리지 타입"
└─────────────────────────────────────────────┘
```

- **CSI** = "어떻게 연결할지" (드라이버 규격)
- **RBD / CephFS / RGW** = "Ceph의 어떤 스토리지를 쓸지"

→ K8s에서 Ceph를 쓰려면 **무조건 CSI 드라이버를 거침**. 진짜 선택지는 **`ceph-csi-rbd` vs
`ceph-csi-cephfs`**.

### RBD vs CephFS — 우리는 왜 RBD?

| 항목          | RBD (Block)                               | CephFS (File)                 |
| ------------- | ----------------------------------------- | ----------------------------- |
| Access Mode   | **RWO** (Pod 1개만)                       | **RWX** (여러 Pod 동시)       |
| 성능          | 빠름                                      | 메타데이터 거쳐서 느림        |
| 추가 데몬     | 없음                                      | **MDS(Metadata Server) 필요** |
| 추가 Pool     | 데이터 pool 1개                           | 데이터 + 메타데이터 2개       |
| 운영 복잡도   | 낮음                                      | 높음                          |
| 적합 워크로드 | DB, Redis, Prometheus (stateful 단일 Pod) | 공유 파일, 다중 Pod 로그      |

우리 워크로드(Percona PXC, Redis, Prometheus)는 전부 **RWO 단일 Pod**이라 RBD가 자연스러움. CephFS는
시간 남으면 보너스로 추가.

---

## 7) Proxmox RBD vs K8s CSI RBD — 2단 중첩 구조

같은 Ceph 클러스터지만 **클라이언트와 용도가 완전히 다른 두 개의 RBD pool**을 운영함.

```
                  Ceph 클러스터 (1개, 물리 6대)
        ┌────────────────────────────────────────────┐
        │  OSD × 6 (1TB HDD)                         │
        │  ├─ Pool: ceph-rbd-team2      ← Proxmox용  │
        │  └─ Pool: team2-k8s-pvc-rbd   ← K8s용 (신규)│
        └────────┬───────────────────────┬───────────┘
                 │                       │
       ┌─────────┘                       └─────────┐
       │ 클라이언트 = Proxmox 호스트              │ 클라이언트 = K8s 워커 노드
       ▼                                            ▼
  ┌────────────────┐                       ┌────────────────────┐
  │ Proxmox(kosa1~4)│                      │ K8s 워커 (VM)      │
  │ ┌────────────┐  │  ◄── 이 VM 자체가    │ ┌──────────────┐   │
  │ │ K8s 워커VM │──┼──── ceph-rbd-team2   │ │ Pod          │   │
  │ │ (디스크는  │  │     pool에 저장됨    │ │ /data 마운트 │◄──┼── team2-k8s-pvc-rbd
  │ │ Ceph RBD)  │  │                      │ │              │   │   pool의 RBD 이미지
  │ └────────────┘  │                      │ └──────────────┘   │
  └────────────────┘                       └────────────────────┘
```

### 핵심 차이

| 항목       | Proxmox RBD                       | K8s CSI RBD                 |
| ---------- | --------------------------------- | --------------------------- |
| 클라이언트 | Proxmox 호스트(하이퍼바이저 커널) | K8s 워커 노드(VM 내부 커널) |
| 매핑 대상  | VM의 가상 디스크 `/dev/vdX`       | Pod 안의 디렉토리 `/data`   |
| 용도       | **VM OS/디스크 자체**             | **Pod의 영구 볼륨(PV)**     |
| 관리 주체  | Proxmox UI / `pvesm`              | `kubectl` + PVC             |
| Pool       | `ceph-rbd-team2`                  | `team2-k8s-pvc-rbd`         |
| 인증 user  | (Proxmox 기본 user)               | `client.team2-k8s-csi`      |
| 생명주기   | VM 생성/삭제 시                   | PVC 생성/삭제 시            |
| 프로비저닝 | 수동 (VM 생성 시)                 | 자동 (PVC 요청 시)          |

### "K8s가 Proxmox RBD를 그냥 쓰면 안 되나?"

기술적으론 가능하지만 **안 함**:

1. **레이어 위반** — K8s가 Proxmox API에 종속되면 더 이상 클러스터 매니저가 아니라 Proxmox 종속
   시스템이 됨. AWS hybrid burst 같은 다중 환경도 깨짐.
2. **Pod 이동성 손실** — Pod이 `w1`→`w3`로 옮겨갈 때 PV도 따라가야 함. CSI는 자동 detach/attach.
   Proxmox RBD는 VM 단위라 Pod 단위 이동 불가.
3. **권한/quota 격리** — `client.team2-k8s-csi`는 `team2-k8s-pvc-rbd` pool만 r/w. K8s 폭주가 Proxmox
   VM 디스크에 영향 못 주게 격리.

---

## 8) 모니터(MON) — 왜 여러 대?

Ceph 모니터는 **Paxos 기반 쿼럼**으로 클러스터 상태를 합의함.

```
[client (Proxmox/K8s CSI)]
       │
       ├─→ mon.ceph1 (10.10.10.11)
       ├─→ mon.ceph2 (10.10.10.12)  ─┐
       ├─→ mon.ceph3 (10.10.10.13)   ├ 쿼럼 합의 (과반)
       └─→ mon.ceph4 (10.10.10.14)  ─┘
```

- 모니터 1대 = SPOF, 쿼럼 자체가 성립 안 함 → 보통 3대 또는 5대 홀수 권장
- 클라이언트 설정에 모니터 IP를 **여러 개 명시**하는 이유: 한 대 다운 시 자동 failover
- 실제 IP는 `ceph mon dump`로 확인

---

## 9) 우리 환경 — 네이밍 컨벤션

네이밍 형식: **`team2-<사용주체>-<용도>-<타입>`** — 이름만 봐도 누가 뭘 위해 쓰는지 보임.

### Ceph 측 리소스

| 리소스              | 이름                                          | 풀어쓰면                           |
| ------------------- | --------------------------------------------- | ---------------------------------- |
| 기존 Pool (Proxmox) | `ceph-rbd-team2`                              | Proxmox VM 디스크용 (이미 사용 중) |
| K8s PVC용 Pool      | `team2-k8s-pvc-rbd`                           | team2의 K8s PVC용 RBD pool         |
| K8s CSI 전용 User   | `client.team2-k8s-csi`                        | team2의 K8s CSI 클라이언트         |
| Keyring 파일        | `/etc/ceph/ceph.client.team2-k8s-csi.keyring` | 위 user 키                         |

### K8s 측 리소스

| 리소스        | 이름                        | 풀어쓰면                   |
| ------------- | --------------------------- | -------------------------- |
| StorageClass  | `team2-rbd-block` (default) | team2의 RBD 기반 블록 SC   |
| Secret        | `team2-rbd-csi-secret`      | team2 RBD CSI 자격증명     |
| Secret userID | `team2-k8s-csi`             | `client.` 제외한 user 이름 |
| 테스트 PVC    | `team2-rbd-test-pvc`        | 검증용 임시 PVC            |

### 미래 확장 패턴

```
team2-k8s-cephfs-data      ← CephFS 추가 시 데이터 pool
team2-k8s-cephfs-meta      ← CephFS 메타데이터 pool
team2-cephfs-shared        ← CephFS StorageClass

team2-pxc-backup-rgw       ← Percona XtraBackup → RGW S3 버킷
team2-prom-tsdb-rbd        ← Prometheus 메트릭 저장 (필요 시)
team2-loki-logs-rbd        ← Loki 로그 저장 (선택)
```

### 클러스터 스펙

- Ceph 6대 (별도 물리)
- 1TB HDD × 6 = 6TB Raw / 2TB 가용 (3-replica)
- 10GbE Spine-Leaf 패브릭
- 모니터: `ceph mon dump`로 실제 IP 확인 (예: `.11~.14`)
- 예상 사용량: ~270Gi (Percona 150, Redis 30, Prometheus 50, 기타)

---

## 10) 발표 어필

> _"별도 6대 Ceph 클러스터를 K8s의 영구 스토리지 백엔드로 통합했습니다. 같은 클러스터를 Proxmox VM
> 디스크용(`ceph-rbd-team2`)과 K8s PVC용(`team2-k8s-pvc-rbd`)으로 pool 단위 격리해, 권한과 quota를
> 분리했습니다. CSI driver를 통해 PVC 요청 시 동적으로 RBD 볼륨이 생성되며, 3-replica로 노드
> 장애에도 데이터가 보존됩니다."_

---

## 11) 학습 체크리스트

- [ ] RBD/CephFS/RGW 차이 설명
- [ ] CSI는 인터페이스, CephFS는 스토리지 타입 — 직교 관계 설명
- [ ] RBD를 선택한 이유 (RWO 워크로드, CephFS는 MDS 부담)
- [ ] Proxmox RBD vs K8s CSI RBD — 2단 중첩 구조 설명
- [ ] 같은 Ceph에 pool 분리하는 이유 3가지 (레이어/이동성/권한)
- [ ] 모니터를 여러 대 두는 이유 (Paxos 쿼럼 + failover)
- [ ] `team2-*` 네이밍 컨벤션 풀어쓰기
- [ ] 3-replica vs EC 비교
- [ ] BlueStore 장점
- [ ] CSI driver 동작 흐름

---

## 다음 단원

[`04_K8s_핵심.md`](04_K8s_핵심.md)
