# AWS NLB-EC2-VPN-OnPrem 구성 전 사전 준비 체크리스트

> Status: Unverified

본 문서는 아래 구현 문서의 공통 선행 조건을 정리함.

- CLI: `aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`
- 콘솔: `aws-nlb-ec2-vpn-onprem-haproxyedge-console.md`

자동화 스캐폴드:

- Terraform: `./aws-nlb-ec2-vpn-onprem-automation-draft/terraform/`
- Ansible: `./aws-nlb-ec2-vpn-onprem-automation-draft/ansible/`

값 확인 가이드:

- `aws-nlb-ec2-vpn-onprem-value-discovery-guide.md`

---

## 1. 사전 결정값

| 항목            | 예시 값              | 비고                    |
| :-------------- | :------------------- | :---------------------- |
| AWS Region      | `ap-northeast-2`     | 전체 리소스 동일 리전   |
| 도메인          | `sjkim686.store`     | Route 53 위임 대상      |
| 앱 FQDN         | `api.sjkim686.store` | NLB Alias 연결          |
| VPC CIDR        | `10.30.0.0/16`       | 온프레 CIDR과 중복 금지 |
| Public Subnet A | `10.30.1.0/24`       | AZ-a                    |
| Public Subnet C | `10.30.2.0/24`       | AZ-c                    |
| 온프레 CIDR     | 예: `172.16.20.0/24` | 라우팅 목적지           |
| 관리자 공인 IP  | `x.x.x.x/32`         | SSH 최소 허용           |

---

## 2. AWS 계정/권한

필요 권한(최소):

- EC2, VPC, ELBv2, Route53, CloudWatch
- Site-to-Site VPN(VGW/CGW/VPN connection)
- (대안 경로) EIP/ENI/Route table 수정

---

## 3. Terraform/Ansible 적용 가능 범위

- Terraform 권장 대상
  - VPC/Subnet/IGW/Route table/SG
  - EC2(HAProxy/Relay), EIP
  - NLB/Target Group/Listener
  - VGW/CGW/VPN Connection
  - Route53 Hosted Zone/Alias Record
- Ansible 권장 대상
  - HAProxy 설치/설정/서비스 기동
  - WireGuard 설치/설정/서비스 기동
- 수동 대상
  - 가비아 네임서버 위임
  - pfSense FRR/BGP 설정

스캐폴드 시작:

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
```

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/haproxy.yml
```

## 4. AWS CLI로 가능한 범위/불가능한 범위

### 3.1 AWS CLI로 가능한 작업

- VPC/Subnet/IGW/Route table 생성 및 연결
- Key pair 생성
- Route 53 Hosted Zone 생성 및 NS 조회
- (후속 단계) NLB/VPN 리소스 생성

### 3.2 AWS CLI로 불가능(또는 AWS 외부) 작업

- 가비아 네임서버 변경
- 온프레 방화벽 포트 오픈
- pfSense FRR/BGP 지원 확인 및 설정

---

## 5. VPC 기본 구성 (AWS CLI)

## 4.1 환경변수 선언

```bash
export AWS_REGION=ap-northeast-2
export VPC_NAME=vpc-hybrid-edge
export VPC_CIDR=10.30.0.0/16
export SUBNET_A_CIDR=10.30.1.0/24
export SUBNET_C_CIDR=10.30.2.0/24
export AZ_A=ap-northeast-2a
export AZ_C=ap-northeast-2c
```

의미:

- 이후 명령에서 반복 입력할 값을 변수로 고정해 오타를 줄임.

## 4.2 VPC 생성

```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block ${VPC_CIDR} \
  --region ${AWS_REGION} \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]" \
  --query 'Vpc.VpcId' --output text)

echo ${VPC_ID}
```

의미:

- CIDR `10.30.0.0/16`로 VPC 생성
- Name 태그 부여
- 생성된 VPC ID를 `VPC_ID` 변수에 저장

DNS 기능 활성화:

```bash
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-support '{"Value":true}' --region ${AWS_REGION}
aws ec2 modify-vpc-attribute --vpc-id ${VPC_ID} --enable-dns-hostnames '{"Value":true}' --region ${AWS_REGION}
```

의미:

- EC2 내부 DNS 해석과 호스트네임 부여 활성화.

## 4.3 Public Subnet 2개 생성

```bash
SUBNET_A_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${SUBNET_A_CIDR} \
  --availability-zone ${AZ_A} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-public-a}]' \
  --query 'Subnet.SubnetId' --output text)

SUBNET_C_ID=$(aws ec2 create-subnet \
  --vpc-id ${VPC_ID} \
  --cidr-block ${SUBNET_C_CIDR} \
  --availability-zone ${AZ_C} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=subnet-public-c}]' \
  --query 'Subnet.SubnetId' --output text)

echo ${SUBNET_A_ID}
echo ${SUBNET_C_ID}
```

의미:

- 서로 다른 AZ에 Public Subnet 2개 생성(고가용성 목적).

Public IP 자동할당 활성화:

```bash
aws ec2 modify-subnet-attribute --subnet-id ${SUBNET_A_ID} --map-public-ip-on-launch --region ${AWS_REGION}
aws ec2 modify-subnet-attribute --subnet-id ${SUBNET_C_ID} --map-public-ip-on-launch --region ${AWS_REGION}
```

의미:

- 해당 Subnet에서 생성되는 EC2에 공인 IP 자동 부여.

## 4.4 Internet Gateway 생성/연결

```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=igw-hybrid-edge}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

echo ${IGW_ID}

aws ec2 attach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID} --region ${AWS_REGION}
```

의미:

- VPC에 인터넷 출구(IGW)를 연결.

## 4.5 Route Table 생성/연결

```bash
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id ${VPC_ID} \
  --region ${AWS_REGION} \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=rtb-public-edge}]' \
  --query 'RouteTable.RouteTableId' --output text)

echo ${RTB_ID}

aws ec2 create-route \
  --route-table-id ${RTB_ID} \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id ${IGW_ID} \
  --region ${AWS_REGION}

aws ec2 associate-route-table --route-table-id ${RTB_ID} --subnet-id ${SUBNET_A_ID} --region ${AWS_REGION}
aws ec2 associate-route-table --route-table-id ${RTB_ID} --subnet-id ${SUBNET_C_ID} --region ${AWS_REGION}
```

의미:

- Public Route Table 생성
- 기본 라우트(0.0.0.0/0)를 IGW로 설정
- 두 Public Subnet에 연결.

---

## 6. 키페어/접속 준비 (AWS CLI)

키페어 생성(신규):

```bash
aws ec2 create-key-pair \
  --key-name kp-haproxy-edge \
  --query 'KeyMaterial' \
  --output text > kp-haproxy-edge.pem

chmod 400 kp-haproxy-edge.pem
```

의미:

- 신규 키페어 생성 + PEM 파일로 저장
- 파일 권한 제한으로 SSH 오류 방지.

---

## 7. CIDR 중복 점검

AWS/온프레 CIDR이 겹치면 라우팅 충돌이 발생하므로 사전 확인.

```bash
python - <<'PY'
import ipaddress
aws = ipaddress.ip_network('10.30.0.0/16')
onprem = ipaddress.ip_network('172.16.20.0/24')
print('overlap=', aws.overlaps(onprem))
PY
```

의미:

- `overlap=False`여야 정상.

---

## 8. Route 53 준비 (AWS CLI)

Hosted Zone 생성:

```bash
aws route53 create-hosted-zone \
  --name sjkim686.store \
  --caller-reference "sjkim686-store-$(date +%s)"
```

Hosted Zone ID/NS 조회:

```bash
HZ_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name sjkim686.store \
  --query "HostedZones[0].Id" --output text)

echo ${HZ_ID}

aws route53 list-resource-record-sets \
  --hosted-zone-id ${HZ_ID} \
  --query "ResourceRecordSets[?Type=='NS' && Name=='sjkim686.store.'].ResourceRecords[].Value" \
  --output text
```

의미:

- 가비아에 입력할 Route 53 NS 4개 값을 조회.

> 가비아 NS 변경은 AWS CLI로 불가(가비아 콘솔에서 수행).

---

## 9. 시작 전 최종 체크

- [ ] Region/VPC/Subnet/CIDR 확정
- [ ] 관리자 공인 IP(/32) 확정
- [ ] 온프레 공인 IP 유무 확인 (경로 A/B 결정)
- [ ] pfSense FRR/BGP 가능 여부 확인
- [ ] 도메인/레코드(`api.sjkim686.store`) 확정
