# 온프레미스 구축 가이드 (Day 1~5)

> kosa-tickets 프로젝트의 온프레미스 K8s 클러스터를 0부터 구축하는 단계별 가이드.
> **Terraform + Ansible로 자동화**, 각 단계마다 **"어디서 실행"** 과 **검증 명령** 포함.
>
> 관련 문서: [Architecture_Design.md](Architecture_Design.md) | [IaC_Setup_Guide.md](IaC_Setup_Guide.md) | [SSH_Access_Guide.md](SSH_Access_Guide.md) | [Why_Bastion.md](Why_Bastion.md)

---

## 0. 실행 위치 표기 약속 (먼저 읽기) ⭐

이 문서는 명령마다 **어디서 실행해야 하는지** 라벨로 표시함. 라벨 4가지:

| 라벨 | 위치 | 접속 방법 | 용도 |
|---|---|---|---|
| `[노트북]` | 본인 맥북/PC (192.168.21.x) | 터미널 열기 | Terraform 실행, scp/ssh 시작점 |
| `[kosaN]` | Proxmox 호스트 (192.168.21.2~5) | `ssh kosa1` (root) | VM 템플릿 만들기, Ceph 명령 |
| `[bastion]` | Bastion VM (172.16.24.10) | `ssh bastion` (ubuntu) | Ansible, kubectl, helm, argocd 실행 |
| `[k8s-XXX]` | K8s 노드 (172.16.23.10~22) | `ssh k8s-cp1` (ubuntu) | 디버깅용. 일반적으로 직접 X |

> SSH alias 설정은 `SSH_Access_Guide.md` 참고. 본 가이드는 alias 설정 완료 가정.

**실행 위치별 책임 분담:**

```
[노트북]   = "코드 보관 + Terraform 실행"     (코드 원본은 노트북에)
[kosaN]   = "VM 인프라 작업"                  (템플릿, Ceph 등)
[bastion] = "K8s 운영 + Ansible 실행"          (운영 모든 명령은 여기서)
[k8s-XXX] = "거의 안 들어감"                   (디버깅 용)
```

---

## 목차

- [목표 결과물](#목표-결과물)
- [사전 준비 체크리스트](#사전-준비-체크리스트)
- [Phase 1: Proxmox 네트워크 (완료)](#phase-1-proxmox-네트워크-완료)
- [Phase 2: Cloud-init 템플릿 (Day 1)](#phase-2-cloud-init-템플릿-day-1)
- [Phase 3: Terraform으로 VM 생성 (Day 2)](#phase-3-terraform으로-vm-생성-day-2)
- [Phase 4: Ansible로 K8s 부트스트랩 (Day 3)](#phase-4-ansible로-k8s-부트스트랩-day-3)
- [Phase 5: Ceph CSI 연결 (Day 4)](#phase-5-ceph-csi-연결-day-4)
- [Phase 6: ArgoCD + Harbor + 핵심 워크로드 (Day 5)](#phase-6-argocd--harbor--핵심-워크로드-day-5)
- [최종 검증](#최종-검증)
- [트러블슈팅](#트러블슈팅)

---

## 목표 결과물

5일 후 다음 상태 도달:

```
✓ Proxmox 4대 위에 K8s 6대 + Bastion 1대 운영
✓ Calico CNI, MetalLB, Metrics Server 정상 동작
✓ Ceph RBD CSI로 동적 PV 프로비저닝
✓ ArgoCD 설치 (GitOps 준비)
✓ Harbor 컨테이너 레지스트리
✓ Percona PXC × 3 + ProxySQL × 2 배포 (Operator)
✓ Redis Sentinel
✓ Prometheus + Grafana 기본 대시보드
```

K8s 노드 6대 = CP 3 + Worker 3 (Bastion은 K8s 멤버 아님, 도구 호스트).

---

## 사전 준비 체크리스트

### 하드웨어 / 네트워크
- [ ] Proxmox 4대 (kosa1~kosa4) 정상 작동
- [ ] pfSense HA 완료 ✓
- [ ] 관리형 스위치 VLAN 10/20/30/40 설정 ✓
- [ ] Ceph 클러스터 6대 정상 (`ceph status` HEALTH_OK)
- [ ] [노트북]에서 Proxmox 4대로 ssh 가능 (`ssh kosa1`)

### 도구 (노트북에 설치)
- [ ] **Terraform 1.5+**: `[노트북]$ terraform version`
- [ ] **SSH 키**: `~/.ssh/kosa_iac` (없으면 아래 생성)
- [ ] **Proxmox API 토큰** (아래 발급)

> Ansible은 [Bastion]에 설치하면 됨. 노트북엔 굳이 안 깔아도 됨.

### Proxmox API 토큰 발급

1. Proxmox Web UI → **Datacenter → Permissions → API Tokens → Add**
2. 입력:
   - User: `root@pam`
   - Token ID: `terraform`
   - ☐ **Privilege Separation 해제** (학습 편의)
3. **Secret 복사** (한 번만 표시됨!)

토큰 결과:
```
TokenID: root@pam!terraform
Secret:  xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### SSH 키 생성

```bash
[노트북]$ ssh-keygen -t ed25519 -C "kosa-iac" -f ~/.ssh/kosa_iac
[노트북]$ cat ~/.ssh/kosa_iac.pub   # terraform.tfvars에 넣을 값
```

---

## Phase 1: Proxmox 네트워크 (완료)

> pfSense HA 완료 시점에 이미 끝난 단계.
> 상세: `pfSense_HA_Setup_Guide.md`.

검증:
```bash
[노트북]$ ping 172.16.21.1   # VLAN 10 게이트웨이 (CARP VIP)
[노트북]$ ping 172.16.22.1   # VLAN 20
[노트북]$ ping 172.16.23.1   # VLAN 30 (K8s)
[노트북]$ ping 172.16.24.1   # VLAN 40 (Mgmt)
```

모두 응답하면 OK.

---

## Phase 2: Cloud-init 템플릿 (Day 1)

> **한 번만** 만들면 됨. Terraform이 이걸 clone해서 7개 VM 생성.
> 실행 위치: **[kosa1]** (템플릿은 1대에만 만듦, Ceph 공유라 다른 노드도 사용 가능)

### 2.1 Ubuntu Cloud Image 다운로드

```bash
[노트북]$ ssh kosa1

[kosa1]# cd /var/lib/vz/template/iso
[kosa1]# wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
[kosa1]# ls -lh noble-server-cloudimg-amd64.img
# 약 600MB (Ubuntu 24.04 Noble)
```

> ⚠️ **일반 Live ISO와 다름**: Cloud Image는 cloud-init 활성화된 이미 설치된 이미지. 일반 Live Server ISO는 부팅 후 설치 마법사가 떠서 자동화 불가.

### 2.2 qemu-guest-agent 사전 주입 (선택, 강추)

cloud-init이 부팅 후 설치할 수도 있지만 이미지에 미리 넣으면 안정적:

```bash
[kosa1]# apt-get install -y libguestfs-tools   # 한 번만
[kosa1]# virt-customize -a noble-server-cloudimg-amd64.img \
           --install qemu-guest-agent \
           --run-command 'systemctl enable qemu-guest-agent'
```

### 2.3 템플릿 VM 생성 (VMID 9000)

```bash
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

# Ceph RBD에 디스크 import (다른 노드에서도 clone 가능하려면 Ceph 필수)
[kosa1]# qm importdisk 9000 noble-server-cloudimg-amd64.img ceph-rbd-team2

# 디스크 연결
[kosa1]# qm set 9000 --scsi0 ceph-rbd-team2:vm-9000-disk-0,discard=on,ssd=1

# cloud-init 드라이브 (local-lvm OK, 작은 ISO)
[kosa1]# qm set 9000 --ide2 local-lvm:cloudinit

# 부팅 디스크 지정
[kosa1]# qm set 9000 --boot c --bootdisk scsi0

# 템플릿화
[kosa1]# qm template 9000
```

### 2.4 검증

```bash
[kosa1]# qm config 9000 | grep -E "template|scsi0|cpu|agent"
```

기대 출력 (핵심 부분):
```
agent: enabled=1
cpu: host
scsi0: ceph-rbd-team2:base-9000-disk-0,discard=on,size=...,ssd=1
template: 1
```

`template: 1` 보이고 `scsi0`이 `ceph-rbd-team2` 시작이면 OK.

> ✅ 이미 완료된 상태로 들어왔다면 이 Phase 스킵.

---

## Phase 3: Terraform으로 VM 생성 (Day 2)

> 실행 위치: **[노트북]**
> (Terraform state 파일이 노트북에 보관됨)

### 3.1 변수 파일 작성

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project/terraform/onprem
[노트북]$ cp terraform.tfvars.example terraform.tfvars
[노트북]$ vim terraform.tfvars
```

`terraform.tfvars` 필수 항목:
```hcl
proxmox_endpoint  = "https://192.168.21.2:8006/"
proxmox_api_token = "root@pam!terraform=<2.0절_Secret>"
ssh_public_key    = "ssh-ed25519 AAAA... kosa-iac"
```

### 3.2 Terraform 초기화

```bash
[노트북]$ terraform init
```

기대 출력 끝:
```
- Installing bpg/proxmox v0.66.x...
Terraform has been successfully initialized!
```

### 3.3 변경 미리보기

```bash
[노트북]$ terraform plan
```

기대 출력 끝:
```
Plan: 7 to add, 0 to change, 0 to destroy.
```

7대 VM 생성 계획 확인.

### 3.4 VM 생성

```bash
[노트북]$ terraform apply -parallelism=2 -auto-approve
```

> `-parallelism=2` 권장: 동시 7대 clone은 Proxmox에 부담. 동시 2대씩 처리해도 ~8분이면 끝남.

소요: **약 8~12분**. 진행 중 다른 터미널에서 실시간 모니터링:

```bash
# 다른 [노트북] 터미널
[노트북]$ watch -n 5 'ssh kosa1 "pvesh get /cluster/resources --type vm" | grep -E "vm/2[123][0-9]"'
```

### 3.5 검증 — VM이 의도한 노드에 분산됐는지

```bash
[노트북]$ terraform output all_vm_summary
```

기대 출력:
```
tolist([
  "k8s-cp1 (172.16.23.10) on kosa1",
  "k8s-cp2 (172.16.23.11) on kosa2",
  "k8s-cp3 (172.16.23.12) on kosa3",
  "k8s-w1  (172.16.23.20) on kosa3",
  "k8s-w2  (172.16.23.21) on kosa4",
  "k8s-w3  (172.16.23.22) on kosa2",
  "bastion (172.16.24.10) on kosa3",
])
```

### 3.6 모든 VM SSH 동작 확인

```bash
[노트북]$ for h in k8s-cp1 k8s-cp2 k8s-cp3 k8s-w1 k8s-w2 k8s-w3 bastion; do
  echo -n "$h: "
  ssh -o ConnectTimeout=5 $h 'echo OK hostname=$(hostname) ci=$(cloud-init status | tail -1)' 2>/dev/null || echo FAIL
done
```

기대: 7개 모두 `OK hostname=... ci=status: done`.

> 만약 cloud-init이 `running` 상태면 1~2분 더 대기 후 재시도.

### 3.7 코드 Git 커밋 (선택)

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project
[노트북]$ git add terraform/onprem/
[노트북]$ git commit -m "Add onprem Terraform code (CP3 + W3 + Bastion)"
# terraform.tfvars 는 .gitignore에 있어 안 들어감 ✓
```

---

## Phase 4: Ansible로 K8s 부트스트랩 (Day 3) ⭐

> 가장 중요한 단계. 매 명령마다 **어디서 실행하는지** 라벨로 표시.
> 막히면 가장 마지막 ✅ 체크포인트로 돌아가서 다시 시도.

### 4.0 큰 그림

```
[노트북]                                [bastion]                   [K8s VM 6대]
   │                                       │                            │
   │ ① scripts 권한 부여 + ~/.ssh/config 설정 (사전)                       │
   │ ② generate-inventory.sh → inventory 생성                            │
   │ ③ rsync로 코드/키를 bastion에 전송 ──→ │                            │
   │ ④ ssh bastion ──────────────────────→ │                            │
   │                                       │ ⑤ apt-get으로 ansible 등 설치 │
   │                                       │ ⑥ ansible all -m ping       │
   │                                       │ ⑦ ansible-playbook 순차 실행 │
   │                                       │ ──ssh────────────────────→ │
   │                                       │   각 VM에 패키지/설정 적용     │
   │                                       │   K8s 클러스터 구성         │
```

**한 번에 보는 명령 시퀀스:**

```bash
# [노트북] ─────────────────────────────────────────────────────
chmod +x scripts/*.sh                              # 4.1
cat >> ~/.ssh/config <<EOF ... EOF                 # 4.1
ssh bastion 'echo OK'                              # 4.1 검증
./scripts/generate-inventory.sh                    # 4.2
rsync -avz ansible/ bastion:~/ansible/             # 4.3
scp ~/.ssh/kosa_iac bastion:~/.ssh/kosa_iac        # 4.3
ssh bastion 'bash -s' < scripts/setup-bastion.sh   # 4.4 (자동) 
ssh bastion                                        # 4.5

# [bastion] ───────────────────────────────────────────────────
cd ~/ansible
ansible-galaxy collection install -r requirements.yml  # 4.5
ansible all -m ping                                    # 4.5 검증
ansible-playbook playbooks/00-bootstrap.yml            # 4.6 Step 1
ansible-playbook playbooks/10-k8s-prepare.yml          # 4.6 Step 2
ansible-playbook playbooks/20-k8s-install.yml          # 4.6 Step 3
ansible-playbook playbooks/30-k8s-init.yml             # 4.6 Step 4
ansible-playbook playbooks/40-k8s-addons.yml           # 4.6 Step 5
```

---

### 4.1 [노트북] 사전 준비 (필수 — 빼먹으면 다음 단계에서 막힘) ⚠️

세 가지를 먼저 처리: **(A) scripts 실행 권한**, **(B) SSH config**, **(C) 연결 테스트**.

#### (A) scripts 실행 권한

`generate-inventory.sh` 같은 셸 스크립트가 `permission denied` 안 나도록:

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project
[노트북]$ chmod +x scripts/*.sh
[노트북]$ ls -l scripts/
```

기대 — 끝에 `x` 권한 있어야 함:
```
-rwxr-xr-x  ...  generate-inventory.sh
-rwxr-xr-x  ...  setup-bastion.sh
```

#### (B) ~/.ssh/config 설정 (bastion 같은 alias 등록)

`bastion`, `k8s-cp1` 같은 단축 이름으로 SSH 가능하게 등록. 한 번만:

```bash
[노트북]$ cat >> ~/.ssh/config <<'EOF'

# === KOSA Proxmox (root) ===
Host kosa1
  HostName 192.168.21.2
  User root
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes

Host kosa2
  HostName 192.168.21.3
  User root
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes

Host kosa3
  HostName 192.168.21.4
  User root
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes

Host kosa4
  HostName 192.168.21.5
  User root
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes

# === KOSA K8s VM (ubuntu) ===
Host bastion
  HostName 172.16.24.10
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-cp1
  HostName 172.16.23.10
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-cp2
  HostName 172.16.23.11
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-cp3
  HostName 172.16.23.12
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-w1
  HostName 172.16.23.20
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-w2
  HostName 172.16.23.21
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null

Host k8s-w3
  HostName 172.16.23.22
  User ubuntu
  IdentityFile ~/.ssh/kosa_iac
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF

[노트북]$ chmod 600 ~/.ssh/config
```

> `StrictHostKeyChecking no` + `UserKnownHostsFile /dev/null`은 학습/데모용 — VM 재생성 시 host key 변경 경고 회피. 운영에선 빼야 함.

#### (C) ✅ 체크포인트 — bastion 접속 + 7대 VM SSH 모두 OK인지 확인

```bash
[노트북]$ ssh bastion 'echo OK from bastion'
# 기대: OK from bastion

[노트북]$ for h in bastion k8s-cp1 k8s-cp2 k8s-cp3 k8s-w1 k8s-w2 k8s-w3; do
  echo -n "$h: "
  ssh -o ConnectTimeout=5 $h 'hostname' 2>/dev/null || echo FAIL
done
```

기대 — 7대 모두 hostname 출력:
```
bastion: bastion
k8s-cp1: k8s-cp1
...
```

❌ 만약 `Could not resolve hostname bastion` 나오면 → (B) 단계 다시. config 파일 권한이 600인지도 확인.
❌ 만약 `Permission denied (publickey)` → `~/.ssh/kosa_iac` 파일 권한 600 확인: `chmod 600 ~/.ssh/kosa_iac`.

---

### 4.2 [노트북] Inventory 생성

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project
[노트북]$ ./scripts/generate-inventory.sh
```

이 스크립트가 하는 일:
1. `terraform/onprem` 디렉토리에서 `terraform output -raw ansible_inventory` 실행
2. 결과 YAML을 `ansible/inventory/hosts.yml` 에 저장
3. 기존 파일 있으면 `.bak.<timestamp>` 로 백업

#### ✅ 체크포인트

```bash
[노트북]$ cat ansible/inventory/hosts.yml | head -20
```

기대 — `all:` 으로 시작하는 YAML, 7개 호스트 IP가 보임:
```yaml
"all":
  "vars":
    "ansible_user": "ubuntu"
    "ansible_ssh_private_key_file": "~/.ssh/kosa_iac"
  "children":
    "bastion":
      "hosts":
        "bastion":
          "ansible_host": "172.16.24.10"
    "k8s_control_plane":
      "hosts":
        "k8s-cp1":
          "ansible_host": "172.16.23.10"
        ...
```

❌ `Error: terraform.tfstate 없음` → `cd terraform/onprem && terraform apply` 먼저 (Phase 3).

---

### 4.3 [노트북] Bastion에 코드 + SSH 키 전송

```bash
[노트북]$ cd /Users/sangjjang/kosa_infra_project

# 1) ansible 디렉토리 전체를 bastion 홈으로
[노트북]$ rsync -avz --exclude='.git' ansible/ bastion:~/ansible/

# 2) bastion이 K8s VM 6대에 SSH 들어가야 하므로 private key도 같이 전송
[노트북]$ scp ~/.ssh/kosa_iac bastion:~/.ssh/kosa_iac
[노트북]$ ssh bastion 'chmod 600 ~/.ssh/kosa_iac'

# 3) bastion의 ~/.ssh/config에도 K8s VM alias 등록 (선택, 편의용)
[노트북]$ scp ~/.ssh/config bastion:~/.ssh/config
[노트북]$ ssh bastion 'chmod 600 ~/.ssh/config'
```

> 🔐 **보안 노트**: kosa_iac 개인키를 bastion에 복사하는 건 운영에선 비추. 운영 환경에선 SSH agent forwarding 또는 별도 bastion 전용 키 사용. 학습 환경에선 편의상 복사.

#### ✅ 체크포인트

```bash
[노트북]$ ssh bastion 'ls -la ~/ansible/ && ls -la ~/.ssh/'
```

기대 — `~/ansible/` 안에 playbooks/, inventory/, roles/, requirements.yml 등 보임. `~/.ssh/` 안에 `kosa_iac` (권한 -rw-------) 있음.

❌ `bastion: Could not resolve hostname` → 4.1 (B) 단계 안 됨. SSH config 다시 확인.

---

### 4.4 [bastion] 도구 설치 (ansible, kubectl, helm, argocd)

방법 두 가지. 둘 다 결과 같음.

#### 방법 A — 자동화 스크립트 (권장, 노트북에서 한 줄)

```bash
[노트북]$ ssh bastion 'bash -s' < scripts/setup-bastion.sh
```

#### 방법 B — 수동 (스크립트 안 쓰고 직접)

```bash
[노트북]$ ssh bastion

# 여기서부터 [bastion] 안
[bastion]$ sudo apt-get update
[bastion]$ sudo apt-get install -y \
            git curl wget vim jq python3-pip \
            software-properties-common

# Ansible
[bastion]$ sudo add-apt-repository --yes --update ppa:ansible/ansible
[bastion]$ sudo apt-get install -y ansible

# kubectl (K8s v1.30)
[bastion]$ sudo mkdir -p /etc/apt/keyrings
[bastion]$ curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
            sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
[bastion]$ echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
            sudo tee /etc/apt/sources.list.d/kubernetes.list
[bastion]$ sudo apt-get update && sudo apt-get install -y kubectl

# Helm
[bastion]$ curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ArgoCD CLI
[bastion]$ sudo curl -sSL -o /usr/local/bin/argocd \
            https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
[bastion]$ sudo chmod +x /usr/local/bin/argocd
```

#### ✅ 체크포인트 (bastion 안에서)

```bash
[bastion]$ ansible --version && \
           kubectl version --client && \
           helm version --short && \
           argocd version --client
```

기대 — 4개 모두 버전이 출력 (에러 없이):
```
ansible [core 2.16.x]
Client Version: v1.30.x
v3.14.x
argocd: v2.10.x
```

❌ `command not found: ansible` → apt 설치 단계 실패. `sudo apt-get install -y ansible` 다시.

---

### 4.5 [bastion] Ansible Collection + 연결 테스트

이 시점부턴 **모든 명령은 bastion 안에서**.

```bash
[bastion]$ cd ~/ansible
[bastion]$ ansible-galaxy collection install -r requirements.yml
```

기대 출력 — 컬렉션 다운로드 진행:
```
Starting galaxy collection install process
...
Installing 'community.general:X.X.X' to '/home/ubuntu/.ansible/...'
Installing 'kubernetes.core:X.X.X' to '/home/ubuntu/.ansible/...'
```

#### ✅ 체크포인트 — 7대 VM 모두 ping OK

```bash
[bastion]$ ansible all -m ping
```

기대 — 7개 모두 `SUCCESS`:
```
bastion | SUCCESS => { "ping": "pong" }
k8s-cp1 | SUCCESS => { "ping": "pong" }
k8s-cp2 | SUCCESS => { "ping": "pong" }
k8s-cp3 | SUCCESS => { "ping": "pong" }
k8s-w1  | SUCCESS => { "ping": "pong" }
k8s-w2  | SUCCESS => { "ping": "pong" }
k8s-w3  | SUCCESS => { "ping": "pong" }
```

❌ `UNREACHABLE! ... Permission denied (publickey)` → bastion의 `~/.ssh/kosa_iac` 권한 확인 (`chmod 600`). 또는 `ansible/ansible.cfg`의 `private_key_file` 경로가 `~/.ssh/kosa_iac` 인지 확인.
❌ `UNREACHABLE! ... timeout` → bastion 자체 라우팅 문제. `[bastion]$ ping 172.16.23.10` 으로 테스트.

---

### 4.6 [bastion] 단계별 Playbook 실행

여기서부터 모든 명령은 **bastion 안**. 각 Step 끝나면 검증.

#### Step 1 — 기본 OS 설정 (~5분)

```bash
[bastion]$ ansible-playbook playbooks/00-bootstrap.yml
```

작업 내용:
- hostname 설정
- swap 비활성화 (K8s 필수)
- timezone Asia/Seoul
- NTP (chrony) 동기화
- 기본 패키지 (curl, vim, jq 등)

검증:
```bash
[bastion]$ ansible k8s_cluster -m shell -a "swapon -s; date"
# swap 빈 출력 + Asia/Seoul 시간대
```

#### Step 2 — containerd + 커널 설정 (~5분)

```bash
[bastion]$ ansible-playbook playbooks/10-k8s-prepare.yml
```

작업 내용:
- `overlay`, `br_netfilter` 커널 모듈 로드
- sysctl: `ip_forward=1`, `bridge-nf-call-iptables=1`
- **containerd 설치** (Docker 아님)
- containerd가 systemd cgroup 사용하도록 설정

검증:
```bash
[bastion]$ ansible k8s_cluster -m shell -a "systemctl is-active containerd && lsmod | grep br_netfilter"
# 모두 active
```

#### Step 3 — kubeadm/kubelet/kubectl 설치 (~3분)

```bash
[bastion]$ ansible-playbook playbooks/20-k8s-install.yml
```

작업 내용:
- Kubernetes apt repo 추가 (`pkgs.k8s.io v1.30`)
- kubeadm, kubelet, kubectl 설치
- `apt-mark hold` (자동 업그레이드 방지)

검증:
```bash
[bastion]$ ansible k8s_cluster -m shell -a "kubeadm version -o short"
# v1.30.x
```

#### Step 4 — 클러스터 초기화 + Join (~10분)

```bash
[bastion]$ ansible-playbook playbooks/30-k8s-init.yml
```

작업 내용:
- k8s-cp1: `kubeadm init` (첫 CP, 단일 endpoint 모드)
- k8s-cp2, cp3: `kubeadm join --control-plane`
- k8s-w1, w2, w3: `kubeadm join` (워커)
- Bastion에 `/etc/kubernetes/admin.conf` 복사 → `~/.kube/config`

검증:
```bash
[bastion]$ kubectl get nodes
```

기대 출력:
```
NAME      STATUS     ROLES           AGE   VERSION
k8s-cp1   NotReady   control-plane   5m    v1.30.x
k8s-cp2   NotReady   control-plane   3m    v1.30.x
k8s-cp3   NotReady   control-plane   2m    v1.30.x
k8s-w1    NotReady   <none>          1m    v1.30.x
k8s-w2    NotReady   <none>          1m    v1.30.x
k8s-w3    NotReady   <none>          1m    v1.30.x
```

**NotReady 정상**. CNI 미설치 상태. 다음 step에서 해결.

#### Step 5 — Calico + MetalLB + HAProxy Ingress + Percona Operator (~10분)

```bash
[bastion]$ ansible-playbook playbooks/40-k8s-addons.yml
```

작업 내용:
- Tigera Operator → Calico CNI
- Metrics Server (`--kubelet-insecure-tls`)
- MetalLB + IP 풀 (`172.16.22.50-100`)
- **HAProxy Ingress** (NGINX 아님, L4+L7)
- cert-manager (TLS 자동)
- Percona Operator + PXC 3 + ProxySQL 2

검증:
```bash
[bastion]$ kubectl get nodes
# 모두 Ready

[bastion]$ kubectl get pods -A | grep -v Running | grep -v Completed
# 빈 출력 (모두 Running 또는 Completed)

[bastion]$ kubectl top nodes
# CPU/Memory 사용량 표시
```

### 4.7 한 번에 실행 (학습 후 권장)

```bash
[bastion]$ ansible-playbook playbooks/site.yml
```

site.yml은 00~40을 순차 실행. 총 ~30~40분.

---

## Phase 5: Ceph CSI 연결 (Day 4)

> 실행 위치 분리:
> - **[ceph-mon]** = Ceph 클러스터의 모니터 노드 (별도 6대 클러스터)
> - **[bastion]** = K8s 측 Helm 설치

### 5.1 Ceph 클러스터 정보 수집 ([ceph-mon] 에서)

> **네이밍 컨벤션:** `team2-<사용주체>-<용도>-<타입>` 형태로 통일.
> 이름만 보고도 "team2팀의, K8s가, PVC용으로 쓰는, RBD pool"임이 보이도록 함.
>
> | 리소스 | 이름 | 의미 |
> |---|---|---|
> | Pool | `team2-k8s-pvc-rbd` | team2 K8s PVC용 RBD pool |
> | User | `client.team2-k8s-csi` | team2 K8s CSI 드라이버 client |
> | StorageClass | `team2-rbd-block` | team2 RBD 기반 block StorageClass |
> | Secret | `team2-rbd-csi-secret` | RBD CSI 자격증명 |

```bash
[노트북]$ ssh root@<ceph-mon-IP>   # 예: 10.10.10.x

# 1) 클러스터 ID (fsid) 확인
[ceph-mon]# ceph fsid
# 예: abcdef12-3456-7890-...

# 2) 모니터 IP 목록 확인 (실제 IP를 5.2 values.yaml에 그대로 넣을 것)
[ceph-mon]# ceph mon dump

# 3) 기존 Pool 확인 (Proxmox용 ceph-rbd-team2 외 다른 pool 충돌 방지)
[ceph-mon]# ceph osd pool ls

# 4) K8s PVC용 Pool 생성
[ceph-mon]# ceph osd pool create team2-k8s-pvc-rbd 64 64 replicated
[ceph-mon]# rbd pool init team2-k8s-pvc-rbd

# 5) K8s CSI 전용 user 생성 (team2-k8s-pvc-rbd pool만 접근 권한)
[ceph-mon]# ceph auth get-or-create client.team2-k8s-csi \
              mon 'profile rbd' \
              osd 'profile rbd pool=team2-k8s-pvc-rbd' \
              -o /etc/ceph/ceph.client.team2-k8s-csi.keyring

# 6) 키 확인 (5.2의 userKey에 들어갈 값)
[ceph-mon]# cat /etc/ceph/ceph.client.team2-k8s-csi.keyring
# [client.team2-k8s-csi]
#     key = AQABcD...==     ← 이 값만 복사

# 7) 권한 검증 (옵션, 새 user가 pool 접근 가능한지 확인)
[ceph-mon]# ceph auth get client.team2-k8s-csi
```

**메모해둘 3가지:**
- `fsid` (1번 결과)
- `monitor IPs` (2번 결과의 v1 주소들, `IP:6789` 형태)
- `keyring`의 `key = ...` 값 (6번 결과)

### 5.2 Ceph CSI 설치 (Helm) ([bastion] 에서)

```bash
[bastion]$ helm repo add ceph-csi https://ceph.github.io/csi-charts
[bastion]$ helm repo update

# values.yaml 작성 (5.1에서 받은 값 채워넣기)
# monitors 목록은 'ceph mon dump' 결과의 실제 IP를 그대로 사용할 것
[bastion]$ cat > /tmp/ceph-csi-rbd-values.yaml <<EOF
csiConfig:
  - clusterID: "<5.1의 fsid>"
    monitors:
      - "10.10.10.11:6789"
      - "10.10.10.12:6789"
      - "10.10.10.13:6789"
      - "10.10.10.14:6789"
storageClass:
  create: true
  name: team2-rbd-block               # team2 RBD 기반 block StorageClass
  clusterID: "<5.1의 fsid>"
  pool: "team2-k8s-pvc-rbd"           # 5.1에서 생성한 K8s PVC용 pool
  imageFeatures: "layering"
  reclaimPolicy: Delete
  isDefaultClass: true                # 기본 StorageClass로 지정
  # ↓ Secret 이름을 기본값(csi-rbd-secret)에서 바꿨으므로 참조 4개 모두 명시 필수
  # (provisioner/controllerExpand/controllerPublish/nodeStage 4가지)
  provisionerSecret: team2-rbd-csi-secret
  controllerExpandSecret: team2-rbd-csi-secret
  controllerPublishSecret: team2-rbd-csi-secret
  nodeStageSecret: team2-rbd-csi-secret
secret:
  create: true
  name: team2-rbd-csi-secret          # team2 RBD CSI 자격증명 Secret
  userID: team2-k8s-csi               # 5.1에서 생성한 Ceph user (client. 접두사 제외)
  userKey: "<5.1의 keyring 값>"
EOF

[bastion]$ helm upgrade --install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
            -n ceph-csi-rbd --create-namespace \
            -f /tmp/ceph-csi-rbd-values.yaml
# 'upgrade --install' = 처음이면 install, 이미 있으면 values만 갱신
# "cannot re-use a name" 에러 방지
```

> **values 변경 후 재적용 시:** 위 `helm upgrade --install`로 바로 됨.
> **완전히 새로 깔고 싶을 때:** `helm uninstall ceph-csi-rbd -n ceph-csi-rbd` 후 위 명령 재실행.

### 5.3 검증 ([bastion] 에서)

```bash
# CSI 드라이버 Pod 정상 기동 확인
[bastion]$ kubectl -n ceph-csi-rbd get pods
# csi-rbdplugin-* (각 노드)         Running
# csi-rbdplugin-provisioner-*       Running

# StorageClass 확인
[bastion]$ kubectl get storageclass
# NAME                         PROVISIONER        ...
# team2-rbd-block (default)    rbd.csi.ceph.com   ...

# 테스트 PVC 생성
[bastion]$ cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: team2-rbd-test-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: team2-rbd-block
  resources:
    requests:
      storage: 1Gi
EOF

[bastion]$ kubectl get pvc team2-rbd-test-pvc
# STATUS: Bound  ← OK

# Ceph 쪽에서도 이미지 실제로 생겼는지 확인 (선택)
[ceph-mon]# rbd ls -p team2-k8s-pvc-rbd
# csi-vol-xxxxxxxx... ← PVC가 만든 RBD 이미지

# 정리
[bastion]$ kubectl delete pvc team2-rbd-test-pvc
```

---

## Phase 6: ArgoCD + Harbor + 핵심 워크로드 (Day 5)

> 실행 위치: **모두 [bastion]**

### 6.1 ArgoCD

```bash
[bastion]$ kubectl create namespace argocd

[bastion]$ helm repo add argo https://argoproj.github.io/argo-helm
[bastion]$ helm install argocd argo/argo-cd \
            -n argocd \
            --set server.service.type=LoadBalancer

# 초기 비밀번호
[bastion]$ kubectl -n argocd get secret argocd-initial-admin-secret \
            -o jsonpath="{.data.password}" | base64 -d ; echo

# 외부 IP
[bastion]$ kubectl -n argocd get svc argocd-server
# EXTERNAL-IP: 172.16.22.50 (MetalLB)
```

[노트북] 브라우저에서 `https://172.16.22.50` → admin / 위 비밀번호.

### 6.2 컨테이너 레지스트리 — GHCR (GitHub Container Registry)

> **Harbor 안 씀.** GitHub Actions 기술스택과 가장 자연스럽게 연동되고, 추가 인프라 부담 없음.

#### 왜 GHCR?

| 항목 | Harbor (자체 호스팅) | **GHCR (채택)** |
|---|---|---|
| 셋업 부담 | Pod 10+개, Ceph 100Gi | 없음 (외부 서비스) |
| 비용 | 워커 메모리 ~2GB + 디스크 100GB | 무료 (Private도 무료) |
| GitHub Actions 연동 | 토큰 별도 설정 | **GITHUB_TOKEN 자동** |
| K8s에서 pull | imagePullSecret 필요 | imagePullSecret 필요 (둘 다 동일) |
| 발표 임팩트 | 사설 레지스트리 운영 | GitHub-native CI/CD |

#### 흐름

```
[개발자] git push → GitHub Actions가 빌드 → ghcr.io에 push
                                                  │
                                                  ▼
                                          ArgoCD가 매니페스트 sync
                                                  │
                                                  ▼
                                          K8s가 ghcr.io에서 pull
```

#### 1) GitHub Actions 워크플로 (`.github/workflows/build.yml` 예시)

```yaml
name: Build and Push
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write     # GHCR push 권한

    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}   # 자동 발급

      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: |
            ghcr.io/${{ github.repository_owner }}/kosa-tickets-app:${{ github.sha }}
            ghcr.io/${{ github.repository_owner }}/kosa-tickets-app:latest
```

#### 2) K8s에 imagePullSecret 생성 (Private 이미지의 경우만)

이미지가 **Public** 이면 secret 불필요. **Private** 이면:

```bash
# GitHub Personal Access Token 발급 (Read packages 권한)
# https://github.com/settings/tokens/new?scopes=read:packages
[bastion]$ GHCR_TOKEN=<발급받은_PAT>
[bastion]$ GHCR_USER=<github_username>

[bastion]$ kubectl create secret docker-registry ghcr-pull-secret \
            --docker-server=ghcr.io \
            --docker-username=$GHCR_USER \
            --docker-password=$GHCR_TOKEN \
            -n kosa-tickets
```

> 💡 학습 환경에선 처음엔 **Public 이미지로 만들고** secret 단계 건너뛰는 게 단순. 운영 학습용으로 나중에 Private + secret 흐름 추가.

#### 3) K8s Deployment 매니페스트

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kosa-tickets-app
  namespace: kosa-tickets
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: app
        image: ghcr.io/<github-org>/kosa-tickets-app:latest
      # Private 이미지일 때만:
      # imagePullSecrets:
      # - name: ghcr-pull-secret
```

#### 4) 검증

```bash
# Pod이 정상 pull 됐는지
[bastion]$ kubectl get pods -n kosa-tickets
# Running 이면 OK
# ErrImagePull / ImagePullBackOff → secret 또는 이미지 권한 문제
```

### 6.3 Percona PXC + ProxySQL ⭐

> Phase 4 Step 5 (40-k8s-addons)에서 Operator + CR이 자동 설치되지만,
> **실제 운영에선 storageClassName, WATCH_NAMESPACE, 비밀번호 조정**이 필요.

#### 6.3.1 상태 확인

```bash
[bastion]$ kubectl get pxc -n pii-protected
# NAME       ENDPOINT                          STATUS   PXC   PROXYSQL   AGE
# kosa-pxc   kosa-pxc-proxysql.pii-protected   ready    3     2          12m

[bastion]$ kubectl get pods -n pii-protected
# kosa-pxc-pxc-0..2, kosa-pxc-proxysql-0..1 모두 Running

[bastion]$ kubectl get pvc -n pii-protected
# STORAGECLASS: team2-rbd-block (default), STATUS: Bound
```

#### 6.3.2 ⚠️ 흔한 함정 5가지 (이번 운영에서 실제 발견)

##### 함정 1. WATCH_NAMESPACE — Operator가 PXC CR을 못 봄

**증상:** PXC CR 만들어도 Pod 생성 안 됨, Events 비어있음, Operator 재시작 반복

**원인:** Operator가 자기 namespace(`pxc-operator`)만 감시하도록 설정. PXC CR은 `pii-protected`에 있음.

**해결 (옵션 B 권장 — namespace 분리 유지):**

```bash
# 1) WATCH_NAMESPACE를 multi-namespace로 변경
[bastion]$ kubectl edit deployment -n pxc-operator percona-xtradb-cluster-operator
# env의 WATCH_NAMESPACE를 valueFrom → value: "pxc-operator,pii-protected" 로

# 2) Role 복제 (pxc-operator → pii-protected)
[bastion]$ kubectl get role -n pxc-operator -o yaml | \
              sed "s/namespace: pxc-operator/namespace: pii-protected/g" | \
              kubectl apply -f -

# 3) RoleBinding으로 operator SA에 권한 부여
[bastion]$ kubectl create rolebinding pxc-operator-binding -n pii-protected \
              --serviceaccount=pxc-operator:percona-xtradb-cluster-operator \
              --role=percona-xtradb-cluster-operator
```

> ⚠️ `WATCH_NAMESPACE=""` (모든 namespace)로 하면 cluster-scope Role 필요. 옛 namespace-scoped Role만 있으면 RBAC forbidden 에러로 CrashLoopBackOff.

##### 함정 2. storageClassName — PXC CR이 옛 SC 이름 참조

**증상:** PVC `Pending`, Events에 `storageclass "ceph-rbd" not found`

**해결:** PXC CR의 `storageClassName`은 **immutable** → 재생성 필요

```bash
[bastion]$ kubectl get pxc kosa-pxc -n pii-protected -o yaml > /tmp/pxc.yaml

# vi로 다음 정리:
# - metadata: resourceVersion, uid, generation, creationTimestamp, managedFields 삭제
# - status: 통째로 삭제
# - storageClassName: ceph-rbd → team2-rbd-block (2군데: pxc, proxysql)

[bastion]$ kubectl delete pxc kosa-pxc -n pii-protected
[bastion]$ sleep 5
[bastion]$ kubectl apply -f /tmp/pxc.yaml
```

##### 함정 3. Stale STS + PVC 잔재

**증상:** PXC CR 재생성해도 PVC가 여전히 옛 SC 참조

**원인:** 옛 StatefulSet의 `volumeClaimTemplate`가 옛 SC로 PVC를 만들고 있음

**해결:**
```bash
[bastion]$ kubectl delete sts -n pii-protected --all --force --grace-period=0
[bastion]$ kubectl delete pvc -n pii-protected --all
# finalizer로 안 빠지면
[bastion]$ for pvc in $(kubectl get pvc -n pii-protected -o name); do
              kubectl patch $pvc -n pii-protected --type='merge' -p '{"metadata":{"finalizers":null}}'
           done
```

##### 함정 4. Released PV 잔재 (옛 fsid 등 placeholder)

**증상:** `kubectl get pv`에 Released 상태 PV가 finalizer로 안 빠짐

**해결:**
```bash
[bastion]$ kubectl patch pv <PV-이름> --type='merge' -p '{"metadata":{"finalizers":null}}'
```

> 발견 시 Ceph 측에도 잔재 RBD 이미지 있을 수 있음 — 시간 날 때:
> ```
> [ceph-mon]# rbd ls -p team2-k8s-pvc-rbd
> [ceph-mon]# rbd rm team2-k8s-pvc-rbd/csi-vol-<orphan>
> ```

##### 함정 5. Galera join 시간

PXC는 단순 MySQL이 아니라 **동기 복제 클러스터(Galera)**. 첫 부트스트랩 순서:

```
pxc-0  (5~10분, MySQL 초기화 + 클러스터 생성)
  ↓ Running 1/1
pxc-1  (3~5분, SST로 pxc-0에서 데이터 복사)
  ↓ Running 1/1
pxc-2  (3~5분, SST)
  ↓ Running 1/1
```

`STATUS: Running` 인데 `READY: 0/1`로 잠시 보이는 건 **Galera join 진행 중**으로 정상. 끝까지 기다리면 됨.

#### 6.3.3 root 비밀번호 변경

PXC Operator는 모든 비밀번호를 Secret으로 관리. **mysql에서 직접 `ALTER USER`해도 Operator가 곧 Secret 값으로 되돌림** → 무조건 Secret 수정.

```bash
[bastion]$ NEW_PW="kosa1004"   # 운영에선 강한 비밀번호 사용
[bastion]$ PW_B64=$(echo -n "$NEW_PW" | base64 -w0)
[bastion]$ kubectl patch secret kosa-pxc-secrets -n pii-protected --type='json' \
              -p="[{\"op\":\"replace\",\"path\":\"/data/root\",\"value\":\"$PW_B64\"}]"

# Operator가 1~2분 내 자동 반영
[bastion]$ sleep 90
[bastion]$ kubectl exec kosa-pxc-pxc-0 -n pii-protected -- \
              mysql -uroot -p"$NEW_PW" -e "SELECT 'OK' AS test;"
```

> 💡 다른 시스템 user(`monitor`, `xtrabackup`, `proxyadmin` 등) 비밀번호도 같은 방식. `/data/root` 자리만 바꾸면 됨.

#### 6.3.4 앱용 DB/User 생성 (앱 워크로드 준비)

PXC Operator는 **시스템 user만** 관리. 앱이 쓸 user는 직접 만듦. 이건 Operator가 안 건드림.

```bash
[bastion]$ kubectl exec -it kosa-pxc-pxc-0 -n pii-protected -- mysql -uroot -pkosa1004
```

mysql 안에서:
```sql
CREATE DATABASE kosa_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'kosa_app'@'%' IDENTIFIED BY 'kosa1004';
GRANT ALL PRIVILEGES ON kosa_db.* TO 'kosa_app'@'%';
FLUSH PRIVILEGES;
EXIT;
```

K8s Secret으로 등록 (앱 Deployment가 env로 참조):

```bash
[bastion]$ kubectl create namespace kosa-app
[bastion]$ kubectl create secret generic kosa-db-credentials -n kosa-app \
              --from-literal=DB_HOST=kosa-pxc-proxysql.pii-protected.svc.cluster.local \
              --from-literal=DB_PORT=3306 \
              --from-literal=DB_NAME=kosa_db \
              --from-literal=DB_USER=kosa_app \
              --from-literal=DB_PASSWORD=kosa1004
```

#### 6.3.5 접속 + 클러스터 상태 검증

```bash
# 앱 user로 접속 (PXC 노드 직접)
[bastion]$ kubectl exec kosa-pxc-pxc-0 -n pii-protected -- \
              mysql -h 127.0.0.1 -u kosa_app -pkosa1004 kosa_db \
              -e "SELECT 'login OK' AS test;"

# Galera 클러스터 size (3이어야 정상)
[bastion]$ kubectl exec kosa-pxc-pxc-0 -n pii-protected -- \
              mysql -uroot -pkosa1004 -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
# wsrep_cluster_size    3   ← 3노드 동기 복제 정상

# Ceph 측 RBD 이미지 확인 (선택)
[ceph-mon]# rbd ls -p team2-k8s-pvc-rbd
# csi-vol-... 5개 (pxc 3 + proxysql 2)
```

> ⚠️ ProxySQL을 통한 root 접속은 보안 기본 설정으로 막혀있음. PXC 노드 직접 접속만 됨. 앱 user(`kosa_app`)는 ProxySQL/PXC 둘 다 가능.

#### 6.3.6 ProxySQL 라우팅 룰 (옵션, R/W 분기용)

[DB_Schema.md](DB_Schema.md) Section 8 참고:

```bash
[bastion]$ kubectl exec -it -n pii-protected kosa-pxc-proxysql-0 -- \
            mysql -h127.0.0.1 -P6032 -uproxyadmin -p

mysql> INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply)
       VALUES (3, 1, '^SELECT.*FROM events ', 30, 1);
mysql> LOAD MYSQL QUERY RULES TO RUNTIME;
mysql> SAVE MYSQL QUERY RULES TO DISK;
```

### 6.4 Redis Sentinel

```bash
[bastion]$ helm install redis bitnami/redis \
            -n redis --create-namespace \
            --set architecture=replication \
            --set sentinel.enabled=true \
            --set master.persistence.storageClass=team2-rbd-block \
            --set replica.persistence.storageClass=team2-rbd-block
```

> StorageClass는 Phase 5에서 만든 `team2-rbd-block` 사용.

### 6.5 Prometheus + Grafana

```bash
[bastion]$ helm install kube-prom prometheus-community/kube-prometheus-stack \
            -n monitoring --create-namespace \
            --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=team2-rbd-block \
            --set grafana.adminPassword=admin \
            --set grafana.service.type=LoadBalancer
```

Grafana 접속:
```bash
[bastion]$ kubectl get svc -n monitoring kube-prom-grafana
# EXTERNAL-IP: 172.16.23.1XX (MetalLB 풀: 172.16.23.100~150)
```

[노트북] 브라우저에서 `http://<EXTERNAL-IP>` → admin / admin.

> MetalLB 풀은 K8s 노드와 같은 VLAN 30(`172.16.23.0/24`)에서 할당. VLAN 다르면 ARP 응답 못 해서 노트북에서 접속 불가.

---

## 최종 검증

### 클러스터 상태 ([bastion]에서)
```bash
[bastion]$ kubectl get nodes
# 6개 노드, 모두 Ready

[bastion]$ kubectl get pods -A | grep -v Running | grep -v Completed
# 빈 출력
```

### 핵심 컴포넌트 ([bastion]에서)
```bash
[bastion]$ kubectl get sc                         # ceph-rbd (default)
[bastion]$ kubectl get pods -n calico-system
[bastion]$ kubectl get pods -n metallb-system
[bastion]$ kubectl top nodes
[bastion]$ kubectl get pxc -A                     # Percona
[bastion]$ kubectl get pods -n argocd
[bastion]$ kubectl get pods -n harbor
[bastion]$ kubectl get pods -n redis
[bastion]$ kubectl get pods -n monitoring
```

### LoadBalancer IP 한눈에
```bash
[bastion]$ kubectl get svc -A | grep LoadBalancer
# argocd-server, harbor, grafana 등 172.16.22.X
```

---

## 트러블슈팅

### Terraform 단계 ([노트북])

| 증상 | 해결 |
|---|---|
| `Error: 401 Unauthorized` | API 토큰 + Privilege Separation 해제 확인 |
| `template 9000 not found` | Phase 2 다시 실행 |
| VM 만들어졌는데 모두 kosa1에 — | 사실 clone 진행 중 일시 현상. 1~2분 후 target 노드로 migrate됨. plan의 `node_name` 확인 |
| `vm with id X already exists` | `ssh kosa1 'qm destroy X --purge 1'` 후 재시도 |
| IP 안 잡힘 | `[kosa1]# qm config <vmid> \| grep ipconfig` 확인 |

### Ansible 단계 ([bastion])

| 증상 | 해결 |
|---|---|
| `Permission denied (publickey)` | `~/.ssh/kosa_iac` 권한 600. inventory의 `ansible_ssh_private_key_file` 경로 확인 |
| `kubeadm init` swap 에러 | 00-bootstrap 재실행 → `ansible k8s_cluster -m shell -a 'swapon -s'` 빈 출력인지 |
| Worker join 토큰 만료 | `[k8s-cp1]$ sudo kubeadm token create --print-join-command` 받아서 워커에 수동 적용 |
| Calico 노드 NotReady 지속 | `kubectl get pods -n calico-system` + `kubectl logs -n calico-system <pod>` |
| `ansible all -m ping` 일부 실패 | inventory의 `ansible_host` IP가 실제 VM IP와 같은지 확인 |

### K8s 운영 ([bastion])

| 증상 | 해결 |
|---|---|
| `kubectl top nodes` "Metrics not available" | `kubectl logs -n kube-system -l k8s-app=metrics-server` |
| LoadBalancer Pending | MetalLB `IPAddressPool` + `L2Advertisement` 적용 확인 |
| PVC Pending | `kubectl logs -n ceph-csi-rbd -l app=csi-rbdplugin-provisioner` |
| Pod ImagePullBackOff | Harbor 인증 secret 확인 — `kubectl create secret docker-registry ...` |

---

## 다음 단계

온프레가 안정되면 → **AWS 측 구축** (`terraform/aws/README.md`):
1. Phase 1 (Day 8): VPC + NLB + EC2 HAProxy
2. Phase 2 (Day 9-10): Site-to-Site VPN
3. Phase 3 (Day 10): RDS Read Replica
4. Phase 4 (Day 10-11): EKS + Karpenter
5. Phase 5 (Day 11): WAF + Lambda burst

---

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-05-12 | 초안 |
| 2026-05-12 | "실행 위치" 라벨 도입, Phase 4 상세화, Ubuntu Noble 24.04 반영, Worker 배치 옵션 C 반영 |
