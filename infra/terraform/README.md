# Terraform Guide

AWS ECS Fargate 기반 MVP 인프라를 선언적으로 구성하기 위한 Terraform 작업 공간

## 1. 구성 리소스

- VPC
- Public/Private Subnet
- Internet Gateway
- Route Table
- Security Group
- ALB / Target Group / Listener
- ECR Repository
- ECS Cluster / Task Definition / Service
- DB용 EC2 / ProxySQL EC2
- ProxySQL / PXC Security Group
- 선택: ProxySQL Internal NLB
- SSM Session Manager용 EC2 IAM Role
- IAM Role
- CloudWatch Log Group / Alarm
- WAF Web ACL

## 2. 검증 절차

### 2.1 AWS 인증 전

AWS 인증 전에는 포맷, 초기화, 문법 검증까지만 수행함.

```powershell
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
```

이 단계는 AWS 자격 증명이 없어도 실행 가능해야 함.

### 2.2 AWS 인증 후

`plan`은 AWS provider가 실제 계정 정보를 조회하므로 AWS CLI 인증 후 실행함.

```powershell
aws sts get-caller-identity
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars
```

적용 전 `env/dev.tfvars`의 `github_repository = "OWNER/REPO"`를 실제 GitHub 저장소명으로 바꿈.
적용은 팀 합의 후 담당자 1명만 수행함.

```powershell
terraform -chdir=infra/terraform apply -var-file=env/dev.tfvars
```

### 2.3 plan 검토 기준

- ALB만 Public Subnet에 배치됨
- ECS Task는 App Private Subnet에 배치되고 `assign_public_ip = false`임
- ProxySQL과 PXC EC2는 Data Private Subnet에 배치되고 Public IP가 없음
- ProxySQL Client 포트 `6033`은 ECS SG에서만 접근 가능함
- PXC MySQL 포트 `3306`은 ProxySQL SG에서만 접근 가능함
- Galera 포트 `4567/4568/4444`는 PXC 노드 간 통신으로 제한됨
- GitHub OIDC Trust Policy가 실제 저장소명으로 제한됨
- WAF Web ACL, CloudWatch Log Group, ECS Deployment Circuit Breaker가 포함됨
- NAT Gateway, EC2, ALB, WAF 등 비용 발생 리소스 수가 의도와 일치함

## 3. 주의 사항

- `*.tfstate` 파일은 커밋하지 않음
- 실운영 협업 시 S3 Backend와 DynamoDB Lock Table 사용 권장
- 비용 발생 리소스(ALB, NAT Gateway, Fargate, WAF)는 Day 13 이후 정리 계획 필요
- DB EC2는 Public IP를 부여하지 않으며, 직접 SSH 대신 SSM Session Manager 접근을 기본값으로 사용함
- PXC/ProxySQL 설치와 클러스터 구성은 Terraform 이후 Ansible 또는 수동 Runbook으로 수행함
- 기본값은 ProxySQL 1대 MVP임. 이중화가 필요하면 `env/dev.tfvars`에서 `proxysql_count = 2`,
  `enable_proxysql_internal_nlb = true`로 변경함
- ProxySQL Internal NLB를 켠 경우 애플리케이션 `DB_HOST`는 `proxysql_internal_nlb_dns_name` 출력값을
  사용함
