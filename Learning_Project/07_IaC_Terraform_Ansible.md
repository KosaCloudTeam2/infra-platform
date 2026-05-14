# 07. IaC — Terraform + Ansible

> Layer 3 / 학습 1일

---

## 1) IaC가 풀어주는 문제

수동:

- "kosa1에 어떤 설정 했지?" 기억 안 남
- 새 서버 추가 = 같은 작업 반복
- 환경 차이 (개발/운영) 추적 불가
- 팀원 새로 합류 = 환경 셋업 1주

→ **코드로 인프라 정의** = 재현성 + 버전 관리 + 자동화.

---

## 2) Terraform vs Ansible — 책임 분담

|           | **Terraform**                | **Ansible**                 |
| --------- | ---------------------------- | --------------------------- |
| 패러다임  | 선언적 (Declarative)         | 절차적 (Procedural)         |
| 풀어주는  | "어떤 인프라" (VM, 네트워크) | "어떤 설정" (패키지, 파일)  |
| 상태 추적 | tfstate 파일                 | 매번 SSH로 확인             |
| 멱등성    | 자동 (diff 계산)             | 모듈이 보장                 |
| 우리 사용 | Proxmox VM 생성, AWS 리소스  | K8s 부트스트랩, 패키지 설치 |

### 둘 다 쓰는 이유

```
[Terraform]              [Ansible]
"VM 7대 만들어"           "각 VM에 K8s 깔아"
   ↓                         ↓
[Proxmox API]            [SSH로 VM에 접속]
   ↓                         ↓
VM 인프라                  K8s 클러스터
```

Terraform만 → VM 안 설정 어려움<br> Ansible만 → VM 자체 생성 못 함 (불가능은 아니지만 부자연스러움)

---

## 3) Terraform 핵심 개념

### 3종 파일

| 파일        | 역할                       |
| ----------- | -------------------------- |
| `*.tf`      | 인프라 선언 (HCL 언어)     |
| `*.tfvars`  | 값 (gitignore)             |
| `*.tfstate` | 현재 상태 추적 (자동 생성) |

### 흐름

```
terraform init      # provider 다운로드
terraform plan      # 변경 미리보기
terraform apply     # 실제 적용
terraform destroy   # 전부 삭제
```

### provider

| Provider               | 무엇을                                |
| ---------------------- | ------------------------------------- |
| `hashicorp/aws`        | AWS VPC, EC2                          |
| `bpg/proxmox`          | Proxmox VM (우리가 쓰는 것)           |
| `hashicorp/kubernetes` | K8s 리소스 (보통 안 씀, Ansible이 함) |

### state 관리

- **로컬**: `terraform.tfstate` 파일 (우리)
- **원격**: S3 backend + DynamoDB lock (팀 협업용, 운영 권장)

---

## 4) Ansible 핵심 개념

### 3종 파일

| 파일                  | 역할                      |
| --------------------- | ------------------------- |
| `inventory/hosts.yml` | 대상 호스트 (그룹 + 변수) |
| `playbooks/*.yml`     | 실행할 작업               |
| `roles/*`             | 재사용 가능한 모듈        |

### 흐름

```
ansible all -m ping                       # 연결 테스트
ansible-playbook playbooks/00-...yml      # 실행
ansible-galaxy collection install ...     # 의존성 설치
```

### 멱등성

같은 playbook을 100번 돌려도 결과 동일.

```yaml
- name: nginx 설치
  apt:
    name: nginx
    state: present # 이미 깔려있으면 skip
```

`changed: no` 가 나오면 멱등성 작동.

---

## 5) 우리 프로젝트 구조

```
terraform/
├── onprem/                    Proxmox VM 7대 생성
│   ├── main.tf
│   ├── variables.tf
│   ├── terraform.tfstate     ← 로컬 state
│   └── terraform.tfvars      ← 비밀번호 등 (gitignore)
└── aws/                       AWS Phase 1~5
    ├── vpc.tf
    ├── nlb.tf
    └── ...

ansible/
├── inventory/hosts.yml        Terraform output에서 자동 생성
├── playbooks/
│   ├── 00-bootstrap.yml       hostname, swap, NTP
│   ├── 10-k8s-prepare.yml     containerd, 커널 모듈
│   ├── 20-k8s-install.yml     kubeadm/kubelet/kubectl
│   ├── 30-k8s-init.yml        cluster init + join
│   └── 40-k8s-addons.yml      Calico, MetalLB, Percona Operator
└── roles/
```

---

## 6) 대안 비교

### Terraform vs

|               | **Terraform** | Pulumi       | CloudFormation | Crossplane |
| ------------- | ------------- | ------------ | -------------- | ---------- |
| 언어          | HCL           | TS/Python/Go | YAML/JSON      | K8s YAML   |
| 멀티 클라우드 | ✅            | ✅           | AWS only       | ✅         |
| 학습 가치     | 표준          | 모던         | AWS 한정       | K8s native |

### Ansible vs

|           | **Ansible**  | Chef | Puppet     | SaltStack |
| --------- | ------------ | ---- | ---------- | --------- |
| 에이전트  | 불필요 (SSH) | 필요 | 필요       | 필요      |
| 언어      | YAML         | Ruby | Puppet DSL | YAML      |
| 학습 곡선 | 낮음         | 중   | 중         | 중        |

---

## 7) 발표 어필

> _"인프라 라이프사이클은 Terraform으로 (선언적, state 추적), 호스트 내부 설정은 Ansible로 (멱등성,
> 절차적) 책임 분담했습니다. 100% 코드로 정의되어 새 환경에서도 30분 안에 동일 인프라 재현
> 가능합니다."_

---

## 다음 단원

[`08_GitOps_ArgoCD.md`](08_GitOps_ArgoCD.md)
