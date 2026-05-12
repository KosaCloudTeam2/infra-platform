# Terraform — 인프라 IaC

> kosa-day 프로젝트의 모든 Terraform 코드.

## 디렉토리 구조

```
terraform/
├── modules/              # 재사용 가능한 모듈
│   └── vm/               # Proxmox VM 모듈 (cloud-init 기반)
│
├── onprem/               # 온프레미스 (Proxmox)
│   ├── providers.tf      # bpg/proxmox
│   ├── variables.tf
│   ├── main.tf           # VM 7대 생성 (CP3 + W3 + Bastion)
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── README.md
│
└── aws/                  # AWS (다음 단계)
    └── README.md         # placeholder, 추후 작성
```

## 적용 순서

```bash
# 1) 온프레 먼저
cd onprem
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
terraform init
terraform plan
terraform apply

# 2) AWS (온프레 안정 후)
cd ../aws
# TBD
```

## State 관리

초기엔 각 디렉토리 안에 `terraform.tfstate` 로컬 파일로.
안정 후 Ceph RGW (S3 호환) backend로 이전 예정.

## 주의

- **pfSense VM은 절대 Terraform 관리 X** (이미 운영 중)
- `terraform.tfvars` 는 `.gitignore` 포함 (시크릿)
- MAC 주소 한 번 결정되면 절대 변경 금지
