# AWS Hybrid Terraform

> Status: Unverified 기준 문서: `Project_Study_latest/Project_docs_finals/14-aws-hybrid.md`

이 Terraform은 콘솔에서 수동 생성했던 VPC + Site-to-Site VPN 기반 하이브리드 네트워크를 명령어로
재현하기 위한 초안이다.

## 생성 대상

- VPC `10.20.0.0/16`
- Public Subnet 2개
- Private Subnet 2개
- Internet Gateway
- NAT Gateway 2개
- Public/Private Route Table
- S3 Gateway Endpoint
- Private EC2 HAProxy 2대
- EC2용 SSM IAM Role/Profile
- Internet-facing NLB
- Target Group/Listener 80, 443
- Route53 Hosted Zone/Alias Record
- VGW, CGW, Site-to-Site VPN
- VPN static route와 Private Route Table route propagation

## Terraform 밖 작업

- pfSense IPsec Phase 1/2 설정
- pfSense IPsec Firewall Rule
- pfSense Outbound NAT bypass
- TP-Link/상위 NAT의 UDP 500/4500 통과 확인
- 가비아 네임서버(NS) 위임

## 실행

```bash
cd docs/architecture/build-up/cloud_network_iac/aws-hybrid-terraform
cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars에서 customer_gateway_public_ip, domain_name, app_fqdn 등을 환경에 맞게 수정

terraform init
terraform fmt
terraform validate
terraform plan -out tfplan
terraform apply tfplan
```

주의:

- `terraform plan`만으로는 리소스가 생성되지 않는다.
- 실제 생성은 `terraform apply tfplan` 단계에서 수행된다.
- `terraform apply -auto-approve`는 확인 없이 적용되므로 데모/팀 작업에서는 비권장한다.
- `terraform.tfstate`에는 VPN 설정 정보가 포함될 수 있으므로 저장소에 커밋하지 않는다.

## apply 후 출력 확인

```bash
terraform output
terraform output route53_name_servers
terraform output vpn_tunnel_outside_ips
terraform output -raw vpn_customer_gateway_configuration > vpn-customer-gateway-configuration.xml
```

`vpn-customer-gateway-configuration.xml`에는 Pre-Shared Key(PSK)가 포함될 수 있으므로
저장소/메신저에 공유하지 않는다.

## pfSense 후속 설정

Terraform apply 후 아래 값을 pfSense에 입력한다.

- Remote Gateway: `terraform output vpn_tunnel_outside_ips`
- Pre-Shared Key: `vpn_customer_gateway_configuration` XML 또는 AWS VPN 설정 화면에서 확인
- Local Network: `172.16.0.0/12`
- Remote Network: `10.20.0.0/16`
- IKE: IKEv1
- Phase 1/2: AES128, SHA1, DH Group 2
- NAT Traversal: Force

세부 절차는 상위 가이드 `../aws-hybrid-terraform-guide.md`를 따른다.

## 삭제

```bash
terraform plan -destroy -out tfdestroy
terraform apply tfdestroy
```

수동 생성 리소스가 섞여 있거나 삭제가 실패하면 `../aws-resource-cleanup-checklist.md`를 참고한다.
