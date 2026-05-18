# Terraform 초안 (AWS NLB-EC2-VPN-OnPrem)

> Status: Unverified

## 문서 역할

- 이 README는 **실행 요약**만 다룸
- 변수별 상세 확인 방법(SSOT)은 아래 문서를 사용
  - `../../aws-nlb-ec2-vpn-onprem-value-discovery-guide.md`
  - `../../aws-nlb-ec2-vpn-onprem-prerequisites.md`
  - `../../aws-site-to-site-vpn-rebuild-guide.md`

> 주의: 이 Terraform 초안은 재구축 출발점이며, 현재 AWS 실측 구성(10.20.0.0/16, Private Subnet, NAT
> Gateway 2개, `172.16.0.0/12 -> VGW` 라우트)을 완전히 복제하려면 코드 확장이 필요할 수 있음.

## tfvars 입력 전 체크

1. 경로 A/B 결정
2. `terraform.tfvars.example` -> `terraform.tfvars` 복사
3. 아래 항목 최소 확정
   - 네트워크: `vpc_cidr`, `public_subnet_*`, `az_*`
   - 접근: `admin_cidr`, `key_name`
   - 경로 A: `create_site_to_site_vpn`, `customer_gateway_public_ip`, `customer_gateway_bgp_asn`,
     `onprem_cidr`
   - 경로 B(대안): `create_wireguard_relay`, `relay_allowed_udp_cidr`, `onprem_cidr`
   - DNS: `create_route53_zone`, `domain_name`, `create_route53_alias_record`, `app_fqdn`

> 각 변수의 의미/실측 확인 명령은 value-discovery 가이드를 기준으로 함.

## 실행

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 값 수정

terraform init
terraform plan -out tfplan
terraform apply tfplan
```

## apply 후 확인 (Ansible 연계)

```bash
terraform output
```

확인할 핵심 출력:

- `haproxy_instance_ids`
- `haproxy_public_ips` (Ansible SSH inventory에 사용)
- `haproxy_private_ips`
- `relay_eip` (경로 B 사용 시)
- `route53_name_servers`
- `nlb_dns_name`

## 삭제

```bash
terraform destroy
```
