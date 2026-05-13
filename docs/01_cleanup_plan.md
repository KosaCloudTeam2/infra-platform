# 리소스 정리 계획 (Demo Version)

> **주의**: 본 문서는 프로젝트의 **데모(Demo) 버전** 또는 **임시 구조**를 설명하고 있습니다. 향후
> 전체적인 프로젝트 구조가 변경될 예정이므로 참고하시기 바랍니다.

## 1. 정리 대상

- AWS EC2 Auto Scaling Group
- Launch Template
- Docker Hub Repository 이미지
- NLB / Target Group / Listener
- WAF Web ACL
- CloudWatch Log Group
- Percona Operator 관련 리소스
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
- Percona Operator 노드/인스턴스가 남아 있으면 비용 발생 가능
- Proxmox/Ceph는 AWS Terraform destroy 대상이 아니므로 별도 온프레미스 정리 기준을 따름

## 4. 발표 후 원칙

발표가 끝나면 팀 합의에 따라 보관할 리소스와 삭제할 리소스를 구분함. 비용 발생 리소스는 원칙적으로
당일 정리함.
