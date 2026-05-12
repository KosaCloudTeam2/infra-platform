# Terraform AWS

> kosa-day 프로젝트의 AWS 측 인프라 (VPC, EKS, RDS, Route 53, Lambda).
> **다음 단계에서 작성 예정** — 현재는 placeholder.

## 작성 예정 파일

```
terraform/aws/
├── providers.tf      # AWS provider 설정
├── variables.tf      # AWS region, 자격증명 등
├── vpc.tf            # VPC, Subnet, IGW, NAT Gateway
├── eks.tf            # EKS 클러스터 + IAM 역할
├── karpenter.tf      # Karpenter NodePool (Spot 정책)
├── rds.tf            # RDS for MySQL (Read Replica)
├── route53.tf        # Hosted Zone + Weighted Records
├── lambda.tf         # Burst 자동화 Lambda 함수들
├── iam.tf            # IAM 정책/역할
└── terraform.tfvars.example
```

## 시점

온프레 구축 완료 (Day 5 전후) 이후 시작.
온프레가 안정 동작해야 AWS Burst 의미가 있음.
