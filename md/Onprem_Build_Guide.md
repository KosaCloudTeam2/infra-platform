# 온프레미스 구축 가이드 (Day 1~5)

> kosa-day 프로젝트의 온프레미스 K8s 클러스터를 0부터 구축하는 단계별 가이드.
> **Terraform + Ansible로 자동화** + **각 단계마다 검증 명령 포함**.
>
> 관련 문서: [Architecture_Design.md](Architecture_Design.md) | [IaC_Setup_Guide.md](IaC_Setup_Guide.md)

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
✓ Percona PXC × 3 + ProxySQL × 2 배포
✓ Redis Sentinel
✓ Prometheus + Grafana 기본 대시보드
```

K8s 노드 6대 = CP 3 + Worker 3 (Bastion은 K8s 멤버 아님, 도구 호스트)

---

## 사전 준비 체크리스트

### 하드웨어 / 네트워크
- [ ] Proxmox 4대 (kosa1~kosa4) 정상 작동
- [ ] pfSense HA 완료 ✓
- [ ] 관리형 스위치 VLAN 10/20/30/40/99 설정 ✓
- [ ] Ceph 클러스터 6대 정상 (`ceph status` HEALTH_OK)
- [ ] 노트북 또는 Bastion에서 Proxmox 접근 가능

### 도구
- [ ] **Terraform 1.5+**: `terraform version`
- [ ] **Ansible 2.14+**: `ansible --version`
- [ ] **kubectl**: 추후 Bastion에 설치
- [ ] **SSH 키**: `~/.ssh/kosa_iac` (없으면 아래 생성)
- [ ] **Proxmox API 토큰** (아래 발급)

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
# 로컬 노트북에서
ssh-keygen -t ed25519 -C "kosa-iac" -f ~/.ssh/kosa_iac

# 공개키 확인 (terraform.tfvars에 입력할 값)
cat ~/.ssh/kosa_iac.pub
```

---

## Phase 1: Proxmox 네트워크 (완료)

> pfSense HA 완료 시점에 이미 끝난 단계.
> `pfSense_HA_Setup_Guide.md` 참고.

검증:
```bash
# 노트북에서
ping 172.16.21.1   # VLAN 10 게이트웨이 (CARP VIP)
ping 172.16.22.1   # VLAN 20
ping 172.16.23.1   # VLAN 30
ping 172.16.24.1   # VLAN 40
```

모두 응답하면 OK.

---

## Phase 2: Cloud-init 템플릿 (Day 1)

> **한 번만** 만들면 됨. Terraform이 이걸 clone해서 7개 VM 생성.

### 2.1 Ubuntu Cloud Image 다운로드

```bash
# kosa1 또는 임의 Proxmox 호스트에 SSH
ssh root@192.168.21.2

cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

ls -lh jammy-server-cloudimg-amd64.img
# 약 700MB
```

> ⚠️ **일반 ISO와 다름**: Cloud Image는 cloud-init 활성화된 이미 설치된 이미지. 일반 ISO는 부팅 후 설치 마법사가 떠서 자동화 불가.

### 2.2 템플릿 VM 생성 (VMID 9000)

```bash
# 1) 빈 VM 생성 (디스크 없음)
qm create 9000 \
  --name ubuntu-2204-template \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr0,firewall=0 \
  --ostype l26 \
  --agent enabled=1 \
  --serial0 socket \
  --vga serial0 \
  --scsihw virtio-scsi-pci

# 2) cloud image를 디스크로 import
qm importdisk 9000 jammy-server-cloudimg-amd64.img local-lvm

# 3) 디스크를 SCSI로 연결
qm set 9000 --scsi0 local-lvm:vm-9000-disk-0,discard=on,ssd=1

# 4) cloud-init 드라이브 추가 (cloud-init 데이터 전달용 가상 CD)
qm set 9000 --ide2 local-lvm:cloudinit

# 5) 부팅 디스크 지정
qm set 9000 --boot c --bootdisk scsi0

# 6) 템플릿으로 전환 (이제 직접 시작 불가, clone만 가능)
qm template 9000
```

### 2.3 검증

```bash
# 템플릿 확인 (Status에 'template'이라고 나옴)
qm status 9000
```

### 2.4 (선택) 템플릿 직접 테스트

```bash
# VMID 999로 임시 clone
qm clone 9000 999 --name test-clone --full
qm set 999 --ciuser ubuntu \
           --sshkey ~/.ssh/kosa_iac.pub \
           --ipconfig0 ip=172.16.23.99/24,gw=172.16.23.1
qm start 999

# 1분 후 SSH 시도
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.99

# 잘 되면 삭제
qm stop 999
qm destroy 999
```

---

## Phase 3: Terraform으로 VM 생성 (Day 2)

### 3.1 변수 파일 작성

```bash
# 로컬 노트북에서
cd /Users/sangjjang/kosa_infra_project/terraform/onprem
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

`terraform.tfvars`:
```hcl
proxmox_endpoint  = "https://192.168.21.2:8006/"
proxmox_api_token = "root@pam!terraform=<2.0절에서_받은_Secret>"
ssh_public_key    = "ssh-ed25519 AAAA... kosa-iac"
```

### 3.2 Terraform 초기화

```bash
terraform init
```

기대 출력:
```
Initializing the backend...
Initializing provider plugins...
- Installing bpg/proxmox v0.66.x...
Terraform has been successfully initialized!
```

### 3.3 변경 미리보기

```bash
terraform plan
```

기대 출력 마지막:
```
Plan: 7 to add, 0 to change, 0 to destroy.
```

7대 VM 생성 계획 확인.

### 3.4 VM 생성

```bash
terraform apply
# "yes" 입력
```

소요 시간: **약 10분**. 7대 동시 생성 (병렬).

### 3.5 검증

```bash
# Terraform output 확인
terraform output all_vm_summary
```

기대 출력:
```
[
  "k8s-cp1 (172.16.23.10) on kosa1",
  "k8s-cp2 (172.16.23.11) on kosa2",
  "k8s-cp3 (172.16.23.12) on kosa3",
  "k8s-w1 (172.16.23.20) on kosa3",
  "k8s-w2 (172.16.23.21) on kosa4",
  "k8s-w3 (172.16.23.22) on kosa4",
  "bastion (172.16.24.10) on kosa4",
]
```

### 3.6 Bastion 접속 + 도구 설치

```bash
# 노트북에서
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.24.10

# Bastion에서
sudo apt-get update
sudo apt-get install -y git curl wget vim jq ansible python3-pip
```

### 3.7 모든 VM SSH 접근 확인

Bastion에서:
```bash
for ip in 10 11 12 20 21 22; do
  echo "=== 172.16.23.$ip ==="
  ssh -i ~/.ssh/kosa_iac -o StrictHostKeyChecking=no \
      ubuntu@172.16.23.$ip "hostname && uptime"
done
```

7대 모두 응답 OK.

### 3.8 (선택) 코드를 Git에 커밋

```bash
# 로컬 노트북에서
cd /Users/sangjjang/kosa_infra_project
git add terraform/onprem/
git commit -m "Add onprem Terraform code (CP3 + W3 + Bastion)"

# 단, terraform.tfvars는 .gitignore에 있어 안 들어감 ✓
```

---

## Phase 4: Ansible로 K8s 부트스트랩 (Day 3)

### 4.1 인벤토리 자동 생성

```bash
# 노트북 또는 Bastion에서
cd /Users/sangjjang/kosa_infra_project
./scripts/generate-inventory.sh
```

또는 수동:
```bash
cd terraform/onprem
terraform output -raw ansible_inventory > ../../ansible/inventory/hosts.yml
```

생성된 파일 확인:
```bash
cat ansible/inventory/hosts.yml
```

### 4.2 Ansible Collection 설치

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
```

### 4.3 연결 테스트

```bash
ansible all -m ping
```

기대: 모든 호스트 `pong`.

### 4.4 단계별 플레이북 실행

#### Step 1: 기본 OS 설정 (~5분)

```bash
ansible-playbook playbooks/00-bootstrap.yml
```

작업 내용:
- hostname 설정
- swap 비활성화 (K8s 필수)
- timezone Asia/Seoul
- NTP (chrony) 동기화
- 기본 패키지 설치 (curl, vim, jq 등)

검증:
```bash
# Bastion에서
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.23.10 'swapon -s; date'
# swap 비어있고 timezone Asia/Seoul OK
```

#### Step 2: containerd + 커널 설정 (~5분)

```bash
ansible-playbook playbooks/10-k8s-prepare.yml
```

작업 내용:
- `overlay`, `br_netfilter` 커널 모듈 로드
- sysctl: `ip_forward=1`, `bridge-nf-call-iptables=1`
- **containerd 설치** (Docker 아님!)
- containerd가 systemd cgroup 사용하도록 설정

검증:
```bash
ssh ubuntu@172.16.23.10 'sudo systemctl status containerd | head -3'
# active (running)

ssh ubuntu@172.16.23.10 'lsmod | grep br_netfilter'
# br_netfilter 모듈 보임
```

#### Step 3: kubeadm/kubelet/kubectl 설치 (~3분)

```bash
ansible-playbook playbooks/20-k8s-install.yml
```

작업 내용:
- Kubernetes apt repo 추가 (`pkgs.k8s.io`)
- kubeadm, kubelet, kubectl 설치
- `apt-mark hold` (자동 업그레이드 방지)

검증:
```bash
ssh ubuntu@172.16.23.10 'kubeadm version'
# GitVersion:"v1.30.x"
```

#### Step 4: 클러스터 초기화 + Join (~10분)

```bash
ansible-playbook playbooks/30-k8s-init.yml
```

작업 내용:
- k8s-cp1: `kubeadm init` (첫 CP)
- k8s-cp2, cp3: `kubeadm join --control-plane`
- k8s-w1, w2, w3: `kubeadm join` (워커)
- ubuntu 사용자에 kubeconfig 복사
- Bastion에 admin.conf 가져오기

검증:
```bash
# Bastion에서
kubectl get nodes
```

기대 출력:
```
NAME       STATUS     ROLES           AGE     VERSION
k8s-cp1    NotReady   control-plane   5m      v1.30.x
k8s-cp2    NotReady   control-plane   3m      v1.30.x
k8s-cp3    NotReady   control-plane   2m      v1.30.x
k8s-w1     NotReady   <none>          1m      v1.30.x
k8s-w2     NotReady   <none>          1m      v1.30.x
k8s-w3     NotReady   <none>          1m      v1.30.x
```

**NotReady 정상**. CNI 없어서. 다음 단계에서 해결.

#### Step 5: Calico + MetalLB + Metrics Server (~10분)

```bash
ansible-playbook playbooks/40-k8s-addons.yml
```

작업 내용:
- Tigera Operator → Calico 설치
- Metrics Server 설치 (`--kubelet-insecure-tls`)
- MetalLB 설치 + IP 풀 (172.16.22.50-100)

검증:
```bash
kubectl get nodes
# 모두 Ready 상태로 변함!

kubectl get pods -A
# calico-system, metallb-system, kube-system 모두 Running

kubectl top nodes
# CPU/Memory 사용량 표시 (Metrics Server 작동)
```

### 4.5 한 번에 실행하기 (학습 후 권장)

```bash
ansible-playbook playbooks/site.yml
```

총 소요: **약 30~40분**.

---

## Phase 5: Ceph CSI 연결 (Day 4)

K8s에서 Ceph RBD를 동적 PV로 쓰기 위한 설정.

### 5.1 Ceph 클러스터 정보 수집

Ceph 모니터에서:
```bash
ssh ceph-mon-1  # 예시

# 클러스터 ID
ceph fsid

# 모니터 IP들
ceph mon dump | grep -E "mon\.[0-9]"

# admin keyring
ceph auth get-key client.admin
```

### 5.2 K8s Pool 생성

```bash
# Ceph 측에서
ceph osd pool create kosa-rbd 64 64 replicated
rbd pool init kosa-rbd

# K8s 전용 user 생성
ceph auth get-or-create client.k8s \
  mon 'profile rbd' \
  osd 'profile rbd pool=kosa-rbd' \
  -o ceph.client.k8s.keyring

cat ceph.client.k8s.keyring  # K8s에 등록할 키
```

### 5.3 Ceph CSI 설치 (Helm)

Bastion에서:
```bash
helm repo add ceph-csi https://ceph.github.io/csi-charts
helm repo update

# values.yaml 작성
cat > ceph-csi-rbd-values.yaml <<EOF
csiConfig:
  - clusterID: "<ceph_fsid>"
    monitors:
      - "10.10.10.12:6789"
      - "10.10.10.13:6789"
      - "10.10.10.14:6789"
storageClass:
  create: true
  name: ceph-rbd
  clusterID: "<ceph_fsid>"
  pool: "kosa-rbd"
  imageFeatures: "layering"
  reclaimPolicy: Delete
secret:
  create: true
  name: csi-rbd-secret
  userID: k8s
  userKey: "<위에서_받은_키>"
EOF

helm install ceph-csi-rbd ceph-csi/ceph-csi-rbd \
  -n ceph-csi-rbd --create-namespace \
  -f ceph-csi-rbd-values.yaml
```

### 5.4 검증

```bash
# StorageClass 확인
kubectl get storageclass
# ceph-rbd (default)

# 테스트 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ceph-rbd
  resources:
    requests:
      storage: 1Gi
EOF

# PVC가 Bound 상태인지
kubectl get pvc test-pvc
# STATUS: Bound

# 정리
kubectl delete pvc test-pvc
```

---

## Phase 6: ArgoCD + Harbor + 핵심 워크로드 (Day 5)

### 6.1 ArgoCD 설치

```bash
# Bastion에서
kubectl create namespace argocd

helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd \
  -n argocd \
  --set server.service.type=LoadBalancer
```

```bash
# 초기 비밀번호
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# LoadBalancer IP
kubectl -n argocd get svc argocd-server
# EXTERNAL-IP: 172.16.22.50 (MetalLB)
```

브라우저에서 `https://172.16.22.50` → admin / 위 비밀번호.

### 6.2 Harbor 설치

```bash
kubectl create namespace harbor

helm repo add harbor https://helm.goharbor.io
helm install harbor harbor/harbor \
  -n harbor \
  --set expose.type=loadBalancer \
  --set persistence.persistentVolumeClaim.registry.storageClass=ceph-rbd \
  --set persistence.persistentVolumeClaim.registry.size=100Gi \
  --set persistence.persistentVolumeClaim.database.storageClass=ceph-rbd
```

### 6.3 Percona PXC × 3 배포 (manifest 또는 Operator)

권장: Percona Operator
```bash
kubectl apply -f https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/v1.14.0/deploy/bundle.yaml

# Custom Resource로 클러스터 생성
cat <<EOF | kubectl apply -f -
apiVersion: pxc.percona.com/v1
kind: PerconaXtraDBCluster
metadata:
  name: kosa-pxc
spec:
  crVersion: 1.14.0
  pxc:
    size: 3
    image: percona/percona-xtradb-cluster:8.0
    volumeSpec:
      persistentVolumeClaim:
        storageClassName: ceph-rbd
        resources:
          requests:
            storage: 50Gi
  proxysql:
    size: 2
    image: percona/proxysql2:2.5
EOF
```

### 6.4 Redis Sentinel (Bitnami chart)

```bash
helm install redis bitnami/redis \
  -n redis --create-namespace \
  --set sentinel.enabled=true \
  --set master.persistence.storageClass=ceph-rbd
```

### 6.5 Prometheus + Grafana

```bash
helm install kube-prom prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=ceph-rbd \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=LoadBalancer
```

---

## 최종 검증

### 클러스터 상태
```bash
kubectl get nodes
# 6개 노드, 모두 Ready

kubectl get pods -A | grep -v Running | grep -v Completed
# 빈 출력 (모두 Running 또는 Completed)
```

### 핵심 컴포넌트
```bash
# Storage
kubectl get sc
# ceph-rbd (default)

# Calico
kubectl get pods -n calico-system

# MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system

# Metrics
kubectl top nodes

# 워크로드
kubectl get pxc -A           # Percona
kubectl get pods -n argocd   # ArgoCD
kubectl get pods -n harbor   # Harbor
kubectl get pods -n redis
kubectl get pods -n monitoring
```

### LoadBalancer IP 확인
```bash
kubectl get svc -A | grep LoadBalancer
# argocd-server, harbor, grafana 등에 172.16.22.X IP 할당됨
```

---

## 트러블슈팅

### Terraform 단계

| 증상 | 해결 |
|---|---|
| `Error: 401 Unauthorized` | API 토큰 확인, Privilege Separation 해제 확인 |
| `template 9000 not found` | Phase 2 다시 (Cloud-init 템플릿 생성) |
| VM 만들어졌는데 IP 안 잡힘 | Proxmox 콘솔로 확인: `qm config <vmid> \| grep ipconfig` |
| `vm with id X already exists` | `qm destroy <vmid>` 후 재시도 |

### Ansible 단계

| 증상 | 해결 |
|---|---|
| `Permission denied (publickey)` | SSH 키 경로 확인 (`ansible.cfg`의 `private_key_file`) |
| `kubeadm init` swap 에러 | 00-bootstrap 다시 실행 → `swapon -s` 비어있는지 |
| `kubeadm init` 통신 에러 | 10-k8s-prepare 다시 → `lsmod \| grep br_netfilter` |
| Worker join 실패 (token 만료) | CP에서 `kubeadm token create --print-join-command` 후 수동 join |
| Calico 노드 NotReady 오래 지속 | `kubectl get pods -n calico-system` 보고 Operator 로그 확인 |

### K8s 운영

| 증상 | 해결 |
|---|---|
| `kubectl top nodes` "Metrics not available" | Metrics Server 파드 로그: `kubectl logs -n kube-system -l k8s-app=metrics-server` |
| LoadBalancer 서비스가 Pending | MetalLB IP 풀 확인, IPAddressPool 적용 확인 |
| PVC가 Pending | Ceph CSI 로그: `kubectl logs -n ceph-csi-rbd -l app=csi-rbdplugin-provisioner` |
| Pod이 ImagePullBackOff | Harbor 인증 확인 (`kubectl create secret docker-registry`) |

---

## 다음 단계

온프레가 안정되면 → **AWS 측 구축**:
1. `terraform/aws/` 작성 (VPC, EKS, RDS, Route 53)
2. AWS EKS 클러스터 만들기
3. ArgoCD에 EKS 클러스터 등록 (멀티 클러스터)
4. EventBridge + Lambda burst 자동화
5. Percona binlog → AWS RDS Replica 복제 설정

상세 가이드는 별도 문서로 작성 예정.

---

## 변경 이력

| 일자 | 내용 |
|---|---|
| 2026-05-12 | 초안 작성 |
