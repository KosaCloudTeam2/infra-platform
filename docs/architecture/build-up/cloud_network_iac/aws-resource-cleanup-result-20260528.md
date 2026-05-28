# AWS 리소스 삭제 결과

> Status: Verified

## 기준

- 실행일: 2026-05-28
- 대상 계정: `357737841289`
- 실행 주체: `arn:aws:iam::357737841289:user/sjkim`
- 대상 리전: `ap-northeast-2`
- 전역 대상: S3, Route 53, CloudFront, WAF, IAM, ACM(us-east-1)
- 삭제 방식: AWS CLI
- 임시 옵션: `--no-verify-ssl`
- 삭제 전 기준 문서: [AWS 삭제 전 리소스 인벤토리](./aws-resource-inventory-before-cleanup.md)

## 삭제 완료

- Route 53 Hosted Zone: `caffeinism.cloud.`
- CloudFront Distribution: `E1FTCFDD8KX5Q0`
- WAF Web ACL: `kosa-tickets-waf`
- ACM Certificate: `ticket.caffeinism.cloud` (`ap-northeast-2`, `us-east-1`)
- EKS Cluster: `kosa-eks`
- EKS NodeGroup: `bootstrap`
- CloudFormation Stack: `eksctl-kosa-eks-nodegroup-bootstrap`
- CloudFormation Stack: `Karpenter-kosa-eks`
- CloudFormation Stack: `eksctl-kosa-eks-addon-iamserviceaccount-kube-system-karpenter`
- CloudFormation Stack:
  `eksctl-kosa-eks-addon-iamserviceaccount-kube-system-aws-load-balancer-controller`
- Network Load Balancer: `kosa-tickets-nlb-prod`
- Network Load Balancer: `a75084df64ab34546a4792aea8bdba5b`
- Target Group: `kosa-tickets-tg-haproxy`
- Target Group: `k8s-kosatick-ticketap-e9adcb8343`
- RDS DB Instance: `kosa-rds-replica`
- RDS DB Subnet Group: `kosa-db-subnet-group`
- EC2 Instance: `i-02cc81735edde9628`, `i-074e8b52490d213b7`, `i-05ba392eda8fd7659`
- EKS Node EC2: `i-03e24805e99d88b32`, `i-083ef00deddd7a605`
- EBS Volume: 전체 삭제 확인
- EBS Snapshot: 없음 확인
- VPC: `vpc-03859601c1dd5b658`
- Subnet 4개
- Route Table 3개
- Security Group: `sg-02d21ec5725ed5581`, `sg-0af7d67eaa3587868`
- Internet Gateway: `igw-01db341ff4ac9fe52`
- NAT Gateway: `nat-06228d0a2634bda13`, `nat-0639891e22679e62b`
- Elastic IP: `eipalloc-0e195a049df0c2c33`, `eipalloc-00d1d6ee0b792950f`
- S3 Gateway Endpoint: `vpce-08882f170c9306e62`
- VPN Connection: `vpn-0906e8a06bb85a041`
- Virtual Private Gateway: `vgw-0f14a420ce5d30261`
- Customer Gateway: `cgw-0923e106392116cfc`
- ECR Repository: `kosa-tickets`, `library/kosa-tickets`
- Lambda Function: `burst-trigger`
- Lambda Function URL: `nzmq63ye7lcgcsdicg6tkflqfy0eezca`
- API Gateway HTTP API: `burst-api`
- CloudWatch Alarm: `kosa-Lambda-Errors`, `kosa-NLB-SlowResponse`, `kosa-NLB-UnHealthy`
- CloudWatch Log Group: `/aws/apigateway/burst-api`, `/aws/eks/kosa-eks/cluster`,
  `/aws/lambda/burst-trigger`
- SNS Topic: `kosa-tickets-alerts`
- S3 Bucket: `employee-photo-bucket-kosa-12`, `team2-app-objects-backup`, `team2-etcd-backup`
- EC2 Key Pair: `kosa-aws-key`
- IAM OIDC Provider: EKS OIDC Provider
- IAM Local Policy: `AWSLoadBalancerControllerIAMPolicy`, `cert-manager-route53`
- IAM Role: 프로젝트용 일반 Role 전체 삭제
- IAM User: `cert-manager`
- Resource Explorer View/Index

## 삭제 검증

| 항목                                      | 결과 |
| :---------------------------------------- | :--- |
| 실행/중지 EC2                             | 0    |
| EBS Volume                                | 0    |
| EBS Snapshot                              | 0    |
| VPC                                       | 0    |
| NAT Gateway                               | 0    |
| Elastic IP                                | 0    |
| ELBv2                                     | 0    |
| EKS                                       | 0    |
| RDS Instance                              | 0    |
| RDS Automated Backup                      | 0    |
| ECR Repository                            | 0    |
| Lambda                                    | 0    |
| API Gateway v2                            | 0    |
| CloudFormation 활성 Stack                 | 0    |
| CloudWatch Log Group                      | 0    |
| SNS Topic                                 | 0    |
| S3 Bucket                                 | 0    |
| Route 53 Hosted Zone                      | 0    |
| WAF CloudFront Web ACL                    | 0    |
| ACM Certificate(ap-northeast-2/us-east-1) | 0    |
| IAM Local Policy                          | 0    |
| IAM OIDC Provider                         | 0    |

## 보존 항목

- IAM 사람 계정: `admin`, `jaehyung`, `minjicha03`, `parkpark131`, `sjkim`
- AWS Service Linked Role: AWS 관리용 기본 역할
- Athena WorkGroup: `primary`
- X-Ray Sampling Rule: `Default`
- 종료된 EC2 기록: AWS 콘솔/API에 임시 표시 가능, 과금 대상 아님

## 후속 확인

- Billing > Bills: 다음 청구 주기 반영 확인
- Cost Explorer: NAT Gateway, EC2, EKS, RDS, CloudFront 비용 감소 확인
- 가비아: `caffeinism.cloud` 네임서버 위임 상태 별도 정리
