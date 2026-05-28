# AWS 삭제 전 리소스 인벤토리

> Status: Unverified

## 기준

- 작성일: 2026-05-28
- 조회 계정: `357737841289`
- 조회 주체: `arn:aws:iam::357737841289:user/sjkim`
- 기본 리전: `ap-northeast-2`
- 조회 방식: AWS CLI 읽기 전용 API
- 임시 옵션: `--no-verify-ssl`
- 제외 정보: Secrets Manager 값, SSM Parameter 값, Lambda 환경변수, S3 객체 목록
- 삭제 실행: 미수행

## 전체 요약

- 실제 리소스 집중 리전: `ap-northeast-2`
- 추가 전역 리소스: S3, Route 53, CloudFront, IAM, WAF
- 추가 글로벌 인증서 리전: `us-east-1`
- 핵심 유료 리소스: EC2 5개, NAT Gateway 2개, NLB 2개, RDS 1개, EKS 1개, Lambda 1개
- 다른 활성 리전 주요 유료 리소스: 없음

| Region               | EC2 | NAT | EIP | ELBv2 | EKS | RDS | ECR | Lambda |
| :------------------- | --: | --: | --: | ----: | --: | --: | --: | -----: |
| ap-northeast-2       |   5 |   2 |   2 |     2 |   1 |   1 |   2 |      1 |
| 그 외 활성 리전 16개 |   0 |   0 |   0 |     0 |   0 |   0 |   0 |      0 |

## 전역 리소스

- S3 Bucket: 3개
- Route 53 Hosted Zone: 1개
- CloudFront Distribution: 1개
- WAF Web ACL: 1개
- IAM User: 6개
- IAM Role: 21개
- IAM Local Policy: 3개
- IAM OIDC Provider: 1개

## S3

| Bucket                          | Region           | Versioning | Encryption | Public Access Block | Lifecycle                                                                                                                          |
| :------------------------------ | :--------------- | :--------- | :--------- | :------------------ | :--------------------------------------------------------------------------------------------------------------------------------- |
| `employee-photo-bucket-kosa-12` | `ap-northeast-2` | Disabled   | AES256     | 일부 해제           | `demo-short-glacier-test`, `abort-incomplete-multipart-test`                                                                       |
| `team2-app-objects-backup`      | `ap-northeast-2` | Enabled    | AES256     | 전체 차단           | 없음                                                                                                                               |
| `team2-etcd-backup`             | `ap-northeast-2` | Enabled    | AES256     | 전체 차단           | `expire-daily-etcd-snapshots`, `archive-weekly-etcd-snapshots`, `archive-manual-etcd-snapshots`, `abort-incomplete-multipart-etcd` |

## Route 53

- Hosted Zone: `caffeinism.cloud.`
- Hosted Zone ID: `Z00161011JCXQGT2WY9CI`
- Zone 유형: Public
- Record 수: 5개

| Name                                                         | Type    | Value                                                                                              |
| :----------------------------------------------------------- | :------ | :------------------------------------------------------------------------------------------------- |
| `caffeinism.cloud.`                                          | NS      | `ns-1533.awsdns-63.org`, `ns-1761.awsdns-28.co.uk`, `ns-444.awsdns-55.com`, `ns-847.awsdns-41.net` |
| `caffeinism.cloud.`                                          | SOA     | AWS 기본 SOA                                                                                       |
| `pxc.caffeinism.cloud.`                                      | A       | `172.16.23.55`                                                                                     |
| `ticket.caffeinism.cloud.`                                   | A Alias | `d47cuwh08yagc.cloudfront.net`                                                                     |
| `_aa35cfb6b8f28dc2d1a1e2d64b0f4253.ticket.caffeinism.cloud.` | CNAME   | ACM 검증 레코드                                                                                    |

## CloudFront / WAF / ACM

- CloudFront ID: `E1FTCFDD8KX5Q0`
- CloudFront 도메인: `d47cuwh08yagc.cloudfront.net`
- Alias: `ticket.caffeinism.cloud`
- Origin: `kosa-tickets-nlb-prod-7405a2e027cc2a49.elb.ap-northeast-2.amazonaws.com`
- Viewer 정책: HTTP -> HTTPS Redirect
- 허용 메서드: `GET`, `HEAD`, `OPTIONS`, `PUT`, `POST`, `PATCH`, `DELETE`
- Price Class: `PriceClass_200`
- WAF Web ACL: `kosa-tickets-waf`
- WAF 규칙: `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesSQLiRuleSet`,
  `AWSManagedRulesAmazonIpReputationList`
- ACM 인증서(ap-northeast-2): `ticket.caffeinism.cloud`, `ISSUED`
- ACM 인증서(us-east-1): `ticket.caffeinism.cloud`, `ISSUED`, CloudFront 연결

## VPC

- VPC ID: `vpc-03859601c1dd5b658`
- Name: `kosa-tickets-vpc`
- CIDR: `10.20.0.0/16`
- Default VPC: false
- Internet Gateway: `igw-01db341ff4ac9fe52`, `kosa-tickets-igw`
- S3 Gateway Endpoint: `vpce-08882f170c9306e62`

| Subnet                     | Name                                           | AZ                | CIDR            | 역할                         |
| :------------------------- | :--------------------------------------------- | :---------------- | :-------------- | :--------------------------- |
| `subnet-0452b79f9e98f8473` | `kosa-tickets-subnet-public1-ap-northeast-2a`  | `ap-northeast-2a` | `10.20.1.0/24`  | Public                       |
| `subnet-03bd9bd5ccb3773fb` | `kosa-tickets-subnet-public2-ap-northeast-2c`  | `ap-northeast-2c` | `10.20.2.0/24`  | Public                       |
| `subnet-0ba906a51746b475b` | `kosa-tickets-subnet-private1-ap-northeast-2a` | `ap-northeast-2a` | `10.20.10.0/24` | Private, Karpenter discovery |
| `subnet-02542285c79d0d41c` | `kosa-tickets-subnet-private2-ap-northeast-2c` | `ap-northeast-2c` | `10.20.11.0/24` | Private, Karpenter discovery |

## Route Table

| Route Table             | Name                                        | Association                | 주요 경로                                                                                   |
| :---------------------- | :------------------------------------------ | :------------------------- | :------------------------------------------------------------------------------------------ |
| `rtb-02ced579687efa892` | `kosa-tickets-rtb-public`                   | public 2개                 | `0.0.0.0/0 -> igw-01db341ff4ac9fe52`, `172.16.0.0/12 -> vgw-0f14a420ce5d30261`              |
| `rtb-028ff8167d2c85cb7` | `kosa-tickets-rtb-private1-ap-northeast-2a` | `subnet-0ba906a51746b475b` | `0.0.0.0/0 -> nat-06228d0a2634bda13`, `172.16.0.0/12 -> vgw-0f14a420ce5d30261`, S3 Endpoint |
| `rtb-02a4ba4423ef11f3d` | `kosa-tickets-rtb-private2-ap-northeast-2c` | `subnet-02542285c79d0d41c` | `0.0.0.0/0 -> nat-0639891e22679e62b`, `172.16.0.0/12 -> vgw-0f14a420ce5d30261`, S3 Endpoint |
| `rtb-03f82c1d10f0e4ef4` | 미지정                                      | 없음                       | local                                                                                       |

## NAT / EIP

| NAT Gateway             | Name                                       | Subnet                     | Public IP       | Allocation ID                |
| :---------------------- | :----------------------------------------- | :------------------------- | :-------------- | :--------------------------- |
| `nat-06228d0a2634bda13` | `kosa-tickets-nat-public1-ap-northeast-2a` | `subnet-0452b79f9e98f8473` | `52.78.66.44`   | `eipalloc-0e195a049df0c2c33` |
| `nat-0639891e22679e62b` | `kosa-tickets-nat-public2-ap-northeast-2c` | `subnet-03bd9bd5ccb3773fb` | `13.125.89.218` | `eipalloc-00d1d6ee0b792950f` |

## VPN

- Virtual Private Gateway: `vgw-0f14a420ce5d30261`, `kosa-aws-vgw`, ASN `64512`
- Customer Gateway: `cgw-0923e106392116cfc`, `kosa-onprem-cgw`, ASN `65000`, IP `125.131.208.229`
- VPN Connection: `vpn-0906e8a06bb85a041`, `kosa-vpn-connection`
- VPN 유형: `ipsec.1`
- 라우팅 방식: Static
- 온프레 경로: `172.16.0.0/12`
- Tunnel 상태: `43.200.200.229 DOWN`, `54.116.133.94 UP`
- Transit Gateway: 없음

## Security Group

| Security Group         | Name                                | 용도             | Ingress 요약                                           |
| :--------------------- | :---------------------------------- | :--------------- | :----------------------------------------------------- |
| `sg-01474a20a66f64cb8` | default                             | 기본 SG          | 자기 자신 전체                                         |
| `sg-0ac7c0b6260185d10` | `eks-cluster-sg-kosa-eks-614180594` | EKS Cluster/Node | 자기 자신 전체, VPC 8000, NLB NodePort 32492, ICMP MTU |
| `sg-02d21ec5725ed5581` | `kosa-rds-sg`                       | RDS MySQL        | `172.16.0.0/12:3306`, `10.20.0.0/16:3306`              |
| `sg-0af7d67eaa3587868` | `kosa-tickets-haproxy-sg`           | HAProxy          | `10.20.0.0/16:80`                                      |

## EC2 / EBS

| Instance              | Name                      | Type       | State   | Subnet                     | Private IP     | 역할                 |
| :-------------------- | :------------------------ | :--------- | :------ | :------------------------- | :------------- | :------------------- |
| `i-03e24805e99d88b32` | `kosa-eks-bootstrap-Node` | `t3.small` | running | `subnet-0ba906a51746b475b` | `10.20.10.48`  | EKS Node             |
| `i-083ef00deddd7a605` | `kosa-eks-bootstrap-Node` | `t3.small` | running | `subnet-02542285c79d0d41c` | `10.20.11.44`  | EKS Node             |
| `i-05ba392eda8fd7659` | `kosa-tickets-haproxy-1c` | `t3.micro` | running | `subnet-0ba906a51746b475b` | `10.20.10.65`  | HAProxy              |
| `i-02cc81735edde9628` | `kosa-tickets-haproxy-1a` | `t3.micro` | running | `subnet-02542285c79d0d41c` | `10.20.11.21`  | HAProxy, NLB Target  |
| `i-074e8b52490d213b7` | `kosa-tickets-haproxy`    | `t3.micro` | running | `subnet-02542285c79d0d41c` | `10.20.11.107` | HAProxy, 미등록 후보 |

- EBS Volume: 5개
- EBS Snapshot: 없음
- EC2 Key Pair: `kosa-aws-key`
- EC2 Fleet / Spot Fleet: 없음

| Volume                  | Size | Type | AZ                | Attachment                      |
| :---------------------- | ---: | :--- | :---------------- | :------------------------------ |
| `vol-07afbe252581d456b` |   80 | gp3  | `ap-northeast-2a` | `i-03e24805e99d88b32:/dev/xvda` |
| `vol-0008a08a8c23df313` |   80 | gp3  | `ap-northeast-2c` | `i-083ef00deddd7a605:/dev/xvda` |
| `vol-09c1b451907e08662` |    8 | gp3  | `ap-northeast-2a` | `i-05ba392eda8fd7659:/dev/sda1` |
| `vol-080a6ff74a92eecc8` |    8 | gp3  | `ap-northeast-2c` | `i-02cc81735edde9628:/dev/sda1` |
| `vol-07a7af81bbfd235f3` |    8 | gp3  | `ap-northeast-2c` | `i-074e8b52490d213b7:/dev/sda1` |

## Load Balancer

| NLB                                | DNS                                                                                  | Listener            | Target Group                       | Target                                                                   |
| :--------------------------------- | :----------------------------------------------------------------------------------- | :------------------ | :--------------------------------- | :----------------------------------------------------------------------- |
| `kosa-tickets-nlb-prod`            | `kosa-tickets-nlb-prod-7405a2e027cc2a49.elb.ap-northeast-2.amazonaws.com`            | `80/TCP`, `443/TLS` | `kosa-tickets-tg-haproxy`          | `10.20.11.21:80 healthy`, `10.20.10.65:80 healthy`                       |
| `a75084df64ab34546a4792aea8bdba5b` | `a75084df64ab34546a4792aea8bdba5b-aa4a9d214197da04.elb.ap-northeast-2.amazonaws.com` | `80/TCP`            | `k8s-kosatick-ticketap-e9adcb8343` | `i-03e24805e99d88b32:32492 healthy`, `i-083ef00deddd7a605:32492 healthy` |

- Classic ELB: 없음
- Kubernetes NLB 태그: `kubernetes.io/service-name=kosa-tickets/ticket-app`

## EKS

- Cluster: `kosa-eks`
- Status: `ACTIVE`
- Version: `1.35`
- Endpoint Public Access: true
- Endpoint Private Access: true
- Public Access CIDR: `0.0.0.0/0`
- VPC: `vpc-03859601c1dd5b658`
- Subnet: `subnet-02542285c79d0d41c`, `subnet-0ba906a51746b475b`
- Cluster SG: `sg-0ac7c0b6260185d10`
- OIDC Issuer: `https://oidc.eks.ap-northeast-2.amazonaws.com/id/A32DEDB415CE478F6DBBCDA49E8D46DD`
- Logging: api, audit, authenticator, controllerManager, scheduler
- Addon: coredns, kube-proxy, metrics-server, vpc-cni

### NodeGroup

- NodeGroup: `bootstrap`
- Status: `ACTIVE`
- Version: `1.35`
- AMI Type: `AL2023_x86_64_STANDARD`
- Capacity Type: `ON_DEMAND`
- Instance Type: `t3.small`
- Scaling: min 1, desired 2, max 2
- Node Role: `eksctl-kosa-eks-nodegroup-bootstra-NodeInstanceRole-h5O38Zdg4qbB`
- Auto Scaling Group: `eks-bootstrap-92cf1fb4-ba10-190f-34a0-14df4decca59`
- Launch Template: `lt-036036804bc9ef8ad`, `lt-0ea565a93c76c134d`

## RDS

- DB Instance: `kosa-rds-replica`
- Engine: MySQL `8.0.44`
- Class: `db.t3.micro`
- Status: available
- Endpoint: `kosa-rds-replica.cf88aaksmeg8.ap-northeast-2.rds.amazonaws.com:3306`
- Storage: 20 GiB, gp3, encrypted
- Multi-AZ: false
- Public Access: false
- Backup Retention: 1일
- Automated Backup: active, 20 GiB, 복원 가능 구간 `2026-05-27T02:17:35Z` ~ `2026-05-28T02:17:35Z`
- Deletion Protection: false
- Subnet Group: `kosa-db-subnet-group`
- Security Group: `sg-02d21ec5725ed5581`
- Manual Snapshot: 없음
- DB Cluster: 없음

## ECR

| Repository             | Image Tag                                                                                      |
| :--------------------- | :--------------------------------------------------------------------------------------------- |
| `kosa-tickets`         | `5`                                                                                            |
| `library/kosa-tickets` | `latest`, `4`, `5`, `6`, `7`, `8`, `9`, `10`, `11`, `12`, `13`, `14`, `15`, `20`, untagged 1개 |

## Lambda / API Gateway

- Lambda Function: `burst-trigger`
- Runtime: `python3.12`
- Handler: `lambda_function.lambda_handler`
- Role: `BurstLambdaRole`
- Memory: 128 MiB
- Timeout: 30초
- Function URL: `https://nzmq63ye7lcgcsdicg6tkflqfy0eezca.lambda-url.ap-northeast-2.on.aws/`
- Function URL Auth: `NONE`
- HTTP API: `burst-api`
- API ID: `le24sqo79b`
- API Endpoint: `https://le24sqo79b.execute-api.ap-northeast-2.amazonaws.com`
- Route: `$default`
- Integration: AWS_PROXY -> `burst-trigger`
- Stage: `$default`, Auto Deploy true
- EventBridge Scheduler: 없음
- EventBridge Rule: Karpenter 관리 Rule 4개, AWS 관리 Rule 2개

## CloudWatch / Logs / SNS / SQS

- Alarm: `kosa-Lambda-Errors`, `kosa-NLB-SlowResponse`, `kosa-NLB-UnHealthy`
- Log Group: `/aws/apigateway/burst-api`
- Log Group: `/aws/eks/kosa-eks/cluster`
- Log Group: `/aws/lambda/burst-trigger`
- SNS Topic: `arn:aws:sns:ap-northeast-2:357737841289:kosa-tickets-alerts`
- SQS Queue: `https://sqs.ap-northeast-2.amazonaws.com/357737841289/kosa-eks`

## CloudFormation / Karpenter

- Stack: `eksctl-kosa-eks-nodegroup-bootstrap`
- Stack: `Karpenter-kosa-eks`
- Stack: `eksctl-kosa-eks-addon-iamserviceaccount-kube-system-karpenter`
- Stack: `eksctl-kosa-eks-addon-iamserviceaccount-kube-system-aws-load-balancer-controller`
- Karpenter Controller Role: `KarpenterControllerRole-kosa-eks`
- Karpenter Node Role: `KarpenterNodeRole-kosa-eks`
- Karpenter SQS Queue: `kosa-eks`
- Karpenter EventBridge Rules: InstanceStateChange, Rebalance, ScheduledChange, SpotInterruption

## IAM

### User

- `admin`
- `cert-manager`
- `jaehyung`
- `minjicha03`
- `parkpark131`
- `sjkim`

### 주요 Role

- `AmazonEKSLoadBalancerControllerRole`
- `BurstLambdaRole`
- `eksClusterRole`
- `eksNodeRole`
- `eksctl-kosa-eks-nodegroup-bootstra-NodeInstanceRole-h5O38Zdg4qbB`
- `KarpenterControllerRole-kosa-eks`
- `KarpenterNodeRole-kosa-eks`
- `Kosa_Team2_TerraformRole`
- `AmazonSSMRoleForInstancesQuickSetup`
- `EmployeeWebApp`
- `S3DynamoDBFullAccessRole`
- AWS Service Linked Role 다수

### Local Policy

- `KarpenterControllerPolicy-kosa-eks`
- `AWSLoadBalancerControllerIAMPolicy`
- `cert-manager-route53`

### OIDC Provider

- `arn:aws:iam::357737841289:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/A32DEDB415CE478F6DBBCDA49E8D46DD`

## 미사용 또는 기본 리소스

- DynamoDB Table: 없음
- Secrets Manager Secret: 없음
- SSM Parameter: 없음
- ECS Cluster: 없음
- ElastiCache Cluster: 없음
- RDS Cluster: 없음
- Transit Gateway: 없음
- Classic ELB: 없음
- EC2 Snapshot: 없음
- Athena WorkGroup: `primary`
- KMS Alias: AWS 관리형 alias만 확인
- X-Ray Sampling Rule: `Default`
- Resource Explorer View/Index: 존재

## 삭제 의존성

- CloudFront -> WAF/ACM/Route 53/NLB 의존
- Route 53 `ticket.caffeinism.cloud` -> CloudFront 의존
- Kubernetes Service NLB -> EKS Service 의존
- EKS NodeGroup -> EC2, EBS, ASG, Launch Template 의존
- Karpenter Stack -> SQS, EventBridge Rule, IAM Role/Policy 의존
- RDS -> DB Subnet Group, RDS SG, Private Subnet 의존
- NAT Gateway -> EIP, Public Subnet 의존
- VPN -> CGW, VGW, Route Table Propagation 의존
- VPC -> Subnet, ENI, SG, Route Table, IGW, NAT, Endpoint, VPN 의존

## 재현 기준

- AWS 리전: `ap-northeast-2`
- VPC CIDR: `10.20.0.0/16`
- Public Subnet: `10.20.1.0/24`, `10.20.2.0/24`
- Private Subnet: `10.20.10.0/24`, `10.20.11.0/24`
- 온프레 CIDR: `172.16.0.0/12`
- 도메인: `caffeinism.cloud`
- 서비스 FQDN: `ticket.caffeinism.cloud`
- PXC DNS: `pxc.caffeinism.cloud -> 172.16.23.55`
- Terraform 참조: `docs/architecture/build-up/cloud_network_iac/aws-hybrid-terraform/`

## 삭제 전 확인

- ECR 이미지 보존 필요 여부 확인
- S3 객체 백업 필요 여부 확인
- RDS 최종 스냅샷 필요 여부 확인
- Route 53 도메인 재사용 여부 확인
- IAM 사용자/Access Key 삭제 범위 확인
- CloudFormation/eksctl 관리 리소스 삭제 순서 확인
- Kubernetes Service 삭제 후 AWS NLB 자동 삭제 여부 확인
- NAT Gateway, EIP 잔존 여부 최종 확인
