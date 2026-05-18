# Ansible 초안 (AWS NLB-EC2-VPN-OnPrem)

> Status: Unverified

## 문서 역할

- 이 README는 **inventory/실행 요약**만 다룸
- 변수 상세 기준(SSOT)은 아래 문서를 사용
  - `../../aws-nlb-ec2-vpn-onprem-value-discovery-guide.md`
  - `../../aws-nlb-ec2-vpn-onprem-prerequisites.md`

## 실행 전 체크

1. Terraform `apply` 완료
2. 아래 값으로 inventory 채움
   - `haproxy-a`, `haproxy-c`의 Public IP (`terraform output haproxy_public_ips`)
   - `relay-01`의 EIP (`terraform output relay_eip`, 경로 B 사용 시)
   - `onprem_edge_backends` (기본: `172.16.22.10/11:443`)
   - `onprem_cidr` (현재 실측: `172.16.0.0/12`)
   - `onprem_public_key`, `relay_private_key` (경로 B 사용 시 민감값)

인벤토리 예시 파일:

- `inventory.cloud_network_iac.example.ini`

## Terraform 출력값 -> inventory 매핑

- `terraform output haproxy_public_ips` -> `haproxy-a/c ansible_host`
- `terraform output relay_eip` -> `relay-01 ansible_host` (경로 B 사용 시)
- `terraform.tfvars`의 `onprem_cidr` -> `inventory`의 `onprem_cidr`
- `terraform.tfvars`의 `onprem_edge_backends` -> `inventory`의 `onprem_edge_backends`

## 실행 예시

HAProxy 적용:

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini \
  docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/haproxy.yml
```

WireGuard Relay 적용:

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini \
  docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/wireguard_relay.yml
```

> `relay_private_key`는 저장소 평문 대신 Ansible Vault 또는 실행 시 `-e` 주입 권장.
