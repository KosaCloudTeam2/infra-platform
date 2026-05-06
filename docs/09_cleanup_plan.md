# 리소스 정리 계획

## 1. 정리 대상

- AWS EC2 Auto Scaling Group
- Launch Template
- ECS fallback 리소스
- Docker Hub Repository 이미지
- ALB / Target Group / Listener
- WAF Web ACL
- CloudWatch Log Group
- PXC EC2
- ProxySQL EC2
- ProxySQL Internal NLB를 켠 경우 NLB와 Target Group
- VPC / Subnet / Route Table / IGW / NAT Gateway
- IAM Role / Policy / OIDC Provider

## 2. 정리 명령

```powershell
terraform -chdir=infra/terraform destroy -var-file=env/dev.tfvars
```

## 3. 수동 확인

- Docker Hub 이미지가 남아 있으면 삭제 필요
- CloudWatch Log Group 보존 여부 확인
- NAT Gateway가 남아 있으면 비용 발생 가능
- Elastic IP가 남아 있으면 비용 발생 가능
- PXC/ProxySQL EC2가 남아 있으면 비용 발생 가능
- Proxmox/Ceph는 AWS Terraform destroy 대상이 아니므로 별도 온프레미스 정리 기준을 따름

## 4. 발표 후 원칙

발표가 끝나면 팀 합의에 따라 보관할 리소스와 삭제할 리소스를 구분함. 비용 발생 리소스는 원칙적으로
당일 정리함.
