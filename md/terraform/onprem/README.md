# Terraform 온프레미스 (Proxmox)

> kosa-day 프로젝트의 온프레미스 K8s VM을 Proxmox에 생성하는 Terraform 코드.

## 무엇을 만드는가

총 **7대의 VM**을 Proxmox 4대(kosa1~kosa4)에 자동 분산 배치.
**Worker는 3개 다른 PVE에 분산** → 단일 노드 장애 시에도 워커 2대 보존.

| VM | 용도 | 사양 | 위치 | IP |
|---|---|---|---|---|
| k8s-cp1 | K8s Control Plane #1 | 2C 4G 40G | kosa1 | 172.16.23.10 |
| k8s-cp2 | K8s Control Plane #2 | 2C 4G 40G | kosa2 | 172.16.23.11 |
| k8s-cp3 | K8s Control Plane #3 | 2C 4G 40G | kosa3 | 172.16.23.12 |
| k8s-w1 | K8s Worker #1 | 4C 6G 80G | kosa3 | 172.16.23.20 |
| k8s-w2 | K8s Worker #2 | 4C 6G 80G | kosa4 | 172.16.23.21 |
| k8s-w3 | K8s Worker #3 | 4C 6G 80G | **kosa2** | 172.16.23.22 |
| bastion | Ansible runner + 도구 | 1C 2G 20G | **kosa3** | 172.16.24.10 |

### Proxmox 노드별 K8s VM 합계

| Proxmox | pfSense | K8s VM | K8s 메모리 |
|---|---|---|---|
| kosa1 | MASTER | CP1 | 4GB |
| kosa2 | BACKUP | CP2 + W3 | 10GB |
| kosa3 | - | CP3 + W1 + Bastion | 12GB |
| kosa4 | - | W2 | 6GB |

## 파일 구조

```
terraform/onprem/
├── providers.tf              # bpg/proxmox provider 설정
├── variables.tf              # 변수 정의 (VM 사양, IP 등)
├── main.tf                   # VM 모듈 호출 (CP + W + Bastion)
├── outputs.tf                # 생성된 VM IP + Ansible inventory 자동 생성
├── terraform.tfvars.example  # 환경값 예제
├── terraform.tfvars          # 실제 값 (gitignore!)
└── README.md                 # 이 문서

../modules/vm/                # 재사용 가능한 VM 모듈
├── main.tf
├── variables.tf
└── outputs.tf
```

## 사전 준비 체크리스트

- [ ] Proxmox 4대(kosa1~kosa4) 정상 작동
- [ ] pfSense HA 완료 (다른 작업)
- [ ] **Ubuntu 22.04 cloud-init 템플릿 (VMID 9000) 생성** — Lab 2 참고
- [ ] Proxmox API 토큰 발급
- [ ] SSH 키 생성 (`~/.ssh/kosa_iac`)
- [ ] 로컬에 Terraform 1.5+ 설치 (`brew install terraform` 또는 `apt install terraform`)

## 사용법

### 1) 변수 파일 작성

```bash
cd terraform/onprem
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars     # API 토큰, SSH 키 입력
```

### 2) Terraform 초기화

```bash
terraform init
```

→ `.terraform/` 디렉토리 생성, provider 다운로드.

### 3) 변경 사항 미리보기

```bash
terraform plan
```

기대 출력: `Plan: 7 to add, 0 to change, 0 to destroy.`

### 4) VM 생성

```bash
terraform apply
# "yes" 입력
```

약 10분 안에 7대 VM 생성 완료. cloud-init이 SSH 키 자동 주입.

### 5) Bastion 접속 확인

```bash
ssh -i ~/.ssh/kosa_iac ubuntu@172.16.24.10
# (Bastion에서)
ping 172.16.23.10   # K8s CP1
```

### 6) Ansible inventory 생성

```bash
terraform output -raw ansible_inventory > ../../ansible/inventory/hosts.yml
```

또는 상위 디렉토리의 스크립트 사용:
```bash
../../scripts/generate-inventory.sh
```

## 변경 / 삭제

### 사양 변경 (예: 워커 메모리 증가)

`variables.tf`의 `worker_nodes` 변수에서 memory 값 수정 후:
```bash
terraform plan
terraform apply
```

### 특정 VM만 재생성

```bash
terraform taint 'module.k8s_worker["k8s-w1"]'
terraform apply
```

### 전체 삭제 (주의!)

```bash
terraform destroy
# 7대 VM 모두 사라짐
```

## ⚠️ 주의사항

1. **pfSense VM은 Terraform 관리 X**
   이미 운영 중이라 절대 import 하지 말 것. terraform destroy 사고 시 네트워크 전체 다운.

2. **MAC 주소 자동 생성**
   bpg provider가 자동 할당. 한 번 결정되면 절대 변경 금지 (pfSense가 인터페이스 할당 잃어버림).

3. **state 파일 보관**
   `terraform.tfstate`는 매우 중요. 분실 시 Terraform이 자기가 만든 VM도 모르게 됨.
   - 로컬: 백업 자주 (gitignore에 포함이라 git에 없음)
   - 안정 후: Ceph RGW (S3 호환) backend로 이전

## 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `Error: 401 Unauthorized` | API 토큰 잘못 / 권한 부족 | tfvars의 api_token 확인 |
| `Error: template 9000 not found` | cloud-init 템플릿 없음 | Lab 2 다시 실행 |
| VM 만들어졌는데 SSH 안 됨 | cloud-init이 SSH 키 안 주입 | 콘솔로 확인: `qm config <vmid>` → ciuser/sshkey |
| 같은 VMID 이미 존재 | 충돌 | `qm destroy <vmid>` 후 재시도 |

## 다음 단계

VM 생성 완료 후 → **Ansible로 K8s 부트스트랩** → `../../ansible/README.md` 참고.
