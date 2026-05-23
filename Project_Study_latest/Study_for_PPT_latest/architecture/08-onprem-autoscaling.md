# 08. 온프레 워커노드 자동 프로비저닝 (Terraform + Ansible)

> ⭐ **한 줄 요약**: AWS는 Karpenter로 40초 만에 자동 spot 노드를 생성하는데 **온프레는 사람이 수동으로 30분+ 걸린다**. 워커 자원 부족하면 Pod이 Pending으로 무한 대기. 이 비대칭을 해소하려면 **Prometheus alert → Lambda/Jenkins → Terraform (Proxmox provider) → Ansible kubeadm join** 흐름으로 자동화가 필요하다.

---

## 🚨 문제 정의

### 현재 상태 — 자동화가 없다

K8s scheduler가 Pod을 띄울 노드를 찾지 못하면 그 Pod은 **Pending 상태로 무한 대기**한다. 사람이 들어와서 직접 처리해야 한다.

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

비즈니스 시간엔 누군가 알람 받고 빨리 대응하지만, 새벽이나 주말이면 늦어진다. 그동안 Pod은 계속 Pending. 진짜 운영 환경엔 받아들이기 어려운 상태다.

### AWS 측과 대조하면 불공정

같은 시나리오를 AWS에서 보면 매우 다르다.

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

**모순 인지**: AWS는 자동, 온프레는 수동. 하이브리드 환경에서 일관성이 부족하다. 사용자 경험 측면에서도 AWS 측 burst는 빠르게 응답되는데 온프레는 느리니, 두 사이트의 SLA가 다르게 운영되는 셈이다.

---

## 🎯 우리가 원하는 자동화 구조

이상적으로는 다음 흐름으로 동작해야 한다.

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

전체 시간 목표는 3분 내. AWS Karpenter (40초)보단 느리지만 사람 수동 (30분)보단 한참 빠르다.

---

## 🔍 구현 옵션

### Option A: ⭐ Terraform + Ansible (직접 자동화)

가장 보편적이고 자료가 풍부한 패턴이다. **Terraform Proxmox provider**가 VM 생성을 declarative하게 처리하고, **Ansible playbook**이 OS 설정과 kubeadm join을 자동화한다.

```hcl
# terraform/onprem/worker-pool/main.tf
resource "proxmox_vm_qemu" "k8s_worker" {
  count       = var.worker_count
  name        = "k8s-w${count.index + 4}"   # w4, w5, ...
  target_node = "kosa${(count.index % 4) + 1}"   # 4개 호스트 분산
  clone       = "ubuntu-2204-k8s-template"
  cores       = 2
  memory      = 6144
  
  network {
    bridge = "vmbr1"
    tag    = 30
  }
  ipconfig0 = "ip=dhcp"
}

# 생성 후 ansible로 kubeadm join
resource "null_resource" "k8s_join" {
  count = var.worker_count
  depends_on = [proxmox_vm_qemu.k8s_worker]
  
  provisioner "local-exec" {
    command = "ansible-playbook -i ${ip}, ansible/k8s-worker-join.yml -e join_token=${token}"
  }
}
```

Ansible playbook은 짧다:

```yaml
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

트리거는 Prometheus rule + AlertManager webhook + Lambda 조합:

```yaml
# Prometheus rule
- alert: WorkerNodeAtCapacity
  expr: |
    sum by (node) (kube_pod_container_resource_requests{resource="cpu"})
    / on(node) kube_node_status_allocatable{resource="cpu"} > 0.85
  for: 5m
  labels:
    severity: warning
    auto_scale: "true"
```

Lambda는 alert 받아서 `terraform apply -var=worker_count=${current + 1}` 실행. 끝.

- ✅ **장점**: 완전 자동화, 우리 burst 패턴과 일관성
- ❌ **단점**: Terraform/Ansible 학습 + Proxmox provider 함정
- 💰 **비용**: 0 (도구 무료)
- ⏱️ **작업**: 1~2주 (Terraform 모듈 + Ansible playbook + 트리거 자동화)
- 🎯 **추천 시점**: Phase 7 (운영 진입)

### Option B: ⭐ Cluster API for Proxmox (CAPI)

CAPI는 K8s 표준으로 cluster + node를 관리한다. Proxmox provider도 community에 있다.

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

**`kubectl scale machinedeployment kosa-worker-pool --replicas=6`** 한 줄로 노드 추가가 가능하다. 진짜 K8s native 패턴이다.

- ✅ **장점**: K8s native, declarative, kubectl로 관리
- ❌ **단점**: CAPI 학습 곡선 ★★★, Proxmox provider 미성숙
- 🎯 **추천 시점**: 진짜 K8s native + CAPI 학습 의지

### Option C: 수동 + 알람만

현재 상태를 그대로 두되 Prometheus alert로 "노드 자원 부족 경고" 이메일을 추가하는 옵션이다. 사람이 수 시간 내 수동 대응. 학습 부담 0이지만 자동화 가치도 0.

- 🎯 **추천 시점**: 학습 환경 그대로 (현재)

### Option D: AWS Burst로 자동 우회 (현재 hybrid 활용)

이미 구축된 AWS burst를 활용하는 옵션. 온프레 워커 자원이 부족하면 일반 alert로 burst trigger 발동 → EKS Karpenter spot이 자동 생성해서 트래픽 일부 흡수. 온프레 노드 추가는 사람이 천천히 처리.

- ✅ **장점**: 이미 구축됨, 즉시 부하 해소
- ❌ **단점**: AWS 비용 발생, 온프레 자원은 그대로
- 🎯 **추천 시점**: 즉시 (이미 Phase 4 동작)

### Option E: KubeVirt (K8s 안에서 VM 관리)

K8s 안에 VM도 띄우는 패턴. kubectl로 VM 생성/삭제 가능. 우리 Proxmox와 중복되고 학습 곡선이 있어 비추.

### Option F: 큰 단일 호스트 → micro VM 패턴

거대 호스트 1대 + Firecracker/Kata로 micro VM 자동 생성. 학습 환경엔 과한 패턴.

---

## 📊 의사결정 매트릭스

| 신호 | 우선 옵션 |
|---|---|
| 학습/데모 (현재) | C (수동) + D (burst) |
| Phase 7 운영 진입 | A (Terraform/Ansible) ⭐ |
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

### 수동 vs 자동 ROI 비교

수동으로 VM 1대 추가하는 데 30분 작업. 월 평균 5회 발생한다고 가정하면 월 2.5시간 × ₩50,000/h = **₩125,000/월** 인건비. 자동화 한 번 구축에 2주 들어도 **2.5개월에 ROI**가 나온다. 운영 부담이 누적적이라 자동화 가치가 크다.

---

## ⚖️ Trade-off

| 얻은 것 (Option A) | 잃은 것 |
|---|---|
| 자동 scale (사람 개입 0) | Terraform/Ansible 학습 |
| RTO 1분 (vs 수동 30분) | Proxmox provider 함정 |
| IaC = 변경 추적 (Git) | 자동 scale up은 비용 ↑ 위험 |
| AWS Karpenter와 일관성 | 자동 scale down 어려움 (워크로드 drain) |

가장 큰 trade-off는 **자동 scale의 안전성**이다. Scale up은 쉬운데 down은 복잡하다. Pod이 노드에 분산되어 있어서 노드를 비우려면 drain (다른 노드로 reschedule) 필요. 모든 Pod이 reschedule 가능해야만 노드 삭제 가능하다.

---

## ⚠️ 자동 scale의 함정

### 함정 1: Scale up은 쉬운데 down 어려움

Pod이 새 노드에 분산되어 있어서 "이 노드를 비우자"는 복잡한 의사결정이다. PodDisruptionBudget을 존중하면서 drain해야 하고, 어떤 Pod이 다른 노드에 schedule 가능한지 사전 확인이 필요하다. **Scale down은 정책적**으로 가야 한다 (예: 매일 자정에만 자동 삭제 검토).

### 함정 2: 비용 폭발 위험

alert false positive로 노드를 잘못 추가하면 자원 낭비. 가드는 **maximum nodes 제한** (예: 10대 한도) + alert 조건 강화 (5분 sustained 같이).

### 함정 3: Proxmox 자원 한계

VM을 생성하려면 Proxmox 호스트에 자원 (CPU/RAM/disk)이 있어야 한다. 4개 Proxmox 노드 자원을 다 쓰면 추가 호스트가 필요. **무한 확장이 안 됨**.

### 함정 4: K8s join token 만료

kubeadm token은 default 24h 만료. 자동 scale 시 매번 새 token 발급이 필요. `kubectl create token` 명령을 자동화에 포함해야 한다.

---

## 🚀 Phase 7 구현 단계

### Step 1: Proxmox VM template 정비 (3일)

`ubuntu-2204-k8s-template` (cloud-init + kubeadm pre-installed)를 만들어서 모든 노드에서 clone 가능하게.

### Step 2: Terraform 모듈 작성 (3일)

`terraform/onprem/worker-pool/` 디렉토리에 Proxmox provider 설정 + variable (worker_count) + output (VM IP).

### Step 3: Ansible playbook (2일)

`ansible/k8s-worker-join.yml`에 kubeadm join 자동화 + 라벨 설정.

### Step 4: 트리거 자동화 (2일)

Prometheus rule `WorkerNodeAtCapacity` + AlertManager webhook + Lambda (또는 Jenkins job).

### Step 5: Scale down 정책 (3일)

매일 자정에 사용률 30% 이하면 노드 drain + 삭제. maximum cap (예: 10대).

### Step 6: 검증 (1주)

부하 테스트 → 노드 자동 생성 확인. 부하 제거 → 자동 삭제 확인 (시간 지연 둘 것).

**총 ~2주**

---

## 🔗 다른 파트와의 연결

이 자동화는 AWS Karpenter (`architecture/04-burst-architecture.md`)와 대조점이다. 같은 자동화 컨셉을 온프레에서도 구현하면 하이브리드 일관성이 ↑된다. SPoF 분석 (`06-cost-spof-tradeoffs.md`)에 #14로 추가돼 있다. CI/CD 측면에선 Jenkins job으로 Terraform run이 가능하다. 보안 측면에선 kubeadm token과 Proxmox API credential 관리가 중요하다.

---

## ❓ 면접/발표 예상 질문 + 모범 답변

**Q1. AWS는 Karpenter 자동인데 온프레는 수동인 거 알고 계셨나요?**

A. **솔직히 인지하고 있는 약점**입니다. AWS Karpenter = 40초 자동 spot, 온프레 = 수동 30분. 하이브리드 일관성 부족입니다. Phase 7에서 Terraform + Ansible로 자동화 계획을 잡았습니다.

**Q2. Karpenter처럼 빠르게 가능한가요?**

A. **약 3분 정도** 가능합니다. Proxmox VM 생성 ~2분 + cloud-init ~30초 + kubeadm join ~30초. EC2 spot 40초보단 느리지만 사람 30분 대비 ★★★ 빠릅니다. Proxmox vs EC2의 가상화 layer 차이가 본질적 속도 차이입니다.

**Q3. Cluster API for Proxmox 왜 안 썼나요?**

A. 세 가지 이유입니다. **CAPI 학습 곡선 ★★★**, **Proxmox provider 미성숙** (community), **Terraform이 더 보편적** + 다른 cloud 호환. CAPI는 K8s native 매력은 인정하지만 우선순위가 ↓이었습니다.

**Q4. 자동 scale down은 어떻게 안전하게 하나요?**

A. 세 단계로 합니다. **첫째, 매일 자정에 사용률 평가** (사용자 영향 적은 시점). **둘째, drain → 노드 삭제** (PodDisruptionBudget 존중). **셋째, maximum/minimum cap 설정** (예: min 4, max 10). 즉시 down은 위험하니 시간 지연 + 정책 기반으로.

**Q5. 자동 scale 비용 폭발을 어떻게 방지하나요?**

A. 네 가지 가드입니다. **maximum cap** (예: 10대 한도), **Prometheus alert false positive 줄이기** (5분 sustained), **AWS Budget alert와 연동**, **Slack 알림으로 사람 인지**. false positive 비용은 spot 시간당 $0.03 정도라 즉시 발생해도 큰 손해는 아닙니다.

**Q6. 비싸도 AWS만 가는 게 나은 것 아닌가요?**

A. 세 가지 이유로 온프레 자동화도 가치 있습니다. **학습 가치** (Proxmox provider, IaC 직접 경험). **비용** (AWS spot도 시간당 과금, 누적적). **데이터 주권**. 우리 워크로드 규모엔 온프레 자동화가 합리적입니다. 진짜 글로벌 운영 + 트래픽 폭증 자주 발생하면 AWS 비중을 늘리는 것도 옵션입니다.
