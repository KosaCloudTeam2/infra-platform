# AWS 하이브리드 Terraform 실행 가이드

> Status: Unverified 기준 문서: `Project_Study_latest/Project_docs_finals/14-aws-hybrid.md`

이 문서는 콘솔로 구성했던 AWS 하이브리드 네트워크를 Terraform 명령으로 재생성하기 위한 가이드다. AWS
리소스는 Terraform으로 만들고, Terraform으로 처리할 수 없는 pfSense/가비아 작업만 별도 수동 단계로
분리한다.

---

## 1. 목표 구성

```text
On-Prem 172.16.0.0/12
  └─ pfSense / TP-Link NAT-T
      └─ Site-to-Site VPN
          └─ AWS VPC 10.20.0.0/16
              ├─ Public Subnet 2개: NLB, NAT Gateway
              └─ Private Subnet 2개: HAProxy EC2, 향후 EKS/RDS
```

Terraform 생성 대상:

- VPC, Public/Private Subnet
- Internet Gateway, NAT Gateway
- Route Table, Route Association
- S3 Gateway Endpoint
- Security Group
- Private EC2 HAProxy 2대
- SSM IAM Role/Profile
- Internet-facing NLB, Target Group, Listener
- Route53 Hosted Zone/Alias Record
- VGW, CGW, Site-to-Site VPN Connection
- VPN static route, Private Route Table route propagation

Terraform 외부 작업:

- pfSense IPsec 설정
- pfSense Outbound NAT bypass
- 가비아 NS 위임
- 터널 상태 확인용 AWS CLI

---

## 2. 사전 준비

필수 확인값:

| 항목                 | 값/예시          | 설명                                                 |
| :------------------- | :--------------- | :--------------------------------------------------- |
| AWS Region           | `ap-northeast-2` | 서울 리전                                            |
| AWS VPC CIDR         | `10.20.0.0/16`   | 온프레와 중복 금지                                   |
| On-Prem CIDR         | `172.16.0.0/12`  | VPN static route 대상                                |
| CGW endpoint 공인 IP | 환경별 입력      | pfSense WAN 사설 IP가 아니라 외부에서 보이는 공인 IP |
| 가비아 도메인        | 환경별 입력      | 문서에 특정 도메인 고정 금지                         |

CGW endpoint 공인 IP 확인 예:

```bash
curl -4 ifconfig.me
```

pfSense가 NAT 뒤에 있으면 AWS CGW에는 pfSense WAN IP가 아니라 **상위 NAT/인터넷 출구 공인 IP**를
입력한다.

---

## 3. Terraform 실행

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-hybrid-terraform
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`에서 최소 수정:

```hcl
customer_gateway_public_ip = "<온프레_인터넷_출구_공인_IP>"
domain_name                 = "<가비아에서_구매한_도메인>"
app_fqdn                    = "<서비스_FQDN 또는 빈값>"
```

실행:

```bash
terraform init
terraform fmt
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

주의:

- `terraform init`/`terraform plan`은 리소스를 만들지 않는다.
- 실제 생성은 `terraform apply tfplan`에서 수행된다.
- `terraform apply -auto-approve`는 확인 없이 생성/수정/삭제하므로 팀 작업에서는 비권장한다.

---

## 4. Terraform 출력 확인

```bash
terraform output
terraform output route53_name_servers
terraform output vpn_tunnel_outside_ips
terraform output -raw vpn_customer_gateway_configuration > vpn-customer-gateway-configuration.xml
```

출력값 사용처:

| Output                               | 사용처                              |
| :----------------------------------- | :---------------------------------- |
| `route53_name_servers`               | 가비아 NS 위임                      |
| `vpn_tunnel_outside_ips`             | pfSense Remote Gateway 2개          |
| `vpn_customer_gateway_configuration` | pfSense PSK/IKE/IPsec 파라미터 참고 |
| `haproxy_instance_ids`               | SSM Session Manager 접속 대상       |
| `nlb_dns_name`                       | NLB 접속 검증                       |

`vpn-customer-gateway-configuration.xml`에는 PSK가 포함될 수 있으므로 저장소에 커밋하지 않는다.

---

## 5. pfSense 후속 설정

Terraform은 AWS 쪽 VPN 리소스를 만들지만 pfSense 장비 설정은 직접 변경하지 못한다.

### 5.1 IPsec Phase 1

pfSense WebUI:

```text
VPN → IPsec → Tunnels → Add P1
```

터널 2개를 각각 생성한다.

| 항목                  | 값                                                |
| :-------------------- | :------------------------------------------------ |
| Key Exchange version  | IKEv1                                             |
| Interface             | WAN                                               |
| Remote Gateway        | `terraform output vpn_tunnel_outside_ips`의 각 IP |
| Authentication Method | Mutual PSK                                        |
| Pre-Shared Key        | `vpn_customer_gateway_configuration`에서 확인     |
| Encryption            | AES128                                            |
| Hash                  | SHA1                                              |
| DH Group              | 2                                                 |
| NAT Traversal         | Force                                             |

### 5.2 IPsec Phase 2

각 Phase 1 아래에 Phase 2를 추가한다.

| 항목           | 값              |
| :------------- | :-------------- |
| Mode           | Tunnel IPv4     |
| Local Network  | `172.16.0.0/12` |
| Remote Network | `10.20.0.0/16`  |
| Protocol       | ESP             |
| Encryption     | AES128          |
| Hash           | SHA1            |
| PFS Key Group  | 2               |

### 5.3 IPsec Firewall Rule

```text
Firewall → Rules → IPsec → Add
```

- Action: Pass
- Protocol: any
- Source: `10.20.0.0/16`
- Destination: 필요한 온프레 대역 또는 any

### 5.4 Outbound NAT bypass

```text
Firewall → NAT → Outbound
```

- Mode: Hybrid Outbound NAT
- Rule 위치: 가장 위
- Interface: WAN
- Source: `172.16.0.0/12`
- Destination: `10.20.0.0/16`
- Translation: No NAT

이 룰이 없으면 터널은 UP이어도 트래픽이 drop될 수 있다.

---

## 6. 가비아 NS 위임

Terraform이 Route53 Hosted Zone을 만들면 아래 출력으로 NS 4개를 확인한다.

```bash
terraform output route53_name_servers
```

가비아 콘솔에서 해당 도메인의 네임서버를 Route53 NS 값으로 변경한다.

주의:

- Route53 Hosted Zone 생성은 DNS 서버 설치가 아니다.
- 외부 registrar인 가비아 NS 위임은 AWS Terraform만으로 처리되지 않는다.
- DNS 전파에는 시간이 걸릴 수 있다.

---

## 7. 검증 명령

### 7.1 NLB 확인

```bash
NLB_DNS=$(terraform output -raw nlb_dns_name)
curl -I http://${NLB_DNS}/healthz
```

### 7.2 Route53 확인

```bash
dig +short <서비스_FQDN>
```

### 7.3 VPN 터널 상태 확인

AWS CLI는 생성용이 아니라 상태 확인용으로 사용한다.

```bash
AWS_REGION=ap-northeast-2
VPN_ID=$(terraform output -raw vpn_connection_id)

aws ec2 describe-vpn-connections \
  --region ${AWS_REGION} \
  --vpn-connection-ids ${VPN_ID} \
  --query 'VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status,StatusMessage]' \
  --output table
```

### 7.4 Route Table propagation 확인

```bash
VPC_ID=$(terraform output -raw vpc_id)

aws ec2 describe-route-tables \
  --region ${AWS_REGION} \
  --filters Name=vpc-id,Values=${VPC_ID} \
  --query "RouteTables[*].Routes[?DestinationCidrBlock=='172.16.0.0/12'].[DestinationCidrBlock,GatewayId,State,Origin]" \
  --output table
```

### 7.5 SSM 접속

```bash
terraform output haproxy_instance_ids
```

AWS Console:

```text
Systems Manager → Session Manager → Start session → HAProxy EC2 선택
```

Private Subnet EC2가 SSM에 붙으려면 NAT Gateway 경로와 IAM Role(`AmazonSSMManagedInstanceCore`)이
필요하며, Terraform이 이를 생성한다.

---

## 8. 삭제

Terraform으로 만든 경우 Terraform state 기준으로 삭제한다.

```bash
terraform plan -destroy -out tfdestroy
terraform apply tfdestroy
```

삭제 실패 또는 수동 생성 리소스가 섞인 경우:

- [AWS 리소스 정리 체크리스트](./aws-resource-cleanup-checklist.md)

---

## 9. 주의사항

- `.tfstate`에는 민감 정보가 포함될 수 있으므로 저장소에 저장하지 않는다.
- PSK를 `.tfvars`에 직접 넣지 않는다. 현재 Terraform은 AWS 자동 생성 방식을 사용한다.
- 가비아 도메인 값은 환경별로 입력하고, 문서에 특정 개인 도메인을 고정하지 않는다.
- pfSense NAT-T 환경에서는 UDP 500/4500 통과가 필요하다.
