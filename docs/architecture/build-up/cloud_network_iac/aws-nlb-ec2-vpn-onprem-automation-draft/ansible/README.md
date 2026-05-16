# Ansible 초안 (AWS NLB-EC2-VPN-OnPrem)

> Status: Unverified

인벤토리 예시:

- `inventory.cloud_network_iac.example.ini`

실행 예시:

```bash
ansible-playbook -i docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/inventory.cloud_network_iac.example.ini \
  docs/architecture/build-up/cloud_network_iac/aws-nlb-ec2-vpn-onprem-automation-draft/ansible/playbooks/haproxy.yml
```
