# AWS Terraform VPC 테스트 정리

대상 경로: `/home/ubuntu/infra-platform/terraform/aws`

목적: bastion 서버에서 Terraform으로 AWS 계정 연결을 검증하고, 테스트용 VPC/Subnet/Route Table을 생성한 뒤 Terraform state 기준으로 생성 리소스만 삭제 가능한지 확인.

## 1. 통신 테스트 가능 시점

현재 AWS 확장 단계:

```text
1. AWS 기본 계정/IAM/Terraform 준비
2. VPC/Subnet/Route Table 구성
3. 온프레미스 ↔ AWS VPN 연결
4. DNS / Routing / 보안그룹 정리
5. AWS 내부 접근용 Endpoint 구성
6. EKS 클러스터 구성
7. Argo CD multi-cluster 연결
8. 앱 배포 테스트
9. RDS / S3 / ECR 등 AWS 서비스 연동
10. 모니터링 / 장애 테스트 / 비용 최적화
```

정리:

- bastion에서 AWS private IP로 `ping`, `ssh` 테스트하려면 최소 3번 VPN 연결 필요.
- 2번 VPC/Subnet/Route Table 구성만으로는 bastion과 AWS VPC 사이 통신 경로 없음.
- 현재 생성된 `10.50.0.0/16` route의 `local` 의미는 AWS VPC 내부 통신용.
- VPN 전 통신 테스트는 Public Subnet에 EC2를 만들고 Public IP로 접근하는 방식만 가능.

## 2. Terraform 설치 및 AWS 계정 연결 검증

작업 내용:

- AWS CLI profile `jaehyung` 사용.
- AWS 계정 ID `357737841289` 확인.
- Terraform 설치 후 AWS provider 초기화.
- Terraform이 bastion에 저장된 AWS profile로 실제 AWS 계정을 읽는지 검증.

주요 명령어:

```bash
# AWS profile 인증 확인
aws sts get-caller-identity --profile jaehyung

# Terraform 디렉토리 이동
cd /home/ubuntu/infra-platform/terraform/aws

# Terraform 초기화
terraform init

# Terraform 코드 문법 검증
terraform validate

# 실제 리소스 생성 없이 AWS 계정 연결 확인
terraform plan

# 계정 정보 output을 state에 저장
terraform apply

# 저장된 output 확인
terraform output
```

확인 결과:

```text
account_id     = "357737841289"
caller_arn     = "arn:aws:iam::357737841289:user/jaehyung"
current_region = "ap-northeast-2"
```

의미:

- bastion 서버의 AWS profile과 실제 AWS 계정 연결 정상.
- Terraform AWS provider 인증 정상.
- 이 단계에서는 실제 AWS 인프라 리소스 생성 없음.

## 3. VPC/Subnet/Route Table Terraform 구성

작업 파일:

```text
terraform/aws/
├── main.tf
├── outputs.tf
├── provider.tf
├── variables.tf
├── versions.tf
└── vpc.tf
```

구성 대상:

```text
VPC CIDR: 10.50.0.0/16

Public Subnet:
- 10.50.10.0/24
- 10.50.11.0/24

Private App Subnet:
- 10.50.20.0/24
- 10.50.21.0/24

Private DB Subnet:
- 10.50.30.0/24
- 10.50.31.0/24
```

검증 명령어:

```bash
# Terraform 코드 포맷 정리
terraform fmt

# 문법 검증
terraform validate

# 생성될 AWS 리소스 확인
terraform plan
```

plan 결과:

```text
Plan: 18 to add, 0 to change, 0 to destroy.
```

의미:

- 신규 리소스 18개 생성 예정.
- 기존 AWS 리소스 변경 없음.
- 기존 AWS 리소스 삭제 없음.

## 4. 생성 계획 저장 및 적용

생성 계획 저장:

```bash
# 생성 계획을 파일로 저장
terraform plan -out=tfplan-create
```

생성 적용:

```bash
# 저장된 생성 계획 그대로 적용
terraform apply tfplan-create
```

apply 결과:

```text
Apply complete! Resources: 18 added, 0 changed, 0 destroyed.
```

생성 리소스:

```text
VPC:
- vpc-051a385fb9fa65e72
- CIDR: 10.50.0.0/16

Internet Gateway:
- igw-00b351828266ad982

Public Subnet:
- subnet-074b426ccb18005d1
- subnet-0a1caf01412c35863

Private App Subnet:
- subnet-0dc0ad023b3de3394
- subnet-0beb523780b207298

Private DB Subnet:
- subnet-0f8de6defce030bff
- subnet-02e2321ef3f71c507

Public Route Table:
- rtb-0f5f09832c38a3cdf

Private App Route Table:
- rtb-0ce5053990baddd10

Private DB Route Table:
- rtb-0a1b2725b7a571012
```

중요 확인:

- `18 added`: Terraform 신규 생성.
- `0 changed`: 기존 리소스 변경 없음.
- `0 destroyed`: 기존 리소스 삭제 없음.

## 5. Terraform state 확인

명령어:

```bash
# Terraform이 관리 중인 리소스 목록 확인
terraform state list
```

출력 요약:

```text
data.aws_availability_zones.available
data.aws_caller_identity.current
data.aws_region.current
aws_internet_gateway.main
aws_route.public_internet
aws_route_table.private_app
aws_route_table.private_db
aws_route_table.public
aws_route_table_association.private_app[0]
aws_route_table_association.private_app[1]
aws_route_table_association.private_db[0]
aws_route_table_association.private_db[1]
aws_route_table_association.public[0]
aws_route_table_association.public[1]
aws_subnet.private_app[0]
aws_subnet.private_app[1]
aws_subnet.private_db[0]
aws_subnet.private_db[1]
aws_subnet.public[0]
aws_subnet.public[1]
aws_vpc.main
```

정리:

- `data.*` 3개는 조회용 data source.
- 실제 생성 리소스는 `aws_*` 18개.
- `terraform destroy`는 이 state에 있는 생성 리소스만 삭제 대상.
- 기존 AWS Console에 있던 다른 VPC/Subnet/Route Table은 state에 없으므로 삭제 대상 아님.

## 6. AWS CLI로 생성 결과 확인

VPC 확인:

```bash
aws ec2 describe-vpcs \
  --profile jaehyung \
  --vpc-ids vpc-051a385fb9fa65e72 \
  --query 'Vpcs[*].{VpcId:VpcId,CidrBlock:CidrBlock,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

확인 결과:

```text
VpcId:     vpc-051a385fb9fa65e72
CidrBlock: 10.50.0.0/16
Name:      kosa-team2-hybrid-vpc
```

Subnet 확인:

```bash
aws ec2 describe-subnets \
  --profile jaehyung \
  --filters "Name=vpc-id,Values=vpc-051a385fb9fa65e72" \
  --query 'Subnets[*].{SubnetId:SubnetId,CidrBlock:CidrBlock,AZ:AvailabilityZone,PublicIP:MapPublicIpOnLaunch,Name:Tags[?Key==`Name`]|[0].Value,Tier:Tags[?Key==`Tier`]|[0].Value}' \
  --output table
```

확인 결과:

```text
10.50.10.0/24  ap-northeast-2a  public       PublicIP=True
10.50.11.0/24  ap-northeast-2b  public       PublicIP=True
10.50.20.0/24  ap-northeast-2a  private-app  PublicIP=False
10.50.21.0/24  ap-northeast-2b  private-app  PublicIP=False
10.50.30.0/24  ap-northeast-2a  private-db   PublicIP=False
10.50.31.0/24  ap-northeast-2b  private-db   PublicIP=False
```

Internet Gateway 확인:

```bash
aws ec2 describe-internet-gateways \
  --profile jaehyung \
  --filters "Name=attachment.vpc-id,Values=vpc-051a385fb9fa65e72" \
  --query 'InternetGateways[*].{IgwId:InternetGatewayId,State:Attachments[0].State,Name:Tags[?Key==`Name`]|[0].Value}' \
  --output table
```

확인 결과:

```text
IgwId: igw-00b351828266ad982
Name:  kosa-team2-hybrid-igw
State: available
```

Route Table 확인:

```bash
aws ec2 describe-route-tables \
  --profile jaehyung \
  --filters "Name=vpc-id,Values=vpc-051a385fb9fa65e72" \
  --query 'RouteTables[*].{RouteTableId:RouteTableId,Name:Tags[?Key==`Name`]|[0].Value,Routes:Routes[*].DestinationCidrBlock}' \
  --output table
```

확인 결과:

```text
Private DB Route Table:
- 10.50.0.0/16

Private App Route Table:
- 10.50.0.0/16

Public Route Table:
- 10.50.0.0/16
- 0.0.0.0/0

Default Main Route Table:
- 10.50.0.0/16
```

Public Route Table 인터넷 경로 확인:

```bash
aws ec2 describe-route-tables \
  --profile jaehyung \
  --route-table-ids rtb-0f5f09832c38a3cdf \
  --query 'RouteTables[0].Routes[*].{Destination:DestinationCidrBlock,GatewayId:GatewayId,State:State}' \
  --output table
```

확인 결과:

```text
10.50.0.0/16  local                   active
0.0.0.0/0     igw-00b351828266ad982   active
```

Private App Route Table 확인:

```bash
aws ec2 describe-route-tables \
  --profile jaehyung \
  --route-table-ids rtb-0ce5053990baddd10 \
  --query 'RouteTables[0].Routes[*].{Destination:DestinationCidrBlock,GatewayId:GatewayId,State:State}' \
  --output table
```

확인 결과:

```text
10.50.0.0/16  local  active
```

Private DB Route Table 확인:

```bash
aws ec2 describe-route-tables \
  --profile jaehyung \
  --route-table-ids rtb-0a1b2725b7a571012 \
  --query 'RouteTables[0].Routes[*].{Destination:DestinationCidrBlock,GatewayId:GatewayId,State:State}' \
  --output table
```

확인 결과:

```text
10.50.0.0/16  local  active
```

## 7. 삭제 계획 확인

기존 AWS 리소스를 보호하기 위해 바로 삭제하지 않고 destroy plan 먼저 확인.

명령어:

```bash
terraform plan -destroy
```

확인 결과:

```text
Plan: 0 to add, 0 to change, 18 to destroy.
```

삭제 대상:

- `vpc-051a385fb9fa65e72`
- `igw-00b351828266ad982`
- Terraform으로 생성한 subnet 6개
- Terraform으로 생성한 route table 3개
- Terraform으로 생성한 route 및 route table association

중요:

- 삭제 계획에 기존 AWS 리소스 없음.
- Terraform state에 있는 `aws_*` 리소스 18개만 삭제 대상.
- `data.*` 항목은 조회용이라 삭제 대상 아님.

## 8. 삭제 실행 가이드

삭제 계획 생성 결과:

```text
Plan: 0 to add, 0 to change, 18 to destroy.
Saved the plan to: tfplan-destroy
```

삭제 계획 저장:

```bash
# 삭제 계획을 파일로 저장
terraform plan -destroy -out=tfplan-destroy
```

삭제 적용:

```bash
# 저장된 삭제 계획 그대로 실행
terraform apply tfplan-destroy
```

실행 결과:

```text
Apply complete! Resources: 0 added, 0 changed, 18 destroyed.
```

삭제된 리소스:

```text
aws_route_table_association.public[0]
aws_route_table_association.public[1]
aws_route_table_association.private_app[0]
aws_route_table_association.private_app[1]
aws_route_table_association.private_db[0]
aws_route_table_association.private_db[1]
aws_route.public_internet
aws_route_table.public
aws_route_table.private_app
aws_route_table.private_db
aws_internet_gateway.main
aws_subnet.public[0]
aws_subnet.public[1]
aws_subnet.private_app[0]
aws_subnet.private_app[1]
aws_subnet.private_db[0]
aws_subnet.private_db[1]
aws_vpc.main
```

삭제 후 확인:

```bash
# Terraform state에 남은 리소스 확인
terraform state list

# 삭제된 VPC 조회
aws ec2 describe-vpcs \
  --profile jaehyung \
  --vpc-ids vpc-051a385fb9fa65e72
```

삭제 확인 결과:

```text
terraform state list
```

출력 없음. Terraform state에 관리 중인 `aws_*` 리소스 없음.

```text
An error occurred (InvalidVpcID.NotFound) when calling the DescribeVpcs operation:
The vpc ID 'vpc-051a385fb9fa65e72' does not exist
```

정리:

- Terraform으로 생성한 VPC 삭제 완료.
- 관련 Subnet, Route Table, Internet Gateway, Association 삭제 완료.
- Terraform state 비어 있음.
- AWS CLI에서 VPC 조회 시 `InvalidVpcID.NotFound` 발생.
- 기존 AWS 리소스는 Terraform state에 없었으므로 삭제 대상 아님.

## 9. 현재 테스트 결론

정리:

- bastion에서 AWS CLI profile `jaehyung` 인증 성공.
- Terraform 설치 및 AWS provider 초기화 성공.
- Terraform plan으로 AWS 계정 연결 검증 성공.
- Terraform으로 테스트 VPC/Subnet/Route Table 생성 성공.
- 생성 리소스는 Terraform state에 정상 기록.
- AWS Console 및 AWS CLI로 생성 상태 확인 완료.
- destroy plan 결과 `18 to destroy` 확인.
- `terraform apply tfplan-destroy`로 생성 리소스 18개 삭제 완료.
- 삭제 후 `terraform state list` 출력 없음.
- 삭제 후 VPC 조회 결과 `InvalidVpcID.NotFound` 확인.
- 기존 AWS 리소스는 Terraform state에 없으므로 삭제 대상 아님.

## 10. 다음 단계

다음 작업:

```text
3. 온프레미스 ↔ AWS VPN 연결
```

VPN 이후 가능해지는 테스트:

- bastion에서 AWS private subnet EC2로 ping 테스트.
- bastion에서 AWS private subnet EC2로 ssh 테스트.
- AWS EC2에서 온프레미스 대역으로 ping/ssh 테스트.
- Route Table에 온프레미스 CIDR 경로 추가 검증.

필요 정보:

```text
AWS VPC CIDR:
- 10.50.0.0/16

온프레미스 CIDR:
- 172.16.21.0/24
- 172.16.22.0/24
- 172.16.23.0/24
- 172.16.24.0/24
- 10.10.10.0/24
```
