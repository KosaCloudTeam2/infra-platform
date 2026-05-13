# 챕터 14: Terraform + Ansible (IaC)

> KOSA 인프라 프로젝트 학습 시리즈 / 작성일 2026-05-13
> 환경: Terraform 1.5+ (bpg/proxmox provider), Ansible 2.16+, Bastion에서 실행

## 학습 후 알 수 있는 것

- IaC(Infrastructure as Code)의 정의와 등장 배경을 한 문장으로 설명할 수 있어요.
- Terraform이 "선언적"이고 Ansible이 "절차적"이라는 게 무슨 뜻인지, 왜 둘을 같이 쓰는지 말할 수 있어요.
- 우리가 만든 Terraform 모듈 구조(`modules/vm` 재사용 + `onprem/main.tf` for_each)가 왜 깔끔한지 알 수 있어요.
- Ansible playbook 5단계(00 → 10 → 20 → 30 → 40)가 어떤 순서로 K8s를 부트스트랩하는지 설명할 수 있어요.
- 우리가 만난 함정 — Terraform state vs 실제 환경 불일치(cp1 수동 마이그레이션), Ansible task에 retries 추가(etcd leader change), `helm install` 이름 중복 — 의 메커니즘을 이해해요.

---

## 1. 기술 개요

### 1.1 정의 (한 문장)

- **Terraform**: 인프라(VM, 네트워크, 스토리지, AWS 리소스 등)를 HCL이라는 선언적 DSL로 기술하고, "원하는 상태"와 "현재 상태"의 diff를 자동으로 좁히는 IaC 도구예요.
- **Ansible**: SSH 기반 agentless 구성 관리 도구로, YAML 플레이북에 "이 호스트들에 이 작업들을 순서대로 수행하라"를 기술해서 실행해요.

### 1.2 등장 배경

- 2000년대 — 운영자가 새 서버 받으면 매뉴얼 따라 손으로 설치 → "snowflake server"(눈송이처럼 똑같은 서버가 없음).
- 2009년 Chef, 2011년 Puppet 등장 — 구성 관리 자동화. 단 agent 설치 필요.
- 2012년 Ansible — Python + SSH, agent 불필요. 학습 곡선 ↓ 폭발적 보급.
- 2014년 Terraform (HashiCorp) — "VM 자체를 만드는" IaC. AWS 등장 + 클라우드 시대와 맞물려 표준화.
- 2023년 HashiCorp 라이센스 변경(BSL) → 커뮤니티가 OpenTofu fork. 현재 양립 중.

### 1.3 핵심 개념 + 용어 풀이

**Terraform 핵심 용어:**

| 용어 | 의미 |
|---|---|
| Provider | "Proxmox를 어떻게 다루는지 아는 플러그인". bpg/proxmox, aws, kubernetes 등 |
| Resource | `proxmox_virtual_environment_vm`, `aws_instance` 같은 관리 대상 단위 |
| Module | 여러 resource를 묶은 재사용 단위. 함수처럼 input/output |
| State | 현재 인프라 상태의 스냅샷. `terraform.tfstate` 파일 (또는 원격 저장소) |
| Plan | 현재 상태와 원하는 상태의 diff. apply 전에 미리 보여줌 |
| Apply | plan을 실제 적용. provider가 API 호출 |

**Ansible 핵심 용어:**

| 용어 | 의미 |
|---|---|
| Inventory | "어떤 호스트들에 적용할지" 목록 (YAML/INI). 그룹 가능 |
| Playbook | 작업 모음 YAML. 위에서 아래로 순차 실행 |
| Task | 단일 작업(패키지 설치, 파일 복사 등). 모듈을 호출 |
| Module | Ansible이 호스트에서 실행하는 단위 명령(`apt`, `copy`, `shell`, `kubernetes.core.k8s` 등) |
| Role | 재사용 가능한 task 묶음 + 기본값 + 핸들러 |
| Handler | 변경 발생 시 트리거되는 task (예: 설정 바뀌면 데몬 재시작) |

### 1.4 동작 원리 (내부 메커니즘)

**Terraform 실행 흐름:**

```
1) terraform init
   - .tf 파일 읽고 필요한 provider 다운로드 (~/.terraform.d/plugins/)
2) terraform plan
   - 현재 state(terraform.tfstate) 로드
   - .tf의 "원하는 상태"와 비교 → 추가/변경/삭제할 리소스 출력
3) terraform apply
   - plan 결과대로 provider API 호출 (Proxmox REST API 등)
   - 성공한 만큼 state 파일 갱신
4) 다음 plan에선 갱신된 state 기준
```

**Ansible 실행 흐름:**

```
1) ansible-playbook playbook.yml
   - inventory 파싱 → 대상 호스트 결정
   - 각 호스트에 SSH 연결 → 임시 디렉토리 생성
   - Python 모듈을 호스트에 복사
   - 모듈 실행 → JSON 결과 받음
   - 다음 task로
2) 한 task 실패하면 그 호스트만 빠지고 나머지는 계속 (기본)
3) idempotency는 "각 모듈이 책임" — apt 모듈은 이미 설치된 패키지면 skip
```

**핵심 차이:**

| 항목 | Terraform | Ansible |
|---|---|---|
| 모델 | 선언적 (원하는 상태 명시) | 절차적 (해야 할 작업 나열) |
| 실행 방식 | API 호출 (Proxmox/AWS API) | SSH 후 원격 명령 |
| 상태 추적 | state 파일 명시적 보관 | 매번 호스트 상태 조회 |
| 멱등성 | 핵심 원칙 (재실행 안전) | 모듈마다 보장 정도 다름 |
| 강점 | 인프라 생성 (VM, VPC, RDS) | OS 설정, 패키지 설치, 클러스터 부트스트랩 |

### 1.5 주요 기능

**Terraform:**
- HCL 표현식 (`for_each`, `dynamic`, `count`, locals, functions)
- 모듈 시스템 + Registry (`registry.terraform.io`)
- Remote state (S3, Terraform Cloud, Consul)
- Workspace (같은 코드로 dev/stg/prod state 분리)
- import (기존 인프라를 state로 끌어들이기)

**Ansible:**
- 700+ 모듈 (apt, yum, file, copy, template, lineinfile, kubernetes.core.k8s 등)
- Galaxy (커뮤니티 role/collection)
- Vault (변수 암호화)
- Jinja2 템플릿 (`{{ }}`)
- Tags, when, loop, block/rescue, async/poll
- Callback plugin (출력 포맷, 알림)

### 1.6 다른 도구와 비교

**IaC 도구:**

| 도구 | 특징 | 점유율 |
|---|---|---|
| **Terraform** | Multi-cloud, HCL, 가장 범용 | IaC 1위 |
| OpenTofu | Terraform fork (BSL 회피) | 빠른 성장 중 |
| CloudFormation | AWS 전용, JSON/YAML | AWS 진영 표준 |
| Pulumi | TS/Python/Go 코드 기반 | 코드 친화 |
| Crossplane | K8s CR로 인프라 관리 | GitOps 친화 |
| Ansible (또는 SaltStack) | 인프라 생성도 가능하나 비표준 | 대안 |

**구성 관리 도구:**

| 도구 | 모델 | 특징 |
|---|---|---|
| **Ansible** | Push, SSH | agentless, YAML 쉬움 |
| Chef | Pull, agent | Ruby DSL |
| Puppet | Pull, agent | Ruby DSL, 가장 오래됨 |
| SaltStack | Push/Pull, agent | Python, 대규모 강점 |

---

## 2. 현업/실무 맥락

### 2.1 어떤 상황에서 필요한가

- **Terraform**: AWS/Azure/GCP 위에 VPC + EC2 + RDS + Route53 한 번에 세팅. 또는 Proxmox/VMware 위에 VM 여러 대.
- **Ansible**: 받은 서버(또는 Terraform이 만든 VM)에 K8s 설치, nginx 설정, 데이터베이스 초기화 등.

### 2.2 업계 표준, 대표 사용 기업/사례

- **Terraform**: Netflix, GitHub, Uber, Slack — 거의 모든 빅테크. AWS 환경에선 CloudFormation보다 Terraform 점유율 더 높다는 조사도 있음(HashiCorp State of Cloud 2024).
- **Ansible**: Red Hat 인수 후 Red Hat Ansible Automation Platform으로 엔터프라이즈 제품. Walmart, NASA, JPMorgan 사례.
- **함께 쓰는 패턴**: Terraform으로 VM 생성 → Ansible로 OS/앱 설정. 이 조합은 "Two-step IaC"로 불리는 산업 표준.

### 2.3 왜 효율이 좋은가 (현업 관점)

**Terraform:**
- 인프라 변경의 Git 추적 — PR 리뷰로 인프라 변경 승인
- 환경 복제 — staging과 prod 코드 거의 동일
- 비용 사전 검증 — `terraform plan`이 변경 보여줌, Infracost로 가격 미리 계산
- 클러스터 재구축 — 사고 발생 시 `terraform apply`로 30분 내 복구

**Ansible:**
- 신규 입사자 환경 5분 셋업 — 같은 playbook으로 노트북 환경까지
- 보안 패치 일괄 적용 — `ansible all -m apt -a "upgrade=yes"` 한 줄
- 롤링 업데이트 — `serial: 1`로 노드 하나씩 처리

### 2.4 시장 위치

- Terraform/OpenTofu — IaC 사실상 표준. CloudFormation은 AWS 락인이라 멀티 클라우드 회사는 거의 Terraform.
- Ansible — 구성 관리 1위. Red Hat 엔터프라이즈 제품군과 통합돼서 안정성 ↑.

---

## 3. 우리가 왜 이걸 썼나 (Why)

### 3.1 대안 비교 표

**VM 생성:**

| 옵션 | 장점 | 단점 | 우리 판단 |
|---|---|---|---|
| Proxmox UI 클릭 | 직관적 | 7대 손작업, 재현성 0 | 탈락 |
| `qm clone` 셸 스크립트 | 빠름 | state 추적 X, 실수 시 롤백 X | 탈락 |
| Ansible의 community.general.proxmox 모듈 | 한 도구로 끝 | 모듈 기능 제한적, plan/state 개념 부재 | 1차 검토 후 탈락 |
| **Terraform + bpg/proxmox** | 표준, state 관리, plan 미리보기 | 학습 곡선 | **채택** |

**구성 관리:**

| 옵션 | 장점 | 단점 | 우리 판단 |
|---|---|---|---|
| 수동 SSH + 명령 | 단순 | 재현성 0 | 탈락 |
| Bash 스크립트 | 가벼움 | 멱등성/오류 처리 부족 | 부분 사용(setup-bastion.sh) |
| Chef/Puppet | 강력 | agent 설치, Ruby 학습 | 과함 |
| **Ansible** | agentless, YAML, kubernetes.core 컬렉션 | 디버깅 다소 어려움 | **채택** |

### 3.2 현업 표준과의 정합성

- Terraform + Ansible은 가장 표준적인 IaC 콤보. 면접/포트폴리오에서 "왜 둘 다 쓰셨나요?" 질문이 정해진 답("선언적 vs 절차적", "인프라 vs 구성").
- 우리는 AWS 측에도 Terraform을 그대로 활용 가능 → 멀티 클라우드 일관성.

### 3.3 선택 근거 (트레이드오프)

- **트레이드오프 1 — provider 선택**: Proxmox API용 Terraform provider는 telmate/proxmox(원조)와 bpg/proxmox(신생, 더 활발)가 양립. 우리는 bpg를 채택 — VLAN tag, cloud-init multi-NIC 등 신기능 지원 더 빠름.
- **트레이드오프 2 — Terraform이 K8s를 다 만들 수도 있다**: Terraform의 kubernetes provider로 Deployment까지 만들 수 있어요. 그래도 안 한 이유 — K8s 클러스터 부트스트랩(kubeadm init, etcd quorum 대기) 같은 절차적 작업은 Ansible이 자연스러움. 클러스터 만들고 나면 K8s 리소스는 ArgoCD에 맡김.
- **트레이드오프 3 — 상태 파일 보관**: 우리 state는 노트북 로컬. 운영은 보통 S3/Terraform Cloud 권장. 우리는 4인 팀이라 한 명만 apply하기로 약속, locking은 git 협업 규칙으로 대체.

---

## 4. 우리 환경 구성

### 4.1 토폴로지

```
[노트북]                                  [bastion]                       [K8s VM 6대]
   │                                          │                                  │
   │ ① terraform apply (VM 7대 생성)            │                                  │
   │    Proxmox API 호출 (kosa1~4)             │                                  │
   │                                          │                                  │
   │ ② generate-inventory.sh                   │                                  │
   │    state → ansible/inventory/hosts.yml    │                                  │
   │                                          │                                  │
   │ ③ rsync ansible/ → bastion ──────────────→│                                  │
   │                                          │                                  │
   │                                          │ ④ ansible-playbook 00→40         │
   │                                          │    SSH로 6 VM에 패키지/설정       │
   │                                          │    ────────────────────────────→ │
   │                                          │                                  │
   │                                          │ ⑤ kubectl get nodes (6 Ready)   │
```

### 4.2 핵심 설정값과 근거

**Terraform 측:**

| 항목 | 값 | 근거 |
|---|---|---|
| Provider | bpg/proxmox | 최신 기능, 활발한 maintain |
| Template VMID | 9000 (kosa1, ceph-rbd-team2 디스크) | 한 번만 만들면 모든 노드에서 clone 가능 |
| VM disk | ceph-rbd-team2 (Ceph RBD) | HA — 노드 다운 시 디스크 보존 |
| cloud-init disk | local-lvm | 작은 ISO, 로컬이 빠름 |
| Disk file_format | raw | Ceph RBD는 qcow2 불가, raw만 |
| Network bridge | vmbr0 (primary), vmbr1 (Ceph 10G) | 트래픽 분리 |
| Primary NIC firewall | false | pfSense + K8s NetworkPolicy로 충분, Proxmox fwbr 비활성화로 추가 브리지 안 생김 |
| CP 사양 | 2 vCPU / 4GB / 40GB × 3대 | etcd quorum 3, 4GB는 etcd + kube-apiserver 충분 |
| Worker 사양 | 4 vCPU / 6GB / 80GB × 3대 | Percona/Redis 한 개씩은 띄울 여유 |
| Bastion | 1 vCPU / 2GB / 20GB | Ansible runner 용도, 가볍게 |
| VMID | 210~230 | 충돌 회피용 의도적 점프 |

**Ansible 측:**

| 항목 | 값 | 근거 |
|---|---|---|
| ansible_user | ubuntu | cloud-init이 만든 기본 user |
| private_key_file | ~/.ssh/kosa_iac | 우리 SSH alias와 동일 키 |
| retries (kubernetes.core.k8s) | 5, delay 15s | etcd leader change 일시 에러 흡수 |
| K8s 버전 | 1.30.0 | 안정성, EKS 호환 |
| CNI | Calico (Tigera Operator), VXLAN | IPIP보다 호환성 ↑ |
| Pod CIDR | 10.244.0.0/16 | K8s 관례, 다른 대역과 안 겹침 |
| Service CIDR | 10.96.0.0/12 | kubeadm default |
| MetalLB pool | 172.16.23.100~150 | K8s VLAN 30과 같은 대역 (ARP 응답 가능) |

### 4.3 다른 컴포넌트와의 연결

- **Cloud-init 템플릿(VMID 9000)** ← Terraform clone 대상. SSH 키 주입, 정적 IP 주입, qemu-guest-agent 자동 설치까지 cloud-init이 처리.
- **bastion** ← 운영 명령의 단일 진입점. Terraform이 만든 후, scripts/setup-bastion.sh로 도구 설치, Ansible 실행 위치.
- **Ceph RBD** ← VM 디스크 백엔드. 노드 장애 시 다른 노드에서 같은 디스크 부착 가능.
- **pfSense HA** ← VLAN 30/40 게이트웨이. Terraform이 만드는 VM의 `gateway` 변수가 pfSense CARP VIP.

---

## 5. 실제 코드 / 설정 파일

### 5.1 Terraform — modules/vm/main.tf (재사용 모듈)

파일: `/Users/sangjjang/kosa_infra_project/terraform/modules/vm/main.tf`

```hcl
resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.pve_node
  vm_id     = var.vmid
  on_boot   = true

  clone {
    vm_id     = var.template_vm_id     # 9000
    node_name = var.template_vm_node   # kosa1
    full      = true                    # 독립 디스크 (linked clone 아님)
  }

  cpu {
    cores = var.cores
    type  = "host"                      # nested virtualization 가능
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id     # ceph-rbd-team2
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "raw"                # Ceph RBD는 raw만
    discard      = "on"                 # thin provisioning
    ssd          = true
  }

  network_device {
    bridge   = var.bridge                # vmbr0
    vlan_id  = var.vlan_tag              # 30 또는 40
    model    = "virtio"
    firewall = false                     # Proxmox fwbr 비활성화
  }

  dynamic "network_device" {
    for_each = var.ceph_bridge != "" ? [1] : []
    content {
      bridge = var.ceph_bridge           # vmbr1 (Ceph 10G)
      model  = "virtio"
      mtu    = var.ceph_mtu              # 9000 (jumbo)
    }
  }

  initialization {
    datastore_id = var.cloudinit_datastore_id  # local-lvm

    ip_config {
      ipv4 {
        address = var.ip_address          # 172.16.23.10/24
        gateway = var.gateway             # pfSense CARP VIP
      }
    }

    dynamic "ip_config" {
      for_each = var.ceph_ip != "" ? [1] : []
      content {
        ipv4 { address = var.ceph_ip }    # 10.10.10.110/24
      }
    }

    user_account {
      username = "ubuntu"
      keys     = [var.ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [clone]              # 템플릿 변경 시 기존 VM 재생성 방지
  }
}
```

**핵심 라인 + 왜 이 옵션?**
- `full = true`: linked clone은 빠르지만 템플릿 변경에 영향받음. 안정성 우선.
- `cpu.type = "host"`: nested virt(K8s 위 컨테이너) 가능 + 모든 CPU instruction 노출.
- `file_format = "raw"`: Ceph RBD 스토리지는 qcow2/dir/LVM 모드 못 씀. raw 필수.
- `firewall = false`: Proxmox 자체 방화벽 비활성화 → fwbr/fwln/fwpr 브리지 안 생김 → pfSense CARP와 충돌 회피.
- `dynamic "network_device"`: ceph_bridge가 빈 문자열이면 NIC 안 추가 (Bastion 등은 1 NIC만).
- `lifecycle.ignore_changes = [clone]`: 템플릿이 업데이트되어도 기존 VM 재생성 안 함 (서비스 중단 회피).

### 5.2 Terraform — onprem/main.tf (for_each로 7대 생성)

파일: `/Users/sangjjang/kosa_infra_project/terraform/onprem/main.tf`

```hcl
module "k8s_control_plane" {
  source   = "../modules/vm"
  for_each = { for node in var.control_plane_nodes : node.name => node }

  name             = each.value.name
  vmid             = each.value.vmid
  pve_node         = each.value.pve_node
  cores            = each.value.cores
  memory           = each.value.memory
  disk_size        = each.value.disk_size

  ip_address  = "${cidrhost(var.internal_cidr, each.value.ip_suffix)}/${split("/", var.internal_cidr)[1]}"
  gateway     = var.internal_gateway
  ceph_ip     = "${cidrhost(var.ceph_cidr, each.value.ceph_ip_suffix)}/${split("/", var.ceph_cidr)[1]}"
  ...
}
```

**핵심 라인 + 왜 이 옵션?**
- `for_each = { for node in var.control_plane_nodes : node.name => node }`: 리스트를 map으로 변환해서 모듈 3번 호출. 각 VM이 독립 리소스로 관리됨.
- `cidrhost(var.internal_cidr, each.value.ip_suffix)`: CIDR + 끝자리로 IP 자동 계산. `cidrhost("172.16.23.0/24", 10)` = `172.16.23.10`. 끝자리만 변수화하면 깔끔.

### 5.3 Terraform — variables.tf 노드 정의

파일: `/Users/sangjjang/kosa_infra_project/terraform/onprem/variables.tf`

```hcl
variable "control_plane_nodes" {
  default = [
    { name = "k8s-cp1", vmid = 210, pve_node = "kosa4", ip_suffix = 10, ceph_ip_suffix = 110, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp2", vmid = 211, pve_node = "kosa2", ip_suffix = 11, ceph_ip_suffix = 111, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp3", vmid = 212, pve_node = "kosa3", ip_suffix = 12, ceph_ip_suffix = 112, cores = 2, memory = 4096, disk_size = 40 },
  ]
}
```

**왜 이 옵션?**
- cp1 → kosa4 배치: kosa1의 pfSense-1과 메모리 경쟁 해소(2026-05-13 마이그레이션 결과 반영).
- `ceph_ip_suffix = ip_suffix + 100`: VLAN 30 끝자리 보존 → 디버깅 시 매핑 직관적(172.16.23.10 ↔ 10.10.10.110).
- VMID 210~230 점프: 1xx/2xx 충돌 회피, 한눈에 "K8s 리소스" 식별.

### 5.4 Ansible — 00-bootstrap.yml (OS 기본)

파일: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/00-bootstrap.yml`

```yaml
- name: Bootstrap all VMs
  hosts: all
  become: true
  tasks:
    - name: Hostname을 inventory name으로 설정
      ansible.builtin.hostname:
        name: "{{ inventory_hostname }}"

    - name: Swap 비활성화 (K8s 필수 조건)
      ansible.builtin.command: swapoff -a
      when: ansible_swaptotal_mb > 0

    - name: /etc/fstab에서 swap 라인 주석 처리
      ansible.builtin.replace:
        path: /etc/fstab
        regexp: '^([^#].*\sswap\s.*)$'
        replace: '# \1'

    - name: Chrony 활성화 (NTP)
      ansible.builtin.systemd:
        name: chrony
        enabled: true
        state: started
```

**왜 이 옵션?**
- `swapoff -a` + `fstab 주석`: K8s가 swap 켜진 상태에선 kubelet 시작 거부. 즉시 효과 + 재부팅 후 영구.
- chrony NTP: K8s 노드 간 시간 ±1초 이상 차이 나면 etcd 인증서 검증 실패 → 클러스터 깨짐. NTP 필수.

### 5.5 Ansible — 30-k8s-init.yml (클러스터 초기화)

파일: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/30-k8s-init.yml`

```yaml
- name: Initialize the first control plane
  hosts: k8s_control_plane[0]    # 첫 CP만
  become: true
  tasks:
    - name: 이미 init 되어 있는지 확인
      ansible.builtin.stat:
        path: /etc/kubernetes/admin.conf
      register: kubeconfig_check

    - name: kubeadm init 실행
      ansible.builtin.shell: |
        kubeadm init \
          --control-plane-endpoint "{{ kubernetes_api_endpoint }}:{{ kubernetes_api_port }}" \
          --upload-certs \
          --pod-network-cidr={{ pod_subnet }} \
          --service-cidr={{ service_subnet }} \
          --kubernetes-version=v{{ kubernetes_version }}.0
      when: not kubeconfig_check.stat.exists    # 멱등성: 이미 init되어 있으면 skip
```

**왜 이 옵션?**
- `hosts: k8s_control_plane[0]`: 그룹의 첫 호스트만 (인벤토리 파싱 즉시 결정 → 변수 평가 타이밍 이슈 X).
- `--upload-certs`: 다른 CP가 join할 때 자동으로 인증서 받음. 수동 복사 불필요.
- `when: not kubeconfig_check.stat.exists`: 이미 init된 호스트에선 skip → 재실행 안전(멱등성).

### 5.6 Ansible — 40-k8s-addons.yml retries 적용

파일: `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml`

```yaml
- name: Tigera Operator 설치
  kubernetes.core.k8s:
    state: present
    src: https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  register: tigera_apply
  retries: 5
  delay: 15
  until: tigera_apply is succeeded
```

**왜 이 옵션?**
- `retries: 5, delay: 15`: 우리 환경에서 자주 발생하는 `etcdserver: leader changed` 일시 에러를 자동 흡수. 5번 시도(75초) 동안 etcd 안정화 대기.
- `until: tigera_apply is succeeded`: succeeded일 때만 다음 task로. 실패면 retry.

---

## 6. 실행 + 결과

### 6.1 Terraform plan + apply

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project/terraform/onprem
[노트북]$ terraform init
```

실제 출력:
```
Initializing the backend...
Initializing modules...
- bastion in ../modules/vm
- k8s_control_plane in ../modules/vm
- k8s_worker in ../modules/vm

Initializing provider plugins...
- Installing bpg/proxmox v0.66.0...
Terraform has been successfully initialized!
```

```bash
[노트북]$ terraform plan
```

실제 출력 끝:
```
Plan: 7 to add, 0 to change, 0 to destroy.
```

```bash
[노트북]$ terraform apply -parallelism=2 -auto-approve
```

소요: 약 8~12분. 실제 출력 끝:
```
Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

all_vm_summary = tolist([
  "k8s-cp1 (172.16.23.10) on kosa4",
  "k8s-cp2 (172.16.23.11) on kosa2",
  "k8s-cp3 (172.16.23.12) on kosa3",
  "k8s-w1  (172.16.23.20) on kosa3",
  "k8s-w2  (172.16.23.21) on kosa4",
  "k8s-w3  (172.16.23.22) on kosa2",
  "bastion (172.16.24.10) on kosa3",
])
```

### 6.2 Inventory 생성 + bastion 전송

```bash
[노트북]$ ./scripts/generate-inventory.sh
[노트북]$ rsync -avz --exclude='.git' ansible/ bastion:~/ansible/
[노트북]$ scp ~/.ssh/kosa_iac bastion:~/.ssh/kosa_iac
```

### 6.3 Ansible 실행

```bash
[노트북]$ ssh bastion
[bastion]$ cd ~/ansible
[bastion]$ ansible all -m ping
```

실제 출력:
```
bastion | SUCCESS => { "ping": "pong" }
k8s-cp1 | SUCCESS => { "ping": "pong" }
k8s-cp2 | SUCCESS => { "ping": "pong" }
k8s-cp3 | SUCCESS => { "ping": "pong" }
k8s-w1  | SUCCESS => { "ping": "pong" }
k8s-w2  | SUCCESS => { "ping": "pong" }
k8s-w3  | SUCCESS => { "ping": "pong" }
```

```bash
[bastion]$ ansible-playbook playbooks/00-bootstrap.yml
[bastion]$ ansible-playbook playbooks/10-k8s-prepare.yml
[bastion]$ ansible-playbook playbooks/20-k8s-install.yml
[bastion]$ ansible-playbook playbooks/30-k8s-init.yml
[bastion]$ ansible-playbook playbooks/40-k8s-addons.yml
```

각 단계별 소요 — 약 5/5/3/10/15분. 합계 ~40분.

### 6.4 최종 검증

```bash
[bastion]$ kubectl get nodes
```

실제 출력:
```
NAME      STATUS   ROLES           AGE   VERSION
k8s-cp1   Ready    control-plane   42m   v1.30.14
k8s-cp2   Ready    control-plane   38m   v1.30.14
k8s-cp3   Ready    control-plane   37m   v1.30.14
k8s-w1    Ready    <none>          35m   v1.30.14
k8s-w2    Ready    <none>          35m   v1.30.14
k8s-w3    Ready    <none>          35m   v1.30.14
```

---

## 7. 함정 + 디버깅 (우리가 만난 것)

### 7.1 Terraform state vs 실제 환경 불일치 (cp1 수동 마이그레이션)

**증상:** Terraform code에는 cp1이 kosa1에 있는데, 실제로는 메모리 경쟁 때문에 kosa4로 수동 마이그레이션했어요. 다음 `terraform plan` 하면 "kosa1로 옮기겠다"고 변경 제안.

**원인:** Terraform state는 마지막 apply 시점 기준. 외부에서 `qm migrate`로 옮겨도 state엔 안 반영. 다음 plan에서 state(=kosa1)와 .tf(=kosa1)는 같지만, 실제(=kosa4)와 불일치.

엄밀히는 우리는 code를 kosa4로 갱신해서 해결 (`variables.tf`의 `pve_node = "kosa4"`). 그래서 state는 여전히 kosa1을 가리키지만, plan은 "kosa1 → kosa4로 옮긴다"는 변경을 보여줘요. 운영 중 VM은 이미 kosa4에 있으니 실제론 변경 없음 + state만 갱신하면 됨.

**해결 패턴 1: import (state를 실제와 맞춤)**
```bash
[노트북]$ terraform state rm 'module.k8s_control_plane["k8s-cp1"].proxmox_virtual_environment_vm.this'
[노트북]$ terraform import 'module.k8s_control_plane["k8s-cp1"].proxmox_virtual_environment_vm.this' kosa4/qemu/210
```

**해결 패턴 2: state mv (provider가 node_name을 추적하면)**
```bash
[노트북]$ terraform apply -refresh-only
```

**왜 이 함정이 발생하는가 (메커니즘):**
Terraform은 자체 state(=신뢰 원천)와 .tf 코드(=원하는 상태)의 diff로 작업해요. 외부 변경(수동 마이그레이션, UI 클릭)을 안 반영하므로 drift가 누적되면 plan이 위험한 변경(VM 재생성 등)을 제안할 수 있음. **rule of thumb — Terraform이 만든 리소스는 Terraform으로만 변경**. 부득이 손대면 즉시 import/refresh로 state 동기화. 출처: Session_Handoff.md / inventory.md 표 2.

### 7.2 Ansible — etcd leader change 일시 에러

**증상:**
```
TASK [Tigera Operator 설치] ******************
fatal: [k8s-cp1]: FAILED! => {"msg": "Failed to apply: etcdserver: leader changed"}
```

**원인:** 3-CP 클러스터 초기엔 etcd 리더 선출이 진행 중. K8s API server가 etcd write 요청 보내는 순간 리더가 바뀌면 일시 거부.

**해결:** Ansible task에 `retries` 추가.

```yaml
- name: Tigera Operator 설치
  kubernetes.core.k8s:
    state: present
    src: https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml
  register: tigera_apply
  retries: 5
  delay: 15
  until: tigera_apply is succeeded
```

**왜 이 함정이 발생하는가 (메커니즘):**
etcd는 Raft 합의 프로토콜. 리더가 죽거나 부하 ↑이면 다른 노드에서 election. 그 짧은 순간(보통 1~3초) write 요청이 거부됩니다. K8s API server는 retry를 일부 해주지만 ansible 같은 외부 호출이 timeout 안에 안 들어오면 실패. → 클라이언트 측 retry로 흡수해야 함. 우리 환경에선 cp1이 kosa1에 있을 때 pfSense-1 메모리 경쟁으로 leader change가 빈번했고, cp1 → kosa4 이동 후 빈도 감소. 출처: Session_Handoff.md / 40-k8s-addons.yml.

### 7.3 ansible-galaxy not found on 노트북

**증상:** 노트북에서 `ansible-galaxy collection install` 실행했더니 `command not found`.

**원인:** 우리는 Ansible을 bastion에만 설치하기로 결정 — 노트북엔 Terraform만. 노트북에서 ansible-galaxy 호출은 의도와 다름.

**해결:** Galaxy 설치는 bastion에서.
```bash
[노트북]$ ssh bastion
[bastion]$ cd ~/ansible
[bastion]$ ansible-galaxy collection install -r requirements.yml
```

**왜 이 함정이 발생하는가 (메커니즘):**
"실행 위치"가 명확해야 IaC가 작동. 우리 표준은 Terraform=노트북, Ansible=bastion. 한 컴퓨터에서 다 하는 게 학습엔 편하지만 — bastion 패턴이 운영 표준이라 그대로 가져감. 노트북에서 노트북 디스크의 ansible 폴더에서 실행했다가 inventory_hostname 못 찾는 다른 함정도 있어요. 출처: Session_Handoff.md.

### 7.4 PEP 668 — pip install 차단 (Ubuntu 24.04)

**증상:** `pip install kubernetes` 실행 시 `error: externally-managed-environment`.

**원인:** Ubuntu 24.04부터 시스템 Python의 pip 사용 차단(PEP 668). venv 또는 명시적 flag 필요.

**해결:** 40-k8s-addons.yml의 0번 task에 `--break-system-packages` 추가.

```yaml
- name: kubernetes / pyyaml Python 라이브러리 설치
  ansible.builtin.pip:
    name:
      - kubernetes
      - PyYAML
    extra_args: --break-system-packages
    executable: pip3
```

**왜 이 함정이 발생하는가 (메커니즘):**
시스템 패키지 매니저(apt)와 pip가 같은 Python 라이브러리를 다르게 관리하면 충돌. PEP 668은 시스템 Python 보호. 운영 정석은 venv 만들기, 임시 학습 환경엔 `--break-system-packages` 허용. Ansible Galaxy의 kubernetes.core 모듈이 Python 측 kubernetes 라이브러리에 의존 → 이걸 설치해야 K8s 리소스 task가 동작. 출처: 40-k8s-addons.yml 주석.

### 7.5 `Found both group and host with same name: bastion` WARNING

**증상:** 매번 ansible 실행 시 WARNING.

**원인:** inventory에 `bastion` 그룹과 `bastion` 호스트가 같은 이름. Ansible은 충돌 경고하지만 동작은 정상.

**해결:** 무시. 동작에는 영향 없음. 정리하려면 그룹 이름을 `bastion_hosts`로 변경.

**왜 이 함정이 발생하는가 (메커니즘):**
Ansible inventory의 group과 host는 별개 네임스페이스지만 같은 이름은 어느 변수가 우선되는지 헷갈리게 함. 운영 환경에선 prefix(`bastion_grp` / `bastion_host`)로 구분 권장.

---

## 8. 더 깊이 공부할 자료

**Terraform:**
- 공식 docs: https://developer.hashicorp.com/terraform/docs
- bpg/proxmox provider: https://registry.terraform.io/providers/bpg/proxmox/latest/docs
- 책 `Terraform: Up & Running` 3판 (O'Reilly, 2022) — 모듈 구조의 정석
- OpenTofu (Terraform fork): https://opentofu.org

**Ansible:**
- 공식 docs: https://docs.ansible.com/
- 책 `Ansible for DevOps` (Jeff Geerling) — 가장 실무 친화
- kubernetes.core 컬렉션: https://docs.ansible.com/ansible/latest/collections/kubernetes/core/
- Galaxy: https://galaxy.ansible.com

**참고 우리 프로젝트 파일:**
- `/Users/sangjjang/kosa_infra_project/terraform/onprem/main.tf`
- `/Users/sangjjang/kosa_infra_project/terraform/onprem/variables.tf`
- `/Users/sangjjang/kosa_infra_project/terraform/modules/vm/main.tf`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/00-bootstrap.yml`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/10-k8s-prepare.yml`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/20-k8s-install.yml`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/30-k8s-init.yml`
- `/Users/sangjjang/kosa_infra_project/ansible/playbooks/40-k8s-addons.yml`
- `/Users/sangjjang/kosa_infra_project/Session_Handoff.md`
- `/Users/sangjjang/kosa_infra_project/Onprem_Build_Guide.md` Phase 3, 4
- `/Users/sangjjang/kosa_infra_project/inventory.md` 표 2 함정

---

## 다음 챕터 미리보기

**챕터 15: ticket-app (FastAPI + 앱 배포)**에서는 우리가 시연용으로 만든 좌석 100개짜리 티켓팅 앱 — FastAPI 백엔드, 좌석 그리드 HTML, Dockerfile, K8s 매니페스트, GHCR 빌드/배포 흐름 — 을 다룰 거예요. 왜 Flask가 아니라 FastAPI인지, 왜 마이크로서비스 안 쓰고 단일 앱인지, 그리고 GHCR private/public 정책으로 막혔던 함정과 env 이름 미스매치(DB_HOST vs DATABASE_HOST) 함정의 메커니즘도 들여다볼게요.
