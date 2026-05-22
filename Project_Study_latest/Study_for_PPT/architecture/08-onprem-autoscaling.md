# 08. 온프레 워커노드 자동 프로비저닝 (Terraform + Ansible)

> ⭐ **한 줄 요약**: AWS는 Karpenter로 자동 spot 노드 생성하는데 **온프레는 자동화 없음** = 워커 자원 부족하면 Pod Pending 상태로 멈춤. **Terraform (Proxmox provider) + Ansible로 자동 VM 프로비저닝 + kubeadm join** 구축 권장.

---

## 🚨 문제 정의

### 현재 상태 (자동화 없음)
```
[Pod 생성 요청]
   │
   ▼
[K8s scheduler가 적합한 노드 찾기]
   │
   ▼
[모든 워커 자원 부족] ← 여기서 멈춤
   │
   ▼
[Pod Pending 상태로 무한 대기]
   │
   ▼
[사람이 Proxmox UI 접속 → VM 수동 생성 → cloud-init → kubeadm join]
   ↑
   ★★★★★ 사람 개입 필요. RTO 30분~수시간.
```

### AWS 측과 대조 (불공정)
```
[AWS EKS]
   ↓
[Pod Pending]
   ↓
[Karpenter 감지 (40초 내)]
   ↓
[EC2 Spot 자동 생성 + EKS join]
   ↓
[Pod schedule]
   ↑
   ★ 사람 개입 0
```

**모순**: AWS는 자동 scale, 온프레는 수동. 하이브리드 일관성 부족.

---

## 🎯 우리가 원하는 구조

```
[Pod Pending 감지]
   ↓ (Prometheus alert)
[AlertManager → Webhook]
   ↓
[Lambda 또는 Jenkins job]
   ↓
[Terraform run] (Proxmox provider)
   ↓
[Proxmox VM 생성 (template clone)]
   ↓
[cloud-init: hostname, SSH key, network]
   ↓
[Ansible playbook: kubeadm join + 라벨 설정]
   ↓
[K8s scheduler → Pending Pod schedule]
   ↑
   ★ 사람 개입 0
```

---

## 🔍 구현 옵션

### Option A: ⭐ Terraform + Ansible (직접 자동화)
```hcl
# terraform/onprem/worker-pool/main.tf
resource "proxmox_vm_qemu" "k8s_worker" {
  count       = var.worker_count
  name        = "k8s-w${count.index + 4}"   # w4, w5, ...
  target_node = "kosa${(count.index % 4) + 1}"   # 4개 호스트에 분산
  clone       = "ubuntu-2204-k8s-template"
  cores       = 2
  memory      = 6144
  
  network {
    bridge = "vmbr1"   # 10G NIC
    tag    = 30        # VLAN 30
  }
  
  ipconfig0 = "ip=dhcp"
}

# 생성 후 ansible로 kubeadm join
resource "null_resource" "k8s_join" {
  count = var.worker_count
  
  depends_on = [proxmox_vm_qemu.k8s_worker]
  
  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook -i ${proxmox_vm_qemu.k8s_worker[count.index].default_ipv4_address}, \
        ansible/k8s-worker-join.yml \
        -e "join_token=$(kubectl create token ...)"
    EOT
  }
}
```

**Ansible playbook**:
```yaml
# ansible/k8s-worker-join.yml
- hosts: all
  tasks:
    - name: Install kubeadm/kubelet/containerd
      apt:
        name: [kubeadm=1.30.*, kubelet=1.30.*, containerd]
    - name: kubeadm join
      command: kubeadm join 172.16.23.5:6443 --token {{ join_token }} ...
    - name: Label node
      delegate_to: bastion
      command: kubectl label node {{ inventory_hostname }} workload-type=production
```

**Trigger**:
```yaml
# Prometheus rule
- alert: WorkerNodeAtCapacity
  expr: |
    sum by (node) (
      kube_pod_container_resource_requests{resource="cpu"}
    ) / on(node) kube_node_status_allocatable{resource="cpu"} > 0.85
  for: 5m
  labels:
    severity: warning
    auto_scale: "true"
  annotations:
    summary: "Worker node {{ $labels.node }} at 85% CPU. Auto-scale trigger."

# AlertManager route
routes:
  - matchers:
    - auto_scale="true"
    receiver: terraform-webhook
```

**Lambda (또는 Jenkins job)**:
```python
def handle_alert(event):
    if event['alerts'][0]['labels']['auto_scale'] == 'true':
        # 1. Terraform apply
        subprocess.run(['terraform', 'apply', '-auto-approve', 
                       f'-var=worker_count={current_count + 1}'])
        # 2. Ansible은 Terraform null_resource에 포함
```

- ✅ **장점**: 완전 자동화, 우리가 원하는 구조
- ❌ **단점**: Terraform/Ansible 학습 + Proxmox provider 함정
- 💰 **비용**: 0 (도구 무료)
- ⏱️ **작업**: 1주 (Terraform 모듈 + Ansible playbook + 트리거 자동화)
- 🎯 **추천 시점**: Phase 7 (운영 진입)

### Option B: ⭐ Cluster API for Proxmox (CAPI)
CAPI = K8s 표준으로 cluster + node 관리. Proxmox provider 있음.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: kosa-worker-pool
spec:
  replicas: 4   # K8s가 이 수를 강제
  template:
    spec:
      infrastructureRef:
        kind: ProxmoxMachineTemplate
        name: kosa-worker-template
```

- ✅ **장점**: K8s native (kubectl scale로 노드 수 변경), declarative
- ❌ **단점**: CAPI 학습 곡선 ★★★, Proxmox provider 미성숙
- 🎯 **추천 시점**: 진짜 K8s native + CAPI 학습 의지

### Option C: 수동 + 알람만
- 현재 그대로 수동 VM 생성
- + Prometheus alert로 "노드 자원 부족 경고" 이메일
- 사람이 수시간 내 수동 대응
- ✅ **장점**: 학습 부담 0
- ❌ **단점**: 자동화 가치 X
- 🎯 **추천 시점**: 학습 환경 그대로 (현재)

### Option D: AWS Burst로 자동 우회 (현재 hybrid 활용)
- 온프레 워커 자원 부족 → 일반적인 alert → AWS burst trigger
- EKS Karpenter spot이 자동 생성 → 트래픽 일부 흡수
- 온프레 노드 추가는 사람 (천천히)
- ✅ **장점**: 이미 구축됨, 즉시 부하 해소
- ❌ **단점**: AWS 비용, 온프레 자원 그대로
- 🎯 **추천 시점**: 즉시 (이미 Phase 4 동작)

### Option E: KubeVirt (K8s 안에서 VM 관리)
- K8s 안에 VM도 띄움 → kubectl로 VM 생성/삭제
- ❌ **단점**: 우리 Proxmox와 중복, 학습 곡선
- 🎯 **추천 시점**: 진짜 K8s + VM 통합 운영

### Option F: 큰 단일 호스트 → micro VM 패턴
- 거대 호스트 1대 + Firecracker/Kata로 micro VM 자동 생성
- ❌ **단점**: 학습 환경엔 과함
- 🎯 **추천 시점**: cloud provider 자체 구축 시

---

## 📊 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 학습/데모 (현재) | C (수동) + D (burst) |
| Phase 7 운영 진입 | A (Terraform/Ansible) |
| K8s native 추구 | B (CAPI) |
| 자원 진짜 부족 | A + 노드 추가 |

---

## 💰 비용 분석

### Option A (Terraform/Ansible) 구현 비용
| 항목 | 비용 |
|---|---|
| Terraform/Ansible 라이센스 | 0 (OSS) |
| Proxmox provider 학습 | 1주 |
| Ansible playbook 작성 | 3일 |
| 트리거 자동화 (Lambda/Jenkins) | 2일 |
| **합계** | **약 2주 (개발), 0 (운영 비용)** |

### Option A vs 수동 운영 비용 비교
- 수동: VM 1대 추가 = 30분 작업 × 월 평균 5회 = 2.5h/월 × ₩50,000/h = ₩125,000/월
- 자동: 초기 2주 + 운영 0
- → **2.5개월에 ROI** (수동 자주 한다면)

---

## ⚖️ Trade-off

| 얻은 것 (Option A) | 잃은 것 |
|---|---|
| 자동 scale (사람 개입 0) | Terraform/Ansible 학습 |
| RTO 1분 (vs 수동 30분) | Proxmox provider 함정 |
| IaC = 변경 추적 (Git) | 자동 scale up은 비용 ↑ 위험 |
| AWS Karpenter와 일관성 | 자동 scale down 어려움 (워크로드 drain) |

---

## ⚠️ 자동 scale의 함정

### 함정 1: Scale up은 쉬운데 down 어려움
- Pod 분산되어 있어서 노드 비우기 (drain) 어려움
- 노드 비우기 전 모든 Pod이 다른 노드로 schedule 가능해야 함
- → Scale down은 정책적 (자정에만 등)

### 함정 2: 비용 폭발 위험
- alert false positive → 노드 추가 → 비용 ↑
- 가드: maximum nodes 제한 (예: 10대 한도)

### 함정 3: Proxmox 자원 한계
- VM 생성하려면 호스트 자원 (CPU/RAM/disk) 있어야
- 4개 Proxmox 노드 자원 다 쓰면 추가 호스트 필요

### 함정 4: K8s join token 만료
- kubeadm token default 24h 만료
- 자동 scale 시 매번 새 token 발급 필요

---

## 🚀 Phase 7 구현 단계

### Step 1: Proxmox VM template 정비 (3일)
- ubuntu-2204-k8s-template (cloud-init + kubeadm pre-installed)
- 모든 노드에서 clone 가능

### Step 2: Terraform 모듈 작성 (3일)
- `terraform/onprem/worker-pool/`
- Proxmox provider 설정
- variable: worker_count
- output: VM IP

### Step 3: Ansible playbook (2일)
- `ansible/k8s-worker-join.yml`
- kubeadm join 자동화
- 라벨 설정

### Step 4: 트리거 자동화 (2일)
- Prometheus rule: `WorkerNodeAtCapacity`
- AlertManager webhook
- Lambda 또는 Jenkins job

### Step 5: Scale down 정책 (3일)
- 매일 자정에 사용률 30% 이하면 노드 drain + 삭제
- maximum cap (예: 10대)

### Step 6: 검증 (1주)
- 부하 테스트 → 노드 자동 생성 확인
- 부하 제거 → 자동 삭제 확인 (시간 지연)

**총 ~2주**

---

## 🔗 다른 파트와의 연결

| 파트 | 연결 |
|---|---|
| 🏛️ 자기 (`04-burst-architecture.md`) | AWS Karpenter와 비교 (대조점) |
| 🏛️ 자기 (`06-cost-spof-tradeoffs.md`) | 자원 부족 SPoF로 추가 |
| 🔧 CI/CD | Jenkins job으로 Terraform run |
| 🔒 보안 | kubeadm token, Proxmox API credential |

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. AWS는 Karpenter 자동인데 온프레는 수동인 거 알았나?**
A. 솔직히 인지. AWS Karpenter = 40초 자동 spot, 온프레 = 수동 30분. **하이브리드 일관성 부족**. Phase 7에서 Terraform + Ansible로 자동화 계획.

**Q2. Karpenter처럼 빠르게 가능한가?**
A. Proxmox VM 생성 ~2분 + cloud-init ~30초 + kubeadm join ~30초 = 약 **3분**. EC2 spot 40초보다 느림. 하지만 사람 30분 대비 ★★★ 빠름.

**Q3. Cluster API for Proxmox 왜 안 썼나?**
A. (1) CAPI 학습 곡선 ★★★, (2) Proxmox provider 미성숙 (community), (3) Terraform이 더 보편적 + 다른 cloud 호환. CAPI는 K8s native 매력은 인정.

**Q4. 자동 scale down 어떻게?**
A. (1) 매일 자정에 사용률 평가, (2) drain → 노드 삭제, (3) PodDisruptionBudget 존중. 자정에만 (사용자 영향 적은 시점). 즉시 down은 위험.

**Q5. 자동 scale 비용 폭발 방지?**
A. (1) maximum cap (예: 10대 한도), (2) Prometheus alert false positive 줄이기 (5분 sustained), (3) AWS Budget alert와 연동, (4) Slack 알림으로 사람 인지.

**Q6. 비싸도 AWS만 가는 게 나은 거 아닌가?**
A. (1) 학습 가치 (온프레 자동화 직접), (2) 비용 (AWS spot도 시간당 과금), (3) 데이터 주권. 우리 워크로드 규모엔 온프레 자동화가 합리적.
