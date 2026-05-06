# Terraform Guide

온프레미스 Kubernetes를 기본 런타임으로 두고, AWS는 비용 우선 burst 영역으로 사용하는 Terraform 작업
공간임. MVP 기본 경로는 **ALB + EC2 Auto Scaling Group + Launch Template**이며, ECS Fargate는 더
이상 기본 인프라가 아님.

## 1. 구성 리소스

- VPC
- Public / App Private / Data Private Subnet
- Internet Gateway
- NAT Gateway 1개
- Route Table
- Security Group
- ALB / Target Group / Listener
- AWS burst app Launch Template
- AWS burst app EC2 Auto Scaling Group
- DB용 EC2 / ProxySQL EC2
- ProxySQL / PXC Security Group
- 선택: ProxySQL Internal NLB
- SSM Session Manager용 EC2 IAM Role
- GitHub Actions OIDC Role
- CloudWatch Alarm
- WAF Web ACL

## 2. 검증 절차

### 2.1 AWS 인증 전

AWS 인증 전에는 포맷, 초기화, 문법 검증까지만 수행함.

```powershell
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform fmt -check -recursive
terraform -chdir=infra/terraform validate
```

### 2.2 AWS 인증 후

`plan`은 AWS provider가 실제 계정 정보를 조회하므로 AWS CLI 인증 후 실행함.

```powershell
aws sts get-caller-identity
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -recursive
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan -var-file=env/dev.tfvars
```

적용 전 `env/dev.tfvars`의 값을 실제 환경에 맞춤.

- `github_repository = "OWNER/REPO"`를 실제 GitHub 저장소명으로 변경
- `app_image`를 실제 Docker Hub 이미지로 변경
- 비용 제한에 맞춰 `app_min_size`, `app_desired_capacity`, `app_max_size` 확인

적용은 팀 합의 후 담당자 1명만 수행함.

```powershell
terraform -chdir=infra/terraform apply -var-file=env/dev.tfvars
```

## 3. plan 검토 기준

- ALB와 NAT Gateway만 Public Subnet에 배치됨
- AWS burst app EC2는 App Private Subnet에 배치되고 Public IP가 없음
- AWS burst app EC2는 Launch Template user data로 Docker 이미지를 실행함
- ALB Target Group 대상이 Auto Scaling Group 인스턴스로 연결됨
- ProxySQL과 PXC EC2는 Data Private Subnet에 배치되고 Public IP가 없음
- ProxySQL Client 포트 `6033`은 app SG 또는 선택 Internal NLB SG에서만 접근 가능함
- PXC MySQL 포트 `3306`은 ProxySQL SG에서만 접근 가능함
- Galera 포트 `4567/4568/4444`는 PXC 노드 간 통신으로 제한됨
- GitHub OIDC Trust Policy가 실제 저장소명으로 제한됨
- NAT Gateway, EC2, ALB, WAF 등 비용 발생 리소스 수가 의도와 일치함

## 4. 주의 사항

- `*.tfstate` 파일은 커밋하지 않음
- 실운영 협업 시 S3 Backend와 DynamoDB Lock Table 사용 권장
- 비용 발생 리소스(ALB, NAT Gateway, EC2, WAF)는 발표 후 정리 계획을 따름
- DB EC2는 Public IP를 부여하지 않으며, 직접 SSH 대신 SSM Session Manager 접근을 기본값으로 사용함
- PXC/ProxySQL 설치와 클러스터 구성은 Terraform 이후 DB Runbook 또는 Ansible로 수행함
- 기본값은 ProxySQL 1대 MVP임. 이중화가 필요하면 `env/dev.tfvars`에서 `proxysql_count = 2`,
  `enable_proxysql_internal_nlb = true`로 변경함
- ProxySQL Internal NLB를 켠 경우 애플리케이션 `DB_HOST`는 `proxysql_internal_nlb_dns_name` 출력값을
  사용함
