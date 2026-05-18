# Ansible 초안 (AWS NLB-EC2-VPN-OnPrem)

> Status: Unverified

## 문서 역할

- 이 README는 **inventory/실행 요약**만 다룸
- 변수 상세 기준(SSOT)은 아래 문서를 사용
  - `../../aws-nlb-ec2-vpn-onprem-prerequisites.md`

## 실행 전 체크

1. Terraform `apply` 완료
2. 아래 값으로 inventory 채움
   - `haproxy-a`, `haproxy-c`의 Public IP (`terraform output haproxy_public_ips`)
   - `onprem_edge_backends` (기본: `172.16.22.10/11:443`)

인벤토리 예시 파일:

- `inventory.cloud_network_iac.example.ini`

## Terraform 출력값 -> inventory 매핑

- `terraform output haproxy_public_ips` -> `haproxy-a/c ansible_host`
- `terraform.tfvars`의 `onprem_edge_backends` -> `inventory`의 `onprem_edge_backends`

## 실행 예시

HAProxy 적용:

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini \
  docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/haproxy.yml
```
