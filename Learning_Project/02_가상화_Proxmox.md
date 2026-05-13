# 02. 가상화 — Proxmox VE + Cloud-Init

> Layer 1 / 학습 시간 1일 / 등급 🟡
> 선수: 리눅스 기초, 가상화 개념

---

## 학습 목표

- Proxmox VE의 정체 — VMware 대안 오픈소스
- 클러스터 + HA 동작 원리
- Cloud-Init이 자동화에 왜 필수인가
- 우리 환경의 VM 7대 분산 설계 이유

---

## 1) Proxmox VE란

**Proxmox Virtual Environment** = Debian + KVM + LXC를 묶은 **오픈소스 가상화 플랫폼**.

```
[웹 UI / API]
    ↓
[Proxmox VE 관리 레이어]
    ↓
[KVM (VM)] + [LXC (컨테이너)]
    ↓
[Debian Linux 호스트]
```

기능:
- VM/컨테이너 생성/관리 (Web UI + CLI)
- 클러스터링 (여러 호스트를 묶어 한 화면)
- HA (한 호스트 다운 시 VM 자동 이전)
- 백업/복원
- 스토리지 통합 (LVM, ZFS, Ceph, NFS 등)

---

## 2) 왜 Proxmox? 대안과 비교

| 항목 | **Proxmox VE** | VMware ESXi | Hyper-V | OpenStack |
|---|---|---|---|---|
| 라이센스 | 오픈소스 (구독 선택) | Broadcom 인수 후 상용화 | Windows Server | 오픈소스 |
| 클러스터 | 기본 제공 | vCenter 별도 (유료) | SCVMM 별도 | 기본 |
| 운영 난이도 | 중 | 낮음 (UI 우수) | 중 | 매우 높음 |
| 학습 자료 | 풍부 | 풍부 (단, 변화 많음) | 중 | 풍부 |
| **선택 이유** | 무료 + 안정 + KVM 표준 + Ceph 통합 | - | - | - |

KOSA가 Proxmox를 선택한 이유:
1. **무료** — 학습 환경 부담 없음
2. **KVM 표준** — 업계 표준 가상화 기술 (이력서 가치)
3. **Ceph 통합** — Proxmox와 Ceph가 한 화면에서
4. **클러스터 + HA 기본 제공** — 추가 도구 없이 4대 묶기 가능

---

## 3) Proxmox 클러스터링

### 클러스터 구성

```
[kosa1] ─── corosync ─── [kosa2]
   │                        │
   │      cluster network    │
   │                        │
[kosa3] ─── corosync ─── [kosa4]
```

- **corosync**: 노드 간 상태 동기화 (heartbeat)
- **cluster network**: 별도 네트워크 권장 (관리망과 분리)
- **quorum**: 과반수 (4대 중 3대) 살아있으면 정상 운영

### 우리 환경

4대 묶인 클러스터. Web UI에서 한 화면으로 모든 VM 관리.

---

## 4) Proxmox HA (High Availability)

### 일반 VM vs HA VM

| | 일반 VM | HA VM |
|---|---|---|
| 호스트 다운 시 | VM도 다운 | 다른 호스트로 자동 이전 |
| 디스크 위치 | 로컬 가능 | **공유 스토리지 필수** (Ceph, NFS) |
| 페일오버 시간 | - | 1~2분 |

### 우리 환경에서 HA를 안 쓰는 이유

- VM 디스크는 Ceph에 있어서 **이론적으론 HA 가능**
- 그치만 학습 환경이라 굳이 자동 페일오버 안 함
- **K8s 자체가 HA**라 VM 레벨 HA 필요성 ↓
- 발표 시 "Proxmox HA는 옵션, K8s가 상위 HA 책임" 으로 설명

---

## 5) Cloud-Init — 자동화의 핵심

### 왜 필요한가

VM 1대 만들 때 수동 작업:
1. ISO 부팅
2. 설치 마법사 (언어, 키보드, 디스크 파티션)
3. 사용자 계정 생성
4. SSH 키 등록
5. 네트워크 설정
6. 패키지 업데이트
7. ...

7대 VM에 이걸 반복? 미친 짓.

### Cloud-Init이란

**Cloud-Init** = VM 첫 부팅 시 자동으로 설정 적용하는 표준 도구.

```
[Cloud Image (.img)]  ← 이미 설치된 OS + cloud-init 활성화
    │
    ↓ Proxmox clone
[새 VM]
    │
    ↓ 첫 부팅
[cloud-init 실행]
    - hostname 설정
    - SSH 키 등록
    - 사용자 생성
    - 네트워크 설정
    - 패키지 설치
    ↓
[1분 후 SSH 가능]
```

### Cloud Image vs Live ISO

| | Cloud Image | Live ISO |
|---|---|---|
| 형식 | `.img` (디스크 이미지) | `.iso` (부팅 미디어) |
| 설치 마법사 | **없음** (이미 설치됨) | 있음 |
| Cloud-Init | 기본 활성화 | 별도 설치 필요 |
| 자동화 | 가능 | 어려움 |
| 우리 선택 | ✅ Ubuntu Noble cloud image | ❌ |

### 우리가 만든 템플릿 (VMID 9000)

```
ubuntu-2404-template
├── Ubuntu 24.04 Noble cloud image
├── qemu-guest-agent 사전 설치
├── 디스크: ceph-rbd-team2 (공유 스토리지)
└── Terraform이 이걸 clone해서 7대 VM 만듦
```

상세는 `../project/06_IaC_가이드.md`.

---

## 6) 가상화 네트워킹

### Bridge — 가상 스위치

```
[VM 1] ─┐
[VM 2] ─├─→ [vmbr0] ─→ [eno1 (물리 NIC)] ─→ 외부
[VM 3] ─┘
```

vmbr0 = Linux bridge. 여러 VM이 하나의 가상 스위치에 연결된 것처럼 동작.

### VLAN-aware Bridge

```
[VM (VLAN 30 tag)] ──→ [vmbr0 VLAN-aware] ──→ [Trunk port] ──→ 외부 스위치
```

VM에 VLAN tag 부여 → bridge가 그대로 외부 트렁크 포트로 전달.

우리 환경: `vmbr0`이 VLAN-aware로 설정됨. VM마다 `vlan_id=30` 또는 `vlan_id=40` 지정.

---

## 7) 우리 환경의 VM 분산 (옵션 C HA)

### 전체 VM 배치

```
kosa1: [pfsense-1] [k8s-cp1] [템플릿 9000]
kosa2: [pfsense-2] [k8s-cp2] [k8s-w3]
kosa3: [k8s-cp3] [k8s-w1] [bastion]
kosa4: [k8s-w2]
```

### 분산 설계 의도

| 시나리오 | 영향 |
|---|---|
| **kosa1 다운** | pfSense 페일오버 → BACKUP 활성, k8s-cp1 잃음 (CP 2/3 유지) |
| **kosa2 다운** | pfSense-2 BACKUP 잃음, cp2 + w3 잃음 (CP 2/3, Worker 2/3) |
| **kosa3 다운** | cp3 + w1 + bastion 잃음 (CP 2/3, Worker 2/3) — Bastion은 재배포 필요 |
| **kosa4 다운** | w2 1대만 잃음 (가장 안전) |

핵심: **최악의 경우에도 K8s Control Plane 2/3, Worker 2/3 유지** → 클러스터 정상 운영.

상세 이유: `../project/02_아키텍처_설계.md` ADR-04 (VM 분산 옵션 C).

---

## 8) 실습 명령

```bash
# 클러스터 상태
ssh kosa1 'pvecm status'

# VM 목록 (특정 노드)
ssh kosa1 'qm list'

# VM 시작/정지
ssh kosa1 'qm start 210'
ssh kosa1 'qm shutdown 210'

# 다른 노드로 마이그레이션 (offline)
ssh kosa1 'qm migrate 210 kosa2 --online 0'

# 클러스터 전체 VM
ssh kosa1 'pvesh get /cluster/resources --type vm'

# VM 설정 확인
ssh kosa1 'qm config 210'
```

---

## 9) 발표 어필

> *"Proxmox 4대 클러스터 위에 K8s 6대 + Bastion 1대를 분산 배치했습니다. 단일 PVE 노드 장애 시에도 K8s CP 2/3, Worker 2/3가 살아있어 클러스터 운영이 지속됩니다. 모든 VM은 Cloud-Init 템플릿(VMID 9000)에서 Terraform으로 1분 안에 7대 동시 생성됩니다."*

---

## 10) 학습 체크리스트

- [ ] Proxmox vs VMware/OpenStack 차이 설명
- [ ] corosync, quorum 개념 이해
- [ ] Cloud-Init이 풀어주는 문제 설명
- [ ] Cloud Image와 Live ISO 차이
- [ ] VLAN-aware bridge 동작
- [ ] 우리 VM 7대 배치도 그리기
- [ ] 노드 장애 시나리오 4개 답변 가능

---

## 다음 단원

[`03_스토리지_Ceph.md`](03_스토리지_Ceph.md)
