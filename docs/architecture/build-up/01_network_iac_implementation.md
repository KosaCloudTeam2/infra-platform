# 01 Cloud / Network / IaC Implementation

담당: 팀원 2

## 1. 목표

Terraform으로 VPC, Subnet, ALB, Security Group, EC2 Auto Scaling Group, DB용 EC2 골격을 재현
가능하게 구성함. AWS burst 진입점은 ALB로 제한하고, 앱 EC2와 DB 계층은 Private Subnet에 배치함.

## 2. 사전 조건

- `infra/terraform/env/dev.tfvars`의 `project_name`, `aws_region`, `github_repository` 확인
- Terraform CLI 설치 및 `terraform -chdir=infra/terraform validate` 통과
- AWS 인증 전에는 `init -backend=false`, `fmt`, `validate`까지만 수행
- AWS 인증 후 `plan`으로 실제 리소스 생성 예정 목록 검토

## 3. 구현 순서

1. VPC와 Public/App Private/Data Private Subnet CIDR 확인
2. Internet Gateway, NAT Gateway, Route Table 구성 확인
3. ALB, Target Group, Listener 구성 확인
4. ALB SG, AWS burst app SG, ProxySQL SG, PXC SG 규칙 확인
5. DB용 EC2와 ProxySQL EC2가 Data Private Subnet에 생성되는지 확인
6. SSM Session Manager용 IAM Role과 Instance Profile 연결 확인
7. 선택 확장 시 ProxySQL Internal NLB 구성 확인

## 4. Terraform 작업

AWS 인증 전 검증:

```powershell
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
```

AWS 인증 후 검증:

```powershell
aws sts get-caller-identity
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars
```

ProxySQL 이중화 시 `env/dev.tfvars` 변경:

```hcl
proxysql_count               = 2
enable_proxysql_internal_nlb = true
```

## 5. 검증 절차

- `plan`에서 ALB만 Public Subnet에 배치되는지 확인
- AWS burst app EC2의 `associate_public_ip_address = false` 확인
- ProxySQL/PXC EC2의 `associate_public_ip_address = false` 확인
- DB 포트 `3306`, `6033`, `4567/4568/4444`가 `0.0.0.0/0`에 열리지 않는지 확인
- AWS burst app SG 또는 허용된 온프레미스 CIDR에서 ProxySQL SG로만 `6033` 접근하는지 확인
- ProxySQL SG에서 PXC SG로만 `3306` 접근하는지 확인
- PXC Galera 포트는 PXC SG self traffic으로 제한되는지 확인

## 6. 산출물

- `terraform plan` 요약
- ALB DNS output
- ProxySQL private IP 또는 Internal NLB DNS output
- PXC private IP 목록 output
- 주요 Security Group 규칙 캡처
- 비용 발생 리소스 목록

## 7. 인계 기준

- CI/CD 담당자에게 ALB DNS, AWS burst Target Group, ProxySQL endpoint 인계
- DB/Storage 담당자에게 PXC/ProxySQL EC2 private IP와 SSM 접속 방식 인계
- Observability / Integration 담당자에게 네트워크 보안 경계와 비용 리스크 인계

## 8. 주의 사항

- Terraform state는 커밋하지 않음
- `apply`는 팀 합의 후 담당자 1명만 수행함
- NAT Gateway는 비용이 발생하므로 발표 후 정리 대상에 포함함
- ProxySQL 1대는 단일 장애점(SPoF)이므로 발표 한계로 명시함
