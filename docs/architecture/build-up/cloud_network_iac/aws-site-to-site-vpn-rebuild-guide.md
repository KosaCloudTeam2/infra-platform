# AWS Site-to-Site VPN 재구축 기준 가이드

> Status: Unverified 목적: 현재 AWS VPN/네트워크 구성을 삭제하더라도 Terraform 또는 AWS CLI로
> 재생성할 수 있도록 기준값과 절차를 정리함.

---

## 1. Terraform/AWS CLI로 가능한 범위

| 항목                                 |         Terraform         |       AWS CLI       | 비고                                                                           |
| :----------------------------------- | :-----------------------: | :-----------------: | :----------------------------------------------------------------------------- |
| VPC/Subnet/Route Table/IGW           |           가능            |        가능         | AWS 리소스                                                                     |
| NAT Gateway                          |           가능            |        가능         | NAT-T와 다름. Private Subnet 인터넷 egress용                                   |
| VGW(Virtual Private Gateway)         |           가능            |        가능         | Site-to-Site VPN AWS 측 게이트웨이                                             |
| CGW(Customer Gateway)                |           가능            |        가능         | 온프레 인터넷 출구 공인 IP 등록                                                |
| Site-to-Site VPN Connection          |           가능            |        가능         | `ipsec.1`                                                                      |
| VPN Static Route / Route Propagation |           가능            |        가능         | 라우트 테이블 정합 필요                                                        |
| Route53 Hosted Zone / Alias Record   |           가능            |        가능         | 가비아 NS 위임은 별도 수동                                                     |
| NAT-T(IPsec NAT Traversal)           |    직접 생성 대상 아님    | 직접 생성 대상 아님 | AWS VPN이 NAT-T를 지원하며, pfSense/상위 NAT 경로가 UDP 500/4500을 허용해야 함 |
| pfSense IPsec 터널 설정              | 제한적/별도 Provider 필요 |        불가         | AWS 설정 다운로드 후 pfSense에 반영                                            |
| 가비아 네임서버 위임                 |           불가            |        불가         | 가비아 콘솔에서 수행                                                           |

정리:

- AWS 쪽 인프라는 대부분 Terraform/AWS CLI로 생성 가능.
- **NAT-T는 NAT Gateway가 아니라 IPsec 터널이 NAT 뒤에서 동작하기 위한 기능**임.
- pfSense 설정과 가비아 위임은 AWS API 대상이 아니므로 별도 절차가 필요함.

---

## 2. 현재 AWS 실측값 (2026-05-18 조회)

### 2.1 VPC/Subnet

| 항목             | 값                                                               |
| :--------------- | :--------------------------------------------------------------- |
| VPC ID           | `vpc-03859601c1dd5b658`                                          |
| VPC CIDR         | `10.20.0.0/16`                                                   |
| VPC Name         | `kosa-tickets-vpc`                                               |
| Public Subnet A  | `subnet-0452b79f9e98f8473` / `10.20.1.0/24` / `ap-northeast-2a`  |
| Public Subnet C  | `subnet-03bd9bd5ccb3773fb` / `10.20.2.0/24` / `ap-northeast-2c`  |
| Private Subnet A | `subnet-0ba906a51746b475b` / `10.20.10.0/24` / `ap-northeast-2a` |
| Private Subnet C | `subnet-02542285c79d0d41c` / `10.20.11.0/24` / `ap-northeast-2c` |

### 2.2 NAT Gateway / Route Table

| 항목          | 값                                                                                         |
| :------------ | :----------------------------------------------------------------------------------------- |
| NAT Gateway A | `nat-06228d0a2634bda13` / Public IP `52.78.66.44`                                          |
| NAT Gateway C | `nat-0639891e22679e62b` / Public IP `13.125.89.218`                                        |
| Public RTB    | `rtb-02ced579687efa892` / `kosa-tickets-rtb-public` / `0.0.0.0/0 -> igw-01db341ff4ac9fe52` |
| Private RTB A | `rtb-028ff8167d2c85cb7` / `0.0.0.0/0 -> nat-06228d0a2634bda13`                             |
| Private RTB C | `rtb-02a4ba4423ef11f3d` / `0.0.0.0/0 -> nat-0639891e22679e62b`                             |
| On-Prem Route | `172.16.0.0/12 -> vgw-0f14a420ce5d30261` (Private RTB A/C)                                 |

> 기존에 `172.16.22.0/24`만 조회하면 안 보일 수 있음. 현재는 더 큰 슈퍼넷인 `172.16.0.0/12`로
> 라우팅되어 있음.

### 2.3 Site-to-Site VPN

| 항목                 | 값                        |
| :------------------- | :------------------------ |
| VPN ID               | `vpn-0906e8a06bb85a041`   |
| VPN Type             | `ipsec.1`                 |
| VPN State            | `available`               |
| StaticRoutesOnly     | `true`                    |
| VGW ID               | `vgw-0f14a420ce5d30261`   |
| VGW State            | `available`, VPC attached |
| AWS ASN              | `64512`                   |
| CGW ID               | `cgw-0923e106392116cfc`   |
| CGW endpoint 공인 IP | `125.131.208.229`         |
| CGW ASN              | `65000`                   |
| Tunnel 1             | `43.200.200.229` / `UP`   |
| Tunnel 2             | `54.116.133.94` / `UP`    |

### 2.4 Route53/NLB

| 항목                                 | 값                                                                   |
| :----------------------------------- | :------------------------------------------------------------------- |
| `sjkim686.store` Route53 Hosted Zone | 현재 조회 결과 없음                                                  |
| NLB                                  | `kosa-tickets-nlb`                                                   |
| NLB DNS                              | `kosa-tickets-nlb-091d28bb8f4ca020.elb.ap-northeast-2.amazonaws.com` |
| NLB 상태                             | `active`                                                             |

---

## 3. 재구축 전략

### 3.1 Terraform 재구축

권장 순서:

1. VPC/Subnet/IGW/Route Table
2. NAT Gateway + Private Route Table
3. VGW attach
4. CGW 생성 (`125.131.208.229`, ASN `65000`)
5. Site-to-Site VPN Connection 생성 (`static_routes_only=true`)
6. VPN static route 또는 route propagation
7. NLB/Target Group/Listener
8. Route53 Hosted Zone/Alias Record(필요 시)
9. 가비아 NS 위임(수동)
10. pfSense IPsec 설정 반영(수동)

주의:

- 기존 AWS 리소스를 그대로 Terraform 관리 대상으로 편입하려면 `terraform import`가 필요함.
- 완전 재생성 목적이면 ID는 바뀌어도 되고, CIDR/라우팅/도메인 기준값만 유지하면 됨.
- 현재 `aws-nlb-ec2-vpn-onprem-automation-draft/terraform` 초안은 모든 현재 리소스(NAT
  Gateway/Private Subnet 등)를 완전 복제하지 않을 수 있으므로, 현 상태 재현 목적이면 Terraform 코드
  확장이 필요함.

### 3.2 AWS CLI 재구축

AWS CLI로도 생성 가능하지만, 의존성 순서를 직접 관리해야 함.

핵심 생성 순서:

```text
VPC -> Subnet -> IGW -> Route Table -> NAT Gateway -> VGW -> CGW -> VPN Connection -> Route -> NLB -> Route53
```

pfSense와 가비아 작업은 별도:

- pfSense: AWS VPN 설정 다운로드 후 IPsec 터널/정적 라우트 반영
- 가비아: Route53 NS 4개를 도메인 네임서버로 위임

---

## 4. 조회 명령 (PowerShell)

### 4.1 VPN 터널 상태

```powershell
$AWS_REGION="ap-northeast-2"
$VPN_ID="vpn-0906e8a06bb85a041"

aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --region $AWS_REGION `
  --query "VpnConnections[0].VgwTelemetry[*].[OutsideIpAddress,Status,StatusMessage]" --output table
```

### 4.2 CGW/VGW 확인

```powershell
$CGW_ID=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --region $AWS_REGION `
  --query "VpnConnections[0].CustomerGatewayId" --output text)

aws ec2 describe-customer-gateways --customer-gateway-ids $CGW_ID --region $AWS_REGION `
  --query "CustomerGateways[0].[CustomerGatewayId,IpAddress,BgpAsn,State]" --output table

$VGW_ID=$(aws ec2 describe-vpn-connections --vpn-connection-ids $VPN_ID --region $AWS_REGION `
  --query "VpnConnections[0].VpnGatewayId" --output text)

aws ec2 describe-vpn-gateways --vpn-gateway-ids $VGW_ID --region $AWS_REGION `
  --query "VpnGateways[0].[VpnGatewayId,State,VpcAttachments[0].VpcId]" --output table
```

### 4.3 Route Table 확인

```powershell
$VPC_ID="vpc-03859601c1dd5b658"

aws ec2 describe-route-tables --region $AWS_REGION `
  --filters Name=vpc-id,Values=$VPC_ID `
  --query "RouteTables[*].[RouteTableId,Tags[?Key=='Name']|[0].Value]" --output table
```

온프레 라우트 확인:

```powershell
aws ec2 describe-route-tables --region $AWS_REGION `
  --filters Name=vpc-id,Values=$VPC_ID `
  --query "RouteTables[*].Routes[?DestinationCidrBlock=='172.16.0.0/12'].[DestinationCidrBlock,GatewayId,State,Origin]" --output table
```

### 4.4 NAT Gateway 확인

```powershell
aws ec2 describe-nat-gateways --region $AWS_REGION `
  --filter Name=vpc-id,Values=$VPC_ID `
  --query "NatGateways[*].[NatGatewayId,State,SubnetId,NatGatewayAddresses[0].PublicIp,NatGatewayAddresses[0].PrivateIp]" --output table
```

### 4.5 Route53/NLB 확인

```powershell
aws route53 list-hosted-zones-by-name --dns-name sjkim686.store `
  --query "HostedZones[*].[Id,Name,Config.PrivateZone,ResourceRecordSetCount]" --output table

aws elbv2 describe-load-balancers --region $AWS_REGION `
  --query "LoadBalancers[?Type=='network'].[LoadBalancerName,DNSName,State.Code,VpcId,Scheme]" --output table
```

---

## 5. 검증 기준

- VPN 터널 2개 `UP`
- AWS Private Subnet Route Table에 `172.16.0.0/12 -> VGW` 또는 운영 기준 온프레 CIDR 경로 존재
- 온프레(pfSense)에 AWS VPC CIDR(`10.20.0.0/16`) 경로 존재
- EC2 -> `172.16.22.10:443`, `172.16.22.11:443` 연결 성공
- NLB Target Group `healthy`
- Route53 사용 시 `sjkim686.store`가 NLB로 해석됨

---

## 6. 정리

현재 실측 기준으로는 **경로 A(Site-to-Site VPN)** 가 정상 동작한다.

- `125.131.208.229`는 온프레 인터넷 출구 공인 IP이자 CGW endpoint 공인 IP로 사용 가능
- pfSense WAN이 사설 IP처럼 보여도, 상위 NAT/회선 구조에서 해당 공인 endpoint로 IPsec/NAT-T가 안정
  동작하면 AWS Site-to-Site VPN 운용 가능
- 경로 B(WireGuard Relay)는 CGW endpoint 공인 IP를 확보할 수 없을 때의 대안으로 유지
