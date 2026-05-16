# AWS NLB-EC2-VPN-OnPrem 값 설정/확인 가이드

> Status: Unverified

`x.x.x.x`, `vpc-xxxx`, `ami-xxxx` 같은 placeholder 값을 실제 값으로 바꾸기 위한 가이드임.

---

## 1. 우선순위

1. 네트워크 값 확정 (CIDR/AZ/Subnet)
2. 인스턴스 값 확정 (AMI/타입/키페어)
3. VPN 값 확정 (온프레 공인 IP, ASN, 라우팅 방식)
4. DNS 값 확정 (도메인/레코드)

---

## 2. AWS CLI 인증/기본 설정 (`aws configure`)

AWS CLI 사용 전, 먼저 계정/리전 기본값을 설정함.

### 2.1 Access Key/Secret Key 발급 위치

권장: 루트(Root) 계정 대신 **IAM 사용자**에서 발급.

#### A) IAM 사용자에서 발급 (권장)

1. AWS 콘솔 > `IAM`
2. `Users` > 대상 사용자 클릭
3. `Security credentials` 탭
4. `Access keys` > `Create access key`
5. 사용 사례 `Command Line Interface (CLI)` 선택

#### B) 계정(Security credentials)에서 발급

1. 우측 상단 계정명
2. `Security credentials`(보안 자격 증명)
3. `Access keys` > `Create access key`
4. 사용 사례 `Command Line Interface (CLI)` 선택

생성 시 확인값:

- `AWS Access Key ID`
- `AWS Secret Access Key`

> `Secret Access Key`는 생성 직후 1회만 표시됨.

### 2.2 `aws configure` 입력 예시

```powershell
aws configure
```

```text
AWS Access Key ID [None]: AKIA...
AWS Secret Access Key [None]: xxxxx
Default region name [None]: ap-northeast-2
Default output format [None]: json
```

리전 참고:

- `ap-northeast-2`: 서울
- `us-east-1`: 버지니아
- `ap-northeast-1`: 도쿄

### 2.3 설정 파일 저장 위치 (Windows)

- `C:\Users\SamuelK\.aws\credentials`
- `C:\Users\SamuelK\.aws\config`

### 2.4 설정 완료 확인

```powershell
aws sts get-caller-identity
```

정상 시 `Account`, `Arn`, `UserId`가 출력됨.

### 2.5 `aws login` vs `aws configure`

- 일반 IAM Access Key 기반: `aws configure`
- IAM Identity Center(SSO)/브라우저 인증 기반: `aws login` 또는 `aws sso login`

### 2.6 보안 주의

- Access Key/Secret Key를 Git 저장소에 커밋 금지
- 채팅/이슈/문서에 키 원문 붙여넣기 금지
- `.env`, `.tfvars`, shell history에 키 노출 여부 점검

### 2.7 Access Key 생성 메뉴가 안 보일 때

- IAM 권한 부족 가능성이 큼
- 루트 계정 또는 IAM 관리자에게 Access Key 생성 권한 정책 확인 요청

---

## 3. Terraform 변수별 확인 위치

기준 파일:
`docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform/terraform.tfvars.example`

| 변수                          | 의미                       | 어디서 확인/결정          | 확인/입력 예시                                                                                       |
| :---------------------------- | :------------------------- | :------------------------ | :--------------------------------------------------------------------------------------------------- |
| `aws_region`                  | AWS 리전                   | 팀 표준 리전              | `aws configure get region` → `ap-northeast-2`                                                        |
| `name_prefix`                 | 리소스 이름 접두어         | 팀 네이밍 규칙            | 예시: `hybrid-edge`                                                                                  |
| `vpc_cidr`                    | VPC CIDR                   | 온프레와 비중복 대역 설계 | 예시: `10.30.0.0/16`                                                                                 |
| `public_subnet_a_cidr`        | Public Subnet A CIDR       | VPC CIDR 하위 대역        | 예시: `10.30.1.0/24`                                                                                 |
| `public_subnet_c_cidr`        | Public Subnet C CIDR       | VPC CIDR 하위 대역        | 예시: `10.30.2.0/24`                                                                                 |
| `az_a`, `az_c`                | 가용영역                   | 리전 내 사용 가능 AZ      | `aws ec2 describe-availability-zones --region ap-northeast-2 --query 'AvailabilityZones[].ZoneName'` |
| `admin_cidr`                  | SSH 허용 CIDR              | 관리자 PC 공인 IP         | `curl ifconfig.me` 결과가 `1.2.3.4`면 `1.2.3.4/32`                                                   |
| `haproxy_ami_id`              | HAProxy EC2 AMI            | AL2023 최신 AMI           | 아래 3.1 조회값 (예: `ami-0abc1234...`)                                                              |
| `haproxy_instance_type`       | 인스턴스 타입              | 성능/비용 기준            | 예시: `t3.small`                                                                                     |
| `key_name`                    | EC2 접속 키페어명          | 기존/신규 키페어          | `aws ec2 describe-key-pairs --query 'KeyPairs[].KeyName'`                                            |
| `onprem_edge_backends`        | 온프레 HAProxyEdge IP:Port | 온프레 운영값(고정)       | **임의 지정 금지**, 아래 `3.3.1` 확인                                                                |
| `create_wireguard_relay`      | Relay 경로 사용 여부       | 공인IP 유무 기준          | 예시: 공인IP 없음 → `true`, 공인IP 있음 → `false`                                                    |
| `relay_ami_id`                | Relay EC2 AMI              | AL2023 최신 AMI           | 아래 3.1 조회값 (예: `ami-0abc1234...`)                                                              |
| `relay_allowed_udp_cidr`      | Relay UDP 허용 대역        | 온프레 NAT 공인IP 우선    | **임의 지정 지양**, 아래 `3.3.2` 확인                                                                |
| `create_site_to_site_vpn`     | S2S VPN 사용 여부          | 공인IP + 장비 지원 여부   | 예시: 공인IP+BGP 가능 → `true`, 공인IP 없음 → `false`                                                |
| `customer_gateway_public_ip`  | 온프레 공인IP              | 온프레 회선/NAT 공인IP    | **임의 지정 금지**, 아래 `3.3.3` 확인                                                                |
| `customer_gateway_bgp_asn`    | 온프레 BGP ASN             | pfSense FRR/BGP 설정값    | **임의 지정 지양**, 아래 `3.3.4` 확인                                                                |
| `onprem_cidr`                 | 온프레 내부 대역           | 라우팅 대상 CIDR          | **임의 지정 금지**, 아래 `3.3.5` 확인                                                                |
| `vpn_static_routes_only`      | Static 모드 여부           | BGP 미지원 시 true        | 예시: BGP 사용 시 `false`, BGP 미사용 시 `true`                                                      |
| `create_route53_zone`         | Hosted Zone 생성 여부      | 도메인 운영 방식          | 예시: Route53에 존 신규 생성 시 `true`                                                               |
| `domain_name`                 | 루트 도메인                | 구매 도메인               | **임의 지정 금지**, 아래 `3.3.6` 확인                                                                |
| `create_route53_alias_record` | Alias 레코드 생성 여부     | 앱 도메인 사용 여부       | 예시: `api.sjkim686.store` 연결 시 `true`                                                            |
| `app_fqdn`                    | 앱 FQDN                    | 도메인 정책               | **임의 지정 지양**, 아래 `3.3.7` 확인                                                                |

### 3.1 AL2023 AMI ID 조회

```bash
aws ssm get-parameters \
  --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --region ap-northeast-2 \
  --query 'Parameters[0].Value' --output text
```

### 3.2 "수동 결정"의 의미

- AWS에서 자동 조회되는 값이 아니라, **팀 설계 기준으로 선택/입력**해야 하는 값이라는 의미임.
- 본 문서의 예시값을 바로 써도 되지만, 실제 온프레 CIDR/공인IP와 충돌 없는지 반드시 확인 후 적용해야
  함.

### 3.3 임의 지정하면 안 되는 값 확인 방법

#### 3.3.1 `onprem_edge_backends`

- 의미: AWS HAProxy가 넘길 **온프레 HAProxyEdge 실제 백엔드 주소(IP:Port)**
- 확인 우선순위:
  1. 팀 표준 문서/Runbook 값 확인
  2. 온프레 HAProxyEdge 서버 실측
- 온프레 HAProxyEdge에서 확인:

```bash
sudo grep -E '^\s*server\s+' /etc/haproxy/haproxy.cfg
```

- 위 결과의 `IP:Port`를 `onprem_edge_backends`에 그대로 반영

#### 3.3.2 `relay_allowed_udp_cidr`

- 의미: WireGuard Relay(51820/UDP)에 접속 허용할 **온프레 NAT 공인IP 대역**
- 확인 항목 1: 온프레 인터넷 라우터/방화벽의 WAN 공인IP
- 확인 항목 2: 가능하면 `/32`로 제한 (예: `203.0.113.10/32`)

#### 3.3.3 `customer_gateway_public_ip`

- 의미: AWS VPN의 Customer Gateway로 등록할 **온프레 공인IP**
- 확인 항목 1: pfSense/온프레 GW WAN 인터페이스 공인IP
- 확인 항목 2: ISP 고정 공인IP 계약값
- 주의: NAT 뒤 사설IP를 넣으면 VPN 터널이 올라오지 않음

#### 3.3.4 `customer_gateway_bgp_asn`

- 의미: 온프레 BGP ASN
- 확인 항목 1: pfSense FRR BGP 설정값과 동일 여부
- 예시: `65000` (팀 실사용값 우선)

#### 3.3.5 `onprem_cidr`

- 의미: AWS에서 온프레로 라우팅할 내부 대역
- 확인 항목 1: `docs/runbooks/onprem_port_vlan_vm_layout.md`
- 확인 항목 2: pfSense 라우팅/인터페이스 설정
- 주의: 실제 운영 대역과 다르면 경로가 잘못 잡힘

#### 3.3.6 `domain_name`

- 의미: Route53 Hosted Zone 대상 루트 도메인
- 확인 항목 1: 도메인 등록기관(가비아)에서 보유한 실제 도메인
- 예시: `sjkim686.store`

#### 3.3.7 `app_fqdn`

- 의미: 외부 노출 서비스 FQDN
- 확인 항목 1: 발표/운영에서 쓰는 실제 엔드포인트 정책
- 확인 항목 2: Route53 레코드 이름과 일치 여부
- 예시: `api.sjkim686.store`

---

## 4. CLI 문서 Placeholder 확인 위치

기준 파일: `docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-haproxyedge-cli.md`

| Placeholder                      | 확인 위치                                                                                                         |
| :------------------------------- | :---------------------------------------------------------------------------------------------------------------- |
| `<VPC_ID>`                       | `aws ec2 describe-vpcs --query 'Vpcs[].VpcId'`                                                                    |
| `<SUBNET_A_ID>`, `<SUBNET_C_ID>` | `aws ec2 describe-subnets --filters Name=vpc-id,Values=<VPC_ID>`                                                  |
| `<NLB_ARN>`                      | `aws elbv2 describe-load-balancers --names <NLB_NAME>`                                                            |
| `<TG_ARN>`                       | `aws elbv2 describe-target-groups --names <TG_NAME>`                                                              |
| `<EC2_ID_A>`, `<EC2_ID_C>`       | `aws ec2 describe-instances --filters Name=tag:Name,Values=*haproxy*`                                             |
| `<RTB_ID>`                       | `aws ec2 describe-route-tables --filters Name=vpc-id,Values=<VPC_ID>`                                             |
| `<IGW_ID>`                       | `aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=<VPC_ID>`                             |
| `<VPN_ID>`                       | `aws ec2 describe-vpn-connections --query 'VpnConnections[].VpnConnectionId'`                                     |
| `<VGW_ID>`                       | `aws ec2 describe-vpn-gateways`                                                                                   |
| `<CGW_ID>`                       | `aws ec2 describe-customer-gateways`                                                                              |
| `<ONPREM_PUBLIC_IP>`             | 온프레 회선/NAT 공인IP 확인                                                                                       |
| `<ONPREM_ASN>`                   | pfSense FRR BGP ASN                                                                                               |
| `<NLB_ZONE_ID>`, `<NLB_DNS>`     | `aws elbv2 describe-load-balancers --names <NLB_NAME> --query 'LoadBalancers[0].[CanonicalHostedZoneId,DNSName]'` |

---

## 5. 콘솔에서 확인해야 할 값

| 값                | 콘솔 위치                                                                  |
| :---------------- | :------------------------------------------------------------------------- |
| VPC ID/CIDR       | VPC 콘솔 > Your VPCs                                                       |
| Subnet ID/CIDR/AZ | VPC 콘솔 > Subnets                                                         |
| Route Table ID    | VPC 콘솔 > Route tables                                                    |
| IGW ID            | VPC 콘솔 > Internet gateways                                               |
| EC2 Instance ID   | EC2 콘솔 > Instances                                                       |
| NLB ARN/DNS       | EC2 콘솔 > Load Balancers                                                  |
| Target Group ARN  | EC2 콘솔 > Target Groups                                                   |
| VPN/CGW/VGW ID    | VPC 콘솔 > Site-to-Site VPN / Customer gateways / Virtual private gateways |
| Hosted Zone ID/NS | Route 53 > Hosted zones                                                    |

---

## 6. WireGuard 값 확인 포인트

| 값                | 확인 방법                           |
| :---------------- | :---------------------------------- |
| Relay public key  | Relay EC2에서 `cat /tmp/relay.pub`  |
| OnPrem public key | OnPrem GW에서 `cat /tmp/onprem.pub` |
| Relay EIP         | EC2 콘솔 > Elastic IPs              |
| AWS VPC CIDR      | VPC 콘솔 > Your VPCs                |

---

## 7. 최종 체크

- [ ] CIDR 중복 없음(AWS VPC vs OnPrem)
- [ ] 관리자 SSH 대역 `/32` 제한
- [ ] 온프레 공인 IP 유무에 따라 경로 A/B 결정
- [ ] pfSense FRR/BGP 가능 여부 확인
- [ ] 도메인(`sjkim686.store`)과 앱 FQDN(`api.sjkim686.store`) 확정
