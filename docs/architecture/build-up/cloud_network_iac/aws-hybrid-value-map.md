# AWS 하이브리드 값 매핑표

> Status: Unverified 기준 문서: `Project_Study_latest/Project_docs_finals/14-aws-hybrid.md`

`14-aws-hybrid.md`에서 콘솔로 입력했던 값을 Terraform 변수와 후속 수동 작업으로 매핑한다.

---

## 1. Terraform 변수로 처리하는 값

| UI/콘솔 입력 항목    | Terraform 변수/리소스                       | 기본/예시        | 비고                                                             |
| :------------------- | :------------------------------------------ | :--------------- | :--------------------------------------------------------------- |
| Region               | `aws_region`                                | `ap-northeast-2` | 전체 리소스 동일 리전                                            |
| VPC Name             | `name_prefix`                               | `kosa-hybrid`    | 리소스 이름 접두사                                               |
| VPC CIDR             | `vpc_cidr`                                  | `10.20.0.0/16`   | 온프레 CIDR과 중복 금지                                          |
| Public Subnet 2a     | `public_subnets.a.cidr`                     | `10.20.1.0/24`   | NAT Gateway/NLB 배치                                             |
| Public Subnet 2c     | `public_subnets.c.cidr`                     | `10.20.2.0/24`   | NAT Gateway/NLB 배치                                             |
| Private Subnet 2a    | `private_subnets.a.cidr`                    | `10.20.10.0/24`  | HAProxy EC2 배치                                                 |
| Private Subnet 2c    | `private_subnets.c.cidr`                    | `10.20.20.0/24`  | HAProxy EC2 배치                                                 |
| NAT Gateway 1 per AZ | `aws_nat_gateway.this`                      | 자동 생성        | EIP도 Terraform이 생성                                           |
| VPC Endpoint S3      | `create_s3_gateway_endpoint`                | `true`           | Private RTB에 연결                                               |
| EC2 AMI              | `ec2_ami_id`                                | `""`             | 비우면 최신 Ubuntu 22.04 자동 조회                               |
| EC2 Instance Type    | `ec2_instance_type`                         | `t3.micro`       | 데모 기준                                                        |
| EC2 IAM Role         | `aws_iam_role.ssm_ec2`                      | 자동 생성        | SSM 접속용                                                       |
| EC2 Key Pair         | `ec2_key_name`                              | `""`             | SSM 기준이면 비움                                                |
| NLB Scheme           | `aws_lb.nlb.internal=false`                 | Public           | Internet-facing NLB                                              |
| NLB Listener         | `aws_lb_listener.http/https`                | 80, 443          | TCP listener                                                     |
| Route53 Hosted Zone  | `create_route53_zone`, `domain_name`        | 직접 입력        | 가비아 도메인명을 입력하되 문서에 고정값 저장 금지               |
| Route53 Alias        | `create_route53_alias_record`, `app_fqdn`   | 직접 입력        | 비우면 apex 레코드                                               |
| CGW Public IP        | `customer_gateway_public_ip`                | 직접 입력        | pfSense WAN 사설 IP가 아니라 온프레 인터넷 출구/상위 NAT 공인 IP |
| CGW ASN              | `customer_gateway_bgp_asn`                  | `65000`          | Static VPN에서도 AWS 리소스 생성에 필요                          |
| VGW                  | `aws_vpn_gateway.this`                      | 자동 생성        | AWS 측 VPN 종단                                                  |
| VPN Connection       | `aws_vpn_connection.this`                   | 자동 생성        | Static routing                                                   |
| VPN Static Route     | `onprem_cidrs`                              | `172.16.0.0/12`  | `aws_vpn_connection_route` 생성                                  |
| Route Propagation    | `aws_vpn_gateway_route_propagation.private` | 자동 생성        | Private RTB에 VGW propagation 활성화                             |

---

## 2. Terraform 출력값으로 후속 입력하는 값

| 후속 작업              | Terraform output                     | 사용 위치                                  |
| :--------------------- | :----------------------------------- | :----------------------------------------- |
| pfSense Remote Gateway | `vpn_tunnel_outside_ips`             | pfSense IPsec Phase 1의 Remote Gateway 2개 |
| pfSense PSK 확인       | `vpn_customer_gateway_configuration` | pfSense Phase 1 Pre-Shared Key             |
| 가비아 NS 위임         | `route53_name_servers`               | 가비아 도메인 네임서버 설정                |
| 접속 검증              | `nlb_dns_name`                       | `curl`/브라우저 테스트                     |
| SSM 접속 대상          | `haproxy_instance_ids`               | AWS Systems Manager Session Manager        |

---

## 3. Terraform으로 처리하지 않는 값/작업

| 항목                          | 이유                                               | 처리 방식                                                |
| :---------------------------- | :------------------------------------------------- | :------------------------------------------------------- |
| pfSense IPsec Phase 1/2       | pfSense는 AWS 리소스가 아님                        | pfSense WebUI 또는 pfSense 자동화 별도 구현              |
| pfSense Outbound NAT bypass   | pfSense 방화벽/NAT 정책                            | WebUI에서 `172.16.0.0/12 -> 10.20.0.0/16` No NAT 룰 추가 |
| pfSense IPsec Firewall Rule   | pfSense 방화벽 정책                                | IPsec interface rule 추가                                |
| TP-Link/상위 NAT UDP 500/4500 | 온프레 네트워크 장비 설정                          | NAT-T passthrough 또는 port forwarding 확인              |
| 가비아 NS 위임                | AWS Route53이 외부 registrar를 자동 변경할 수 없음 | 가비아 콘솔에서 Route53 NS 4개 입력                      |
| VPN 터널 UP 확인              | 생성과 운영 상태는 별개                            | AWS CLI 또는 AWS Console로 확인                          |

---

## 4. 민감 정보 주의

- PSK(Pre-Shared Key)는 VPN 터널 인증용 비밀값이다.
- Terraform이 자동 생성한 PSK도 `terraform.tfstate` 또는 `vpn_customer_gateway_configuration` 출력에
  포함될 수 있다.
- 아래 파일은 커밋하지 않는다.
  - `terraform.tfstate`
  - `terraform.tfstate.backup`
  - `terraform.tfvars`에 민감값을 넣은 경우 해당 파일
  - `vpn-customer-gateway-configuration.xml`
