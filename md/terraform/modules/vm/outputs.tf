###############################################################################
# terraform/modules/vm/outputs.tf
#
# 호출하는 쪽에서 생성된 VM 정보를 참조할 수 있게 노출.
###############################################################################

output "name" {
  description = "VM 이름 (예: k8s-cp1)"
  value       = proxmox_virtual_environment_vm.this.name
}

output "vmid" {
  description = "Proxmox VMID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4" {
  description = "VM의 IPv4 주소 (CIDR 부분 제외, 순수 IP만)"
  # var.ip_address는 "172.16.23.10/24" 형식
  # split("/", "172.16.23.10/24")[0] = "172.16.23.10"
  value = split("/", var.ip_address)[0]
}

output "pve_node" {
  description = "VM이 위치한 Proxmox 노드 이름"
  value       = var.pve_node
}
