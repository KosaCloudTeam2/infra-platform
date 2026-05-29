# On-prem Proxmox Terraform

> Status: Unverified

실제 Proxmox 클러스터 조회값 기준 VM 관리 코드.

## 확인 기준

- Proxmox cluster: `team2`
- Proxmox VE: `9.1.9`
- API endpoint: `https://192.168.21.4:8006/`
- Template: `ubuntu-2204-template`, VMID `9000`, node `kosa1`
- VM disk storage: `ceph-rbd-team2`
- Cloud-init storage: `local-lvm`
- K8s VLAN: `30`, `172.16.23.0/24`
- Bastion VLAN: `40`, `172.16.24.0/24`
- Storage network: `vmbr1`, `10.10.10.0/24`, MTU `9000`

## 대상

- `k8s-cp1`: VMID `210`, node `kosa4`, IP `172.16.23.10`
- `k8s-cp2`: VMID `211`, node `kosa2`, IP `172.16.23.11`
- `k8s-cp3`: VMID `212`, node `kosa3`, IP `172.16.23.12`
- `k8s-w1`: VMID `220`, node `kosa3`, IP `172.16.23.20`
- `k8s-w2`: VMID `221`, node `kosa4`, IP `172.16.23.21`
- `k8s-w3`: VMID `222`, node `kosa2`, IP `172.16.23.22`
- `k8s-sys1`: VMID `223`, node `kosa1`, IP `172.16.23.23`
- `bastion`: VMID `230`, node `kosa3`, IP `172.16.24.10`

## 실행 전제

- 기존 VM import 우선
- `terraform apply` 단독 실행 금지
- `terraform plan` diff 검토 후 담당자 1명 적용
- Proxmox 비밀번호, API token 저장소 저장 금지
- 권장 인증: `PROXMOX_VE_API_TOKEN`
- 임시 인증: `PROXMOX_VE_USERNAME`, `PROXMOX_VE_PASSWORD`

## 실행 예시

```powershell
$env:PROXMOX_VE_USERNAME = "root@pam"
$env:PROXMOX_VE_PASSWORD = "<local-only>"

terraform -chdir=infra/terraform/proxmox init
terraform -chdir=infra/terraform/proxmox plan -var-file=env/onprem.example.tfvars
```

## import 기준

`imports.tf`에 현재 VM import block 포함.

수동 import 필요 시:

```powershell
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-cp1"]' kosa4/210
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-cp2"]' kosa2/211
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-cp3"]' kosa3/212
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-w1"]' kosa3/220
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-w2"]' kosa4/221
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-w3"]' kosa2/222
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["k8s-sys1"]' kosa1/223
terraform -chdir=infra/terraform/proxmox import 'proxmox_virtual_environment_vm.vm["bastion"]' kosa3/230
```

## 제외 대상

- `pfsense-1`, `pfsense-2`: 방화벽 appliance, 별도 수동 운영
- `lb-1`, `lb-2`: 기존 linked clone disk path 이상값 확인 필요
- `edge-haproxy`, `edge-haproxy2`: Ansible 관리 대상, Terraform import 전 별도 검토 필요

## 참고

- Provider: [bpg/proxmox](https://bpg.sh/docs/)
- VM resource import 형식: `node_name/vm_id`
