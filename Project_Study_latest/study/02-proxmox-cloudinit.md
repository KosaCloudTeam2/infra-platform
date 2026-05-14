# 챕터 02 — Proxmox VE + Cloud-init

> KOSA 인프라 프로젝트 학습용 문서 시리즈<br> 작성일: 2026-05-13<br> 선수 챕터:
> `01-project-overview.md` (큰 그림 이해 필요)<br> 후속 챕터: `03-pfsense-network.md` (네트워크
> 설계)

---

## 이 챕터 학습 후 알 수 있는 것

- **Proxmox VE**가 정확히 무엇이고, VMware/Hyper-V와 어떤 기술적 차이가 있는지
- **KVM/QEMU**가 어떻게 동작하며, Proxmox가 그 위에 무엇을 얹는지
- **Cloud-init**이 왜 "수동 OS 설치"를 대체하게 되었는지
- 우리 환경의 **VMID 9000 템플릿**이 어떻게 만들어지고, 왜 그 옵션들을 줬는지
- **Terraform이 템플릿을 clone**해서 7대 VM을 만들 때 내부에서 무슨 일이 일어나는지
- Proxmox 함정 4가지 (메모리 경쟁, autostart 의존, 디스크 datastore, qemu-guest-agent)

---

## 1. 기술 개요 (자세히)

### 1.1 정의 (한 문장)

#### Proxmox VE

**Proxmox Virtual Environment (PVE)** 는 Debian Linux 위에 **KVM(VM) + LXC(컨테이너) + Ceph/ZFS
스토리지 + 웹 UI/API**를 통합한 오픈소스 가상화 플랫폼이에요.

#### Cloud-init

**Cloud-init**은 클라우드/가상화 환경에서 **VM이 처음 부팅될 때 한 번만 실행되어 hostname, SSH 키,
IP, 사용자 계정, 패키지 등을 자동으로 설정**해주는 표준 도구예요. 쉽게 말하면 "VM의 자동 초기 설정
마법사".

### 1.2 등장 배경 (어떤 문제 해결하려고?)

#### Proxmox의 배경

2008년에 Proxmox Server Solutions GmbH(오스트리아)가 만들었어요. 당시 시장은:

- **VMware ESXi**: 상용, 비싸고 폐쇄적
- **Xen**: 오픈소스지만 운영 UI가 부족
- **순수 KVM/libvirt**: CLI 위주, 클러스터링 직접 구성해야 함

→ "**KVM의 성능 + VMware의 UI 편의성 + 오픈소스**" 조합이 필요했고, Proxmox가 그 자리를 차지했어요.

#### Cloud-init의 배경

전통적으로 VM 만들기란:

1. ISO 부팅 → 2. GUI 설치 마법사 → 3. 키보드/타임존/디스크 파티션 선택 → 4. 패스워드 입력 → 5.
   패키지 선택 → 6. 재부팅 → 7. SSH 설정...

**한 대만 만들면 10분이지만 100대면 16시간**. 게다가 사람이 클릭하면 실수가 섞여요. AWS EC2가
등장하면서 "VM은 API 한 번에 만들고 부팅 시 자동 구성"이 필수가 됐고, 그 표준이 cloud-init이에요.
Canonical(Ubuntu 만드는 회사)이 주도해서 만들었어요.

### 1.3 핵심 개념 + 용어 풀이

| 용어                           | 풀이                                                                                                                                          |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **하이퍼바이저**               | VM을 만들고 관리하는 소프트웨어. Type 1 (베어메탈, ESXi), Type 2 (호스트 OS 위, VirtualBox).                                                  |
| **KVM**                        | Kernel-based Virtual Machine. Linux 커널 자체를 Type 1 하이퍼바이저로 만드는 모듈. 쉽게 말하면 "리눅스 = 하이퍼바이저".                       |
| **QEMU**                       | KVM과 짝지어 동작하는 사용자 공간 에뮬레이터. CPU 가상화는 KVM이, 디바이스(NIC/디스크) 에뮬레이션은 QEMU가.                                   |
| **libvirt**                    | KVM/QEMU를 관리하는 API/CLI. Proxmox는 libvirt를 안 쓰고 자체 API(`qm`, `pvesh`)로 직접 관리.                                                 |
| **VMID**                       | Proxmox 내부 VM 고유 번호. 우리 환경 컨벤션: 100번대=인프라, 200번대=K8s, 9000번대=템플릿.                                                    |
| **Cloud-init datasource**      | cloud-init이 설정값을 읽어오는 출처. NoCloud(ISO), AWS metadata, OpenStack ConfigDrive 등. Proxmox는 NoCloud 방식으로 ISO를 생성해 VM에 붙임. |
| **qemu-guest-agent**           | VM 내부에서 동작하는 에이전트. 호스트 측에서 VM의 IP/상태를 조회하거나 정상 shutdown을 보낼 수 있게 해줌.                                     |
| **VirtIO**                     | 반가상화(paravirtualized) 드라이버. 풀 에뮬레이션(e1000) 대신 게스트가 호스트와 직접 통신 → 훨씬 빠름.                                        |
| **Live Migration**             | VM을 실행 중인 채로 다른 호스트로 옮기는 기능. Proxmox는 메모리 페이지를 단계적으로 복사하며 진행.                                            |
| **Linked Clone vs Full Clone** | Linked = 템플릿 디스크를 공유 (빠르지만 의존), Full = 완전 복사 (안전, 우리 환경 선택).                                                       |
| **Datastore**                  | Proxmox가 디스크를 저장하는 백엔드. `local` (로컬 디렉토리), `local-lvm` (로컬 LVM), `ceph-rbd-team2` (Ceph 분산 스토리지).                   |

### 1.4 동작 원리 (내부 메커니즘)

#### Proxmox 스택

```
┌────────────────────────────────────────────────┐
│  웹 UI (8006) / REST API / qm CLI               │  ← 사용자 접점
├────────────────────────────────────────────────┤
│  Proxmox 관리 데몬 (pvedaemon, pveproxy)        │  ← Perl로 작성
├────────────────────────────────────────────────┤
│  corosync (클러스터 상태 동기화)                  │  ← 멀티노드 일관성
├────────────────────────────────────────────────┤
│  QEMU 프로세스 (VM 1개 = 프로세스 1개)            │  ← VM 실행
├────────────────────────────────────────────────┤
│  KVM 커널 모듈 (CPU 가상화)                       │  ← 하드웨어 가속
├────────────────────────────────────────────────┤
│  Debian 13 (Trixie) + Kernel 6.17               │
├────────────────────────────────────────────────┤
│  하드웨어 (CPU VMX 지원, RAM, NIC, 디스크)         │
└────────────────────────────────────────────────┘
```

핵심 포인트:

- VM 1개는 호스트에서 보면 그냥 **`qemu-kvm` 프로세스 1개**예요. `ps aux | grep kvm` 하면 보입니다.
- CPU 가상화는 KVM 커널 모듈이 하드웨어 가속(Intel VT-x, AMD-V)을 직접 활용. **준-네이티브 속도**.
- 디스크/네트워크는 QEMU가 에뮬레이션. VirtIO 드라이버 쓰면 거의 네이티브.

#### Cloud-init의 동작 (NoCloud 방식)

```
1. Proxmox가 VM 생성 시 cloud-init 설정값을 받음 (IP, SSH 키, hostname)
       ↓
2. Proxmox가 그 값으로 ISO 이미지를 생성 (user-data, meta-data, network-config)
       ↓
3. ISO를 VM의 ide2(또는 그 비슷한 슬롯)에 mount
       ↓
4. VM이 부팅되면 cloud-init이 자동 실행
       ↓
5. cloud-init이 ISO를 찾아 읽음 (NoCloud datasource)
       ↓
6. 읽은 값으로:
   - /etc/hostname 설정
   - /etc/netplan/.../config.yaml 작성 → netplan apply
   - /home/ubuntu/.ssh/authorized_keys에 SSH 키 추가
   - 사용자 계정 생성
       ↓
7. /var/lib/cloud/instance/{instance-id}/sem/.../done 파일 마킹
       ↓
8. 다음 부팅부터는 skip (idempotent)
```

> **왜 NoCloud인가?** AWS는 169.254.169.254 메타데이터 서버를 쓰지만, 온프레미스는 그게 없어서 ISO
> 방식이 가장 단순. Proxmox 외에 OpenStack/VirtualBox도 NoCloud 지원.

### 1.5 주요 기능

#### Proxmox

1. **클러스터링 (corosync 기반)** — 최대 32 노드를 한 화면에서 관리
2. **HA (High Availability)** — 호스트 다운 시 VM 자동 이전 (공유 스토리지 필요)
3. **Live Migration** — VM 실행 중 다른 노드로 무중단 이전
4. **백업/복원 (vzdump)** — 스케줄 백업, 압축, 증분
5. **스토리지 통합** — LVM, ZFS, Ceph, NFS, iSCSI 등
6. **VLAN-aware 브리지** — 단일 브리지로 여러 VLAN 트렁크 처리
7. **API + Terraform Provider** — 자동화 가능
8. **2단계 인증, RBAC** — 운영 보안

#### Cloud-init

1. **hostname / FQDN 설정**
2. **네트워크 설정** (정적 IP, DHCP, 본딩, VLAN)
3. **SSH 공개키 주입** — 비밀번호 없이 SSH 가능
4. **사용자 계정 생성** (sudoers, shell)
5. **패키지 설치 (apt/yum)**
6. **임의 스크립트 실행** (`runcmd`, `bootcmd`)
7. **타임존, locale 설정**
8. **로그**: `/var/log/cloud-init.log`, `/var/log/cloud-init-output.log`

### 1.6 다른 도구와 비교 (기술적 차이)

#### Proxmox vs VMware vSphere vs Hyper-V

| 비교축                 | Proxmox VE                                 | VMware vSphere               | Hyper-V                     |
| ---------------------- | ------------------------------------------ | ---------------------------- | --------------------------- |
| 라이센스               | GPL (구독 선택)                            | 상용 (Broadcom 인수 후 폭등) | Windows Server 라이센스     |
| 하이퍼바이저 타입      | Type 1 (KVM)                               | Type 1 (ESXi)                | Type 1 (Windows Hypervisor) |
| 클러스터링             | 기본 제공 (corosync)                       | vCenter 별도 (유료)          | SCVMM 별도                  |
| 라이브 마이그레이션    | 가능 (vMotion 대응)                        | 가능 (vMotion)               | 가능 (Live Migration)       |
| 컨테이너 지원          | LXC 통합                                   | Tanzu/별도                   | Windows Containers          |
| Ceph 통합              | **네이티브** (Proxmox UI 안에서 Ceph 운영) | 외부 별도                    | 외부 별도                   |
| 학습 자료              | 풍부, 영어/독일어                          | 풍부 (단, 정책 변동 잦음)    | 중                          |
| 라이센스 비용 (4 노드) | 0 (구독 안 사면) ~ 연 ~수백만 원           | 연 수천만 원                 | 연 수백만 원                |
| 적합 규모              | 중소~중견                                  | 대기업                       | Windows 환경 위주           |

#### Cloud-init vs Ignition vs Ansible

| 도구           | 동작 시점                          | 특징                                                                                 |
| -------------- | ---------------------------------- | ------------------------------------------------------------------------------------ |
| **Cloud-init** | 첫 부팅 1회                        | 단순, 광범위 호환 (Ubuntu/CentOS/Debian/Amazon Linux/Fedora)                         |
| **Ignition**   | 첫 부팅 1회 (OS 부팅 전 initramfs) | Fedora CoreOS 전용, 더 엄격 (재실행 불가)                                            |
| **Ansible**    | 언제든 반복                        | 멱등성, 풀 자동화. 단, **cloud-init이 한 번 깔린 후**에 Ansible로 운영 (역할이 다름) |

우리 환경은 **cloud-init으로 1차 부팅 셋업** → **bastion에서 Ansible로 K8s 부트스트랩** 2단계 분리.

---

## 2. 현업/실무 맥락 ★

### 2.1 어떤 상황에서 이게 필요한가

#### Proxmox가 잘 맞는 상황

- **VMware 라이센스 비용이 부담** — 2024년 Broadcom이 VMware 인수 후 가격을 5~10배 인상. 중소기업이
  대량 이탈.
- **Linux 친화 환경** — 운영진이 Linux에 능숙한 곳
- **K8s/컨테이너와 함께** — Proxmox는 LXC 컨테이너도 지원
- **Ceph 통합 운영** — Proxmox UI 안에서 Ceph 클러스터 직접 운영 가능
- **하드웨어 자유도** — 인증 HCL이 까다로운 VMware/Hyper-V와 달리 일반 Linux 호환 하드웨어면 됨

#### Cloud-init이 필수인 상황

- VM **2대 이상** 만들 때 (1대면 수동도 OK)
- IaC (Terraform/Pulumi) 사용 시 — Cloud-init 없이는 IaC 의미 절반 상실
- 자동 스케일링 — Auto Scaling Group은 cloud-init 없이는 동작 불가
- **Immutable Infrastructure** 추구 — "OS는 매번 새로 만든다, 절대 수정 안 한다" 패턴

### 2.2 업계에서 보통 어떻게 쓰나

#### Proxmox 표준 사용 패턴

```
[관리 노트북]
     │ SSH/Web UI
     ▼
[Proxmox 노드 3대 이상]  ← corosync quorum
     │
     ├── VM (KVM)        ← 일반 워크로드
     ├── CT (LXC)        ← 가벼운 서비스
     └── Ceph OSD        ← 분산 스토리지 (선택)
```

**대표 사용 사례**:

- **유럽 중견기업**: 독일/프랑스/폴란드 IT 기업이 VMware 대안으로 대거 이전 중 (2024년 트렌드)
- **호스팅 사업자**: OVH, Hetzner 등이 일부 인프라에 Proxmox 사용
- **대학/연구소**: 자체 실험 인프라
- **한국 SMB**: 점진적으로 늘어나는 추세 (특히 스타트업)

#### Cloud-init 표준 사용 패턴

**현업에서 가장 흔한 흐름**:

```
1. Packer로 골든 이미지(템플릿) 빌드 (월 1회 등)
   - 베이스 OS + 기본 패키지 + 보안 패치 + cloud-init 활성화
2. Terraform이 그 이미지에서 VM clone
3. Cloud-init이 VM별 고유값(IP/hostname/SSH키) 주입
4. Ansible/Chef/Puppet이 그 다음 단계 운영
```

**대표 사용 사례**:

- **AWS EC2**: AMI + UserData → cloud-init이 UserData를 실행
- **Azure VM**: Custom Data → cloud-init
- **GCP Compute Engine**: startup-script → cloud-init
- **OpenStack**: ConfigDrive
- **Proxmox/oVirt/VMware vRA**: NoCloud ISO

### 2.3 왜 효율이 좋은가 (현업 관점)

#### 운영 관점

```
[VM 만드는 시간 비교]

수동 OS 설치 + 수동 설정:  ~30분/대 × 7대 = 3.5시간
Cloud-init 템플릿:        템플릿 1번 만들기 30분
                          + clone 1분/대 × 7대 = 37분
                          → 약 6배 빠름
```

또한 **휴먼 에러가 0에 가까움**. 100대를 clone해도 7대 만들 때와 동일.

#### 비용 관점

- Proxmox: 라이센스 0원 (구독 옵션은 있음, 안 사도 운영 가능)
- VMware: 4 소켓 라이센스 + 지원 = 연간 수천만 원

#### 성능 관점

- KVM은 베어메탈 대비 **3~5% 오버헤드** (Intel VT-x 가속 시)
- VMware ESXi와 거의 동일한 성능 (벤치마크 다수)
- Cloud-init 자체는 부팅 시 1회만 동작 → 런타임 영향 없음

#### 학습 곡선

- Proxmox: Debian + KVM을 알면 거의 직관적. UI는 2~3시간 만에 익숙해짐.
- Cloud-init: YAML 설정이라 진입 장벽 낮음. 다만 datasource 동작 원리 이해는 1~2일 필요.

### 2.4 시장 위치

- **글로벌 가상화 시장**: VMware 70%+, Hyper-V 15%, KVM 계열 10%+, 기타 (2024년 IDC)
- **단, "오픈소스 KVM 기반"** 카테고리에서는 Proxmox가 점유 1위 (Spiceworks 2024 설문)
- **Stack Overflow 2024 Developer Survey**: "사용 중인 가상화" 항목에서 Proxmox가 KVM 다음 2위
- **트렌드**: 2024년 VMware Broadcom 인수 이슈 후 Proxmox 다운로드 3배 증가

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

| 대안               | 장점                                      | 단점                                            | 우리 결정          |
| ------------------ | ----------------------------------------- | ----------------------------------------------- | ------------------ |
| **Proxmox VE**     | 무료, KVM 표준, Ceph 통합, 학습 자료 풍부 | UI는 VMware보다 다소 투박                       | ✅ 선택            |
| VMware ESXi (Free) | 익숙함, 안정                              | 클러스터링 유료, 8대 제한, Broadcom 정책 불확실 | ❌ 라이센스 리스크 |
| OpenStack          | 강력, 완전한 IaaS                         | 4인 팀에 너무 무거움, 학습 곡선 가파름          | ❌ 범위 초과       |
| 순수 KVM + libvirt | 가장 가벼움                               | 클러스터링/HA 직접 구성 = 추가 부담             | ❌ 운영 부담       |

| 대안 (자동화)     | 장점                         | 단점                                 | 우리 결정  |
| ----------------- | ---------------------------- | ------------------------------------ | ---------- |
| **Cloud-init**    | 표준, Terraform 호환, 광범위 | 처음 1회만 동작                      | ✅ 선택    |
| Ignition (CoreOS) | 더 엄격, 신뢰성 ↑            | Fedora CoreOS 전용, Ubuntu와 안 맞음 | ❌ OS 종속 |
| Kickstart (RHEL)  | 풀 자동 설치                 | RHEL 한정, 우리는 Ubuntu             | ❌ OS 종속 |
| 수동 설치         | 직관적                       | 7대 × 30분 = 3.5시간 + 휴먼 에러     | ❌ 비효율  |

### 3.2 현업 표준과의 정합성

우리가 선택한 **"Proxmox VE + Ubuntu Cloud Image + cloud-init + Terraform clone"** 패턴은
**온프레미스 IaC 표준 흐름**입니다.

- AWS와의 유사성: AMI (Amazon Machine Image) ≈ Proxmox 템플릿 / UserData ≈ cloud-init user-data
- Azure와의 유사성: Custom Image ≈ 템플릿 / Custom Data ≈ cloud-init
- 결과적으로 **온프레미스 경험이 클라우드 경험과 호환**돼요. 학습 자산이 양쪽에서 다 살아남.

### 3.3 선택 근거 (트레이드오프)

**받아들인 단점**:

1. **Proxmox UI가 다소 투박** — VMware vCenter에 비해 그래프 표현이 단순. 운영 자체엔 무해.
2. **Proxmox 클러스터 quorum 요구** — 4대 중 3대 살아있어야 정상. 1대 다운까지만 견딤 (5대였으면
   2대까지).
3. **Cloud-init은 첫 부팅만** — 이후 설정 변경은 Ansible 등으로 별도. (Day-2 운영 도구 필요)
4. **템플릿 업데이트 시 기존 VM 영향 없음 (장점이자 단점)** — Linked Clone 안 쓰면 OS 패치 시 VM마다
   재배포 필요.

**그래도 선택한 이유**:

- 4인 학습 프로젝트에 적정 복잡도
- 비용 0원
- 현업 이전 가능성

---

## 4. 우리 환경 구성

### 4.1 토폴로지

#### Proxmox 4대 클러스터

```
┌─────────────────────────────────────────────────────────────────┐
│                  Proxmox Cluster (corosync)                      │
├──────────────┬──────────────┬──────────────┬──────────────────┤
│   kosa1      │   kosa2      │   kosa3      │   kosa4          │
│ 192.168.21.2 │ 192.168.21.3 │ 192.168.21.4 │ 192.168.21.5     │
│              │              │              │                  │
│  i7-13700    │  i7-13700    │  i7-13700    │  i7-13700        │
│  32GB RAM    │  32GB RAM    │  32GB RAM    │  32GB RAM        │
│  476GB NVMe  │  476GB NVMe  │  476GB NVMe  │  476GB NVMe      │
│  931GB HDD   │  931GB HDD   │  931GB HDD   │  931GB HDD       │
│              │              │              │                  │
│  VM:         │  VM:         │  VM:         │  VM:             │
│  - pfSense-1 │  - pfSense-2 │  - cp3 (212) │  - cp1 (210) ★   │
│  - tpl 9000  │  - cp2 (211) │  - w1  (220) │  - w2  (221)     │
│              │  - w3  (222) │  - bastion   │                  │
└──────────────┴──────────────┴──────────────┴──────────────────┘
       │              │              │              │
       └──────────────┴──────────────┴──────────────┘
                       1GbE 관리망 (eno1)
       ┌──────────────┬──────────────┬──────────────┐
       │              │              │              │
   10GbE SFP+    10GbE SFP+    10GbE SFP+    10GbE SFP+
   (enp1s0f0)    (enp1s0f0)    (enp1s0f0)    (enp1s0f0)
       │              │              │              │
       └──────────────┴──────────────┴──────────────┘
                  Ceph 10G Spine-Leaf (vmbr1)
                       10.10.10.35~38
```

(★ cp1은 2026-05-13에 kosa1 → kosa4로 마이그레이션됨)

#### Cloud-init 템플릿 (VMID 9000)

```
[kosa1]
  └─ VMID 9000 "ubuntu-2404-template"
        ├─ Disk: ceph-rbd-team2 (base-9000-disk-0)   ← Ceph 공유 → 다른 노드도 clone 가능
        ├─ Memory: 2048 MB
        ├─ CPU: host (2 cores)
        ├─ Agent: enabled=1 (qemu-guest-agent 사전 주입)
        ├─ Network: virtio @ vmbr0
        └─ template: 1                                 ← 템플릿 마킹
```

### 4.2 핵심 설정값과 근거 (왜 이 값?)

| 설정                       | 값                              | 근거                                                                                                                     |
| -------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| `clone.full`               | `true`                          | Linked Clone은 빠르지만 템플릿 변경 시 영향. Full Clone이 안전 + 독립 디스크.                                            |
| `cpu.type`                 | `"host"`                        | 호스트 CPU 그대로 노출 → **nested virtualization 가능** (Proxmox 위 K8s 위 컨테이너). AVX 등 instruction 모두 사용 가능. |
| `memory.dedicated`         | CP 4096 / W 6144 / Bastion 2048 | Proxmox 32GB × 4 = 128GB. Ceph는 별도라 OK. 6 GiB 워커면 Percona Pod (2 GiB) + 시스템 여유.                              |
| `agent.enabled`            | `true`                          | Proxmox에서 VM IP 조회 + 정상 shutdown. qemu-guest-agent를 cloud image에 사전 주입.                                      |
| `disk.datastore_id`        | `"ceph-rbd-team2"`              | Ceph RBD에 두면 노드 페일오버 시에도 데이터 보존. Live migration 가능.                                                   |
| `disk.file_format`         | `"raw"`                         | Ceph RBD는 raw 사용 (qcow2는 LVM/dir 전용). RBD 자체가 스냅샷 지원.                                                      |
| `disk.discard`             | `"on"`                          | Ceph thin provisioning 지원. 게스트가 파일 삭제 시 Ceph가 공간 회수.                                                     |
| `disk.ssd`                 | `true`                          | 게스트 OS에 SSD로 노출 → 일부 OS가 TRIM/스케줄러 최적화.                                                                 |
| `network_device.firewall`  | `false`                         | Proxmox 자체 방화벽 비활성화 (pfSense + K8s NetworkPolicy로 충분). fwbr/fwln 추가 브리지 안 생김.                        |
| `network_device.model`     | `"virtio"`                      | 가장 빠름. e1000은 호환성, vmxnet3은 VMware. KVM에선 virtio가 표준.                                                      |
| `network_device.vlan_id`   | 30 (K8s) / 40 (Bastion)         | Proxmox가 VLAN 태그 부여 → Access 포트처럼 동작.                                                                         |
| `ceph_bridge.mtu`          | 9000                            | Jumbo frame. Ceph IO 처리 성능 ↑ (작은 패킷 대비 패킷 수 ÷6).                                                            |
| `lifecycle.ignore_changes` | `[clone]`                       | 템플릿 이미지가 업데이트되어도 기존 VM 재생성 안 함 (운영 안정성).                                                       |

### 4.3 다른 컴포넌트와의 연결

```
[Terraform (노트북)]
        │ Proxmox API 토큰
        ▼
[Proxmox] ── (template 9000 clone) ──→ [VM 7대]
                                            │
                                       [Cloud-init ISO]
                                            │
                                       (첫 부팅 1회)
                                            │
                                            ▼
                                       [Ubuntu 24.04 + IP/SSH 키 설정 완료]
                                            │
                                            ▼
                                  [Bastion → Ansible로 K8s 부트스트랩]
                                            │
                                            ▼
                                  [K8s 6노드 Ready]
                                            │
                                            ▼
                                  [Ceph CSI → RBD pool에 PV 생성]
                                            │
                                            ▼
                                  [Percona Operator → MySQL 클러스터]
```

---

## 5. 실제 코드 / 설정 파일

### 5.1 Cloud-init 템플릿 생성 (kosa1에서 1회 수행)

`Onprem_Build_Guide.md` Phase 2.3 발췌:

```bash
# Ubuntu Cloud Image 다운로드 (600 MB, 이미 설치된 이미지)
[kosa1]# cd /var/lib/vz/template/iso
[kosa1]# wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

**왜 Cloud Image?** 일반 Live ISO는 부팅 후 설치 마법사가 떠서 자동화 불가. Cloud Image는 이미
설치되어 cloud-init만 활성화되어 있어 부팅 즉시 사용 가능.

```bash
# qemu-guest-agent 사전 주입
[kosa1]# apt-get install -y libguestfs-tools
[kosa1]# virt-customize -a noble-server-cloudimg-amd64.img \
           --install qemu-guest-agent \
           --run-command 'systemctl enable qemu-guest-agent'
```

**왜 사전 주입?** cloud-init이 부팅 후 apt로 깔 수도 있지만 인터넷 의존. 미리 이미지에 박아두면
오프라인 환경에서도 동작.

```bash
# 템플릿 VM 생성
[kosa1]# qm create 9000 \
  --name ubuntu-2404-template \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --net0 virtio,bridge=vmbr0,firewall=0 \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0 \
  --scsihw virtio-scsi-pci
```

**줄별 의미**:

- `--cpu host`: 호스트 CPU 그대로 = 가장 빠름 + nested virt
- `--firewall=0`: Proxmox 자체 방화벽 안 씀 = fwbr 같은 추가 브리지 안 생김
- `--agent enabled=1`: qemu-guest-agent 활성화
- `--serial0 socket`: 시리얼 콘솔 (cloud-init 출력 디버깅용)
- `--scsihw virtio-scsi-pci`: SCSI 컨트롤러 virtio-scsi → 디스크 IO 성능 ↑

```bash
# 디스크를 Ceph RBD에 import (다른 노드도 clone 가능하려면 공유 스토리지 필수)
[kosa1]# qm importdisk 9000 noble-server-cloudimg-amd64.img ceph-rbd-team2
[kosa1]# qm set 9000 --scsi0 ceph-rbd-team2:vm-9000-disk-0,discard=on,ssd=1

# cloud-init 드라이브 (작은 ISO, local-lvm으로 충분)
[kosa1]# qm set 9000 --ide2 local-lvm:cloudinit

# 부팅 디스크 지정 + 템플릿화
[kosa1]# qm set 9000 --boot c --bootdisk scsi0
[kosa1]# qm template 9000
```

**왜 cloud-init은 local-lvm?** ISO 1MB 정도로 작고, 매 부팅마다 읽기만 함. Ceph에 두면 매번 Ceph
액세스 → 약간 느림. local-lvm은 노드 로컬이라 가장 빠름.

### 5.2 Terraform VM 모듈

파일: `/Users/sangjjang/kosa_infra_project/terraform/modules/vm/main.tf`

핵심 발췌 (`main.tf:25-29`):

```hcl
clone {
  vm_id     = var.template_vm_id      # 9000
  node_name = var.template_vm_node    # "kosa1"
  full      = true                     # ★ Full Clone (Linked X)
}
```

**줄별 설명**:

- `vm_id = 9000`: 어떤 템플릿을 clone할지
- `node_name = "kosa1"`: 템플릿이 위치한 노드
- `full = true`: **Linked Clone이 아니라 Full Clone**. 빠른 속도보다 안전성 우선. 템플릿 업데이트 시
  기존 VM 영향 없음.

`main.tf:37-44` — CPU/메모리:

```hcl
cpu {
  cores = var.cores
  type  = "host"        # ★ 호스트 CPU 그대로 → nested virt 가능
}

memory {
  dedicated = var.memory # MB 단위
}
```

`main.tf:64-71` — 디스크:

```hcl
disk {
  datastore_id = var.datastore_id  # "ceph-rbd-team2"
  interface    = "scsi0"
  size         = var.disk_size
  file_format  = "raw"             # ★ Ceph RBD는 raw 필수 (qcow2 X)
  discard      = "on"              # ★ Ceph thin provisioning 활용
  ssd          = true              # ★ 게스트가 SSD 인식 → TRIM
}
```

`main.tf:80-85` — Primary NIC:

```hcl
network_device {
  bridge   = var.bridge          # "vmbr0"
  vlan_id  = var.vlan_tag        # 30 (K8s) or 40 (Bastion)
  model    = "virtio"            # ★ 성능 최고
  firewall = false               # ★ Proxmox 자체 fw 끔 (pfSense/NetworkPolicy로 대체)
}
```

`main.tf:94-102` — Secondary NIC (Ceph 10G, dynamic):

```hcl
dynamic "network_device" {
  for_each = var.ceph_bridge != "" ? [1] : []   # ★ Bastion은 1개 NIC만
  content {
    bridge   = var.ceph_bridge   # "vmbr1"
    model    = "virtio"
    firewall = false
    mtu      = var.ceph_mtu      # ★ 9000 (jumbo frame)
  }
}
```

**왜 dynamic block?** Bastion은 VLAN 40 1개 NIC만, K8s 노드들은 VLAN 30 + Ceph 10G 2개 NIC. 변수로
분기.

`main.tf:111-147` — Cloud-init 설정:

```hcl
initialization {
  datastore_id = var.cloudinit_datastore_id    # "local-lvm"

  ip_config {                                   # 1st = primary NIC
    ipv4 {
      address = var.ip_address                  # "172.16.23.10/24"
      gateway = var.gateway                     # "172.16.23.1" (pfSense CARP VIP)
    }
  }

  dynamic "ip_config" {                         # 2nd = Ceph NIC
    for_each = var.ceph_ip != "" ? [1] : []
    content {
      ipv4 {
        address = var.ceph_ip                   # "10.10.10.110/24" (gateway 없음!)
      }
    }
  }

  dns {
    servers = var.dns_servers                   # ["1.1.1.1", "8.8.8.8"]
  }

  user_account {
    username = "ubuntu"
    keys     = [var.ssh_public_key]             # ★ password 없음, SSH 키만
  }
}
```

**왜 Ceph NIC에 gateway 없음?** 같은 L2(10.10.10.0/24) 안에서 Ceph 모니터/OSD와 직접 통신. 라우팅
불필요.

### 5.3 변수 정의 (CP/Worker/Bastion)

파일: `/Users/sangjjang/kosa_infra_project/terraform/onprem/variables.tf`

`variables.tf:162-181` — Control Plane:

```hcl
variable "control_plane_nodes" {
  default = [
    # PVE 노드 분산: kosa1=pfSense-1, kosa2=pfSense-2 만 남도록 cp1을 kosa4로 이동
    # ceph_ip_suffix = ip_suffix + 100 (디버깅 시 매핑 직관적)
    { name = "k8s-cp1", vmid = 210, pve_node = "kosa4", ip_suffix = 10, ceph_ip_suffix = 110, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp2", vmid = 211, pve_node = "kosa2", ip_suffix = 11, ceph_ip_suffix = 111, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp3", vmid = 212, pve_node = "kosa3", ip_suffix = 12, ceph_ip_suffix = 112, cores = 2, memory = 4096, disk_size = 40 },
  ]
}
```

**핵심 결정**: cp1을 kosa1에 두면 pfSense-1과 메모리 경쟁 (32 GB에 4 GB CP + 4 GB pfSense + 시스템).
OOM/leader change 빈번 → kosa4로 이동.

---

## 6. 실행 + 결과

### 6.1 템플릿 검증

```bash
[kosa1]# qm config 9000 | grep -E "template|scsi0|cpu|agent"
```

기대 출력:

```
agent: enabled=1
cpu: host
scsi0: ceph-rbd-team2:base-9000-disk-0,discard=on,size=2252M,ssd=1
template: 1
```

`template: 1` 보이고 `scsi0`가 `ceph-rbd-team2`로 시작이면 OK.

### 6.2 Terraform으로 7대 생성

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project/terraform/onprem
[노트북]$ terraform init
```

기대 출력 끝:

```
- Installing bpg/proxmox v0.66.x...
Terraform has been successfully initialized!
```

```bash
[노트북]$ terraform plan
```

기대 출력 끝:

```
Plan: 7 to add, 0 to change, 0 to destroy.
```

```bash
[노트북]$ terraform apply -parallelism=2 -auto-approve
```

> `-parallelism=2` 권장: 동시 7대 clone은 Proxmox에 부담. 2대씩이면 안정적. 약 8~12분 소요.

### 6.3 VM 분산 확인

```bash
[노트북]$ terraform output all_vm_summary
```

기대 출력:

```
tolist([
  "k8s-cp1 (172.16.23.10) on kosa4",
  "k8s-cp2 (172.16.23.11) on kosa2",
  "k8s-cp3 (172.16.23.12) on kosa3",
  "k8s-w1  (172.16.23.20) on kosa3",
  "k8s-w2  (172.16.23.21) on kosa4",
  "k8s-w3  (172.16.23.22) on kosa2",
  "bastion (172.16.24.10) on kosa3",
])
```

### 6.4 Cloud-init 동작 확인

```bash
[노트북]$ for h in k8s-cp1 k8s-cp2 k8s-cp3 k8s-w1 k8s-w2 k8s-w3 bastion; do
  echo -n "$h: "
  ssh -o ConnectTimeout=5 $h 'echo OK hostname=$(hostname) ci=$(cloud-init status | tail -1)' 2>/dev/null || echo FAIL
done
```

기대:

```
k8s-cp1: OK hostname=k8s-cp1 ci=status: done
k8s-cp2: OK hostname=k8s-cp2 ci=status: done
...
bastion: OK hostname=bastion ci=status: done
```

만약 `ci=status: running` 나오면 1~2분 더 대기 후 재시도.

### 6.5 cloud-init 내부 로그 확인 (디버깅)

```bash
[k8s-cp1]$ sudo cat /var/log/cloud-init-output.log | tail -30
```

기대 — 마지막 줄:

```
Cloud-init v. 24.4-0ubuntu1~24.04.1 finished at ... Up 47.21 seconds
```

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 함정 1: cp1 자주 OOM, etcd leader change

**증상**: 클러스터 부팅 후 etcd leader가 5~10분 간격으로 바뀌고, cp1 Pod들이 OOMKilled 됨.

**원인**: cp1을 kosa1에 뒀는데, kosa1엔 **pfSense-1 VM(4 GB) + cp1(4 GB) + Proxmox 시스템(~2 GB)**
이 동시에 올라가 있어 32 GB 중 75% 이상 사용. Linux OOM killer가 etcd 프로세스를 죽이는 현상 발생.

**해결**:

```bash
[kosa1]# qm migrate 210 kosa4 --online
```

cp1을 kosa4로 라이브 마이그레이션. kosa4엔 cp1(4) + w2(6) = 10 GB만 사용 → 여유 ~22 GB.

**★ 왜 이 함정이 발생하는가**:

- Linux OOM killer는 가장 많은 메모리를 쓰는 프로세스부터 죽임
- etcd는 항상 데이터 캐시를 메모리에 들고 있어 큰 메모리 사용량 표시
- 결과적으로 etcd가 가장 먼저 죽음 → quorum 깨짐 → leader change 폭증
- **교훈: HA 컴포넌트(pfSense, etcd, Ceph) 끼리는 같은 물리 노드에 모으면 안 됨**

### 함정 2: VM 부팅 시 cloud-init이 IP 못 잡음

**증상**: VM은 부팅됐는데 ssh 안 됨. 콘솔로 들어가보면 IP 0.0.0.0.

**원인 케이스 1**: `serial0` 미설정 → cloud-init 출력 어디로 가는지 불명. **원인 케이스 2**: VLAN
태그가 Proxmox에서만 부여되고 스위치에서 안 받음. **원인 케이스 3**: Cloud-init 드라이브가 잘못된
datastore에 있어 read 실패.

**해결**:

```bash
# 콘솔로 들어가 cloud-init 로그 확인
[kosa-X]# qm terminal 210
# 안에서:
ubuntu@k8s-cp1:~$ sudo cat /var/log/cloud-init.log | grep -i error
ubuntu@k8s-cp1:~$ ip addr
```

`netplan` 설정이 안 들어와 있다면 cloud-init이 metadata를 못 읽은 것. 99% **VLAN 태그 mismatch**
또는 **스위치 trunk 설정 누락**.

**★ 왜 이 함정이 발생하는가**:

- Proxmox에서 VLAN 태그를 주면 Proxmox 측에서 802.1Q 태그 부여
- 스위치는 그 트렁크 포트에서 해당 VLAN ID를 허용해야 함
- 한쪽만 설정되면 패킷 drop → cloud-init이 DHCP/메타데이터 못 받음
- 정적 IP라도 인터페이스가 안 올라오면 의미 없음

### 함정 3: 템플릿 clone 시 디스크 datastore 미스매치

**증상**: `terraform apply` 시 `Error: storage 'ceph-rbd-team2' does not exist on node 'kosa3'`.

**원인**: 템플릿 9000의 디스크가 **노드 로컬 LVM**에 있어서 다른 노드가 clone할 수 없음. Ceph(공유
스토리지)에 있어야 4 노드 어디든 clone 가능.

**해결**: 템플릿 생성 시 `qm importdisk 9000 ... ceph-rbd-team2`로 처음부터 Ceph에 두기. 이미 잘못
만들었으면:

```bash
[kosa1]# qm move-disk 9000 scsi0 ceph-rbd-team2 --delete=1
```

**★ 왜 이 함정이 발생하는가**:

- Proxmox clone은 디스크를 복사하는데, 소스가 노드 로컬이면 그 노드에서만 가능
- 공유 스토리지(Ceph/NFS/iSCSI)에 두면 모든 노드가 접근 가능
- "어떤 노드에 띄울지 자유로워야 한다"가 클러스터 가상화의 핵심

### 함정 4: qemu-guest-agent 미동작 → IP 조회 불가

**증상**: Proxmox UI에서 VM 상세 화면에 IP가 안 보임. Terraform이 cloud-init 진행 상태를 못 추적.

**원인**: cloud image에 qemu-guest-agent 패키지가 설치 안 됨, 또는 서비스 비활성.

**해결**: 템플릿 빌드 시 `virt-customize`로 사전 주입 (Phase 2.2 명령).

**★ 왜 이 함정이 발생하는가**:

- Proxmox는 호스트와 VM이 별도 프로세스라 VM 내부 정보(IP/CPU/메모리)를 직접 못 봄
- qemu-guest-agent가 VM 내부에서 동작하며 virtio-serial 채널로 호스트와 통신
- 이게 없으면 Proxmox는 VM의 상태를 외부에서만 추측 가능

---

## 8. 더 깊이 공부할 자료

### 공식 문서

- **Proxmox VE Admin Guide**: https://pve.proxmox.com/pve-docs/pve-admin-guide.html
- **Cloud-init Documentation**: https://cloudinit.readthedocs.io/
- **QEMU/KVM**: https://www.linux-kvm.org/

### 추천 학습 자료

- **Lawrence Systems YouTube** — Proxmox 튜토리얼 (영어)
- **Proxmox Forum** — 실전 트러블슈팅 사례 풍부
- **Ubuntu Cloud Image 문서** — https://cloud-images.ubuntu.com/

### 우리 프로젝트 내부 문서

- `terraform/modules/vm/main.tf` — VM 생성 모듈
- `terraform/onprem/variables.tf` — 노드 정의
- `Onprem_Build_Guide.md` Phase 2~3 — 실제 구축 순서

### 다음 챕터 미리보기

다음 챕터(`03-pfsense-network.md`)에서는 **이 VM들이 통신하는 네트워크 계층**을 다룹니다. VLAN
10/20/30/40 설계, pfSense HA(CARP), 그리고 K8s 노드의 dual-NIC (VLAN 30 + Ceph 10G) 구성을 봐요.
Cloud-init이 정적 IP를 주입할 때 **gateway가 pfSense CARP VIP**라는 게 어떻게 동작하는지도 거기서
풀립니다.

---

> **이 챕터 핵심 메시지**: Proxmox VE는 KVM 기반 오픈소스 가상화의 사실상 표준이고, Cloud-init은 VM
> 자동 초기 설정의 표준이에요. 우리는 **템플릿 1개(9000) + Terraform 7번 clone + cloud-init이
> IP/SSH/hostname 자동 주입** 패턴으로 7대 VM을 1분 안에 prod-ready 상태로 만들어냅니다.
