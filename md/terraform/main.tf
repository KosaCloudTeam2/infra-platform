###############################################################################
# main.tf
# K8s 클러스터 VM들과 Bastion을 모듈 호출로 생성
###############################################################################

#############################################
# Control Plane × 3
# - for_each로 variables.tf의 control_plane_nodes 리스트를 순회
# - 각 노드는 다른 PVE 호스트에 분산 배치 (HA 위해)
#############################################

module "k8s_control_plane" {
  source = "./modules/vm"

  for_each = { for node in var.control_plane_nodes : node.name => node }

  name             = each.value.name
  vmid             = each.value.vmid
  pve_node         = each.value.pve_node
  template_vm_id   = var.template_vm_id
  template_vm_node = var.template_vm_node

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  bridge   = var.bridge_lan
  vlan_tag = var.internal_vlan_tag

  # IP: 172.16.23.{ip_suffix}/24
  ip_address     = "${cidrhost(var.internal_cidr, each.value.ip_suffix)}/${split("/", var.internal_cidr)[1]}"
  gateway        = var.internal_gateway
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key

  tags = ["k8s", "control-plane", "managed-by-terraform"]
}

#############################################
# Worker × 2
#############################################

module "k8s_worker" {
  source = "./modules/vm"

  for_each = { for node in var.worker_nodes : node.name => node }

  name             = each.value.name
  vmid             = each.value.vmid
  pve_node         = each.value.pve_node
  template_vm_id   = var.template_vm_id
  template_vm_node = var.template_vm_node

  cores     = each.value.cores
  memory    = each.value.memory
  disk_size = each.value.disk_size

  bridge   = var.bridge_lan
  vlan_tag = var.internal_vlan_tag

  ip_address     = "${cidrhost(var.internal_cidr, each.value.ip_suffix)}/${split("/", var.internal_cidr)[1]}"
  gateway        = var.internal_gateway
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key

  tags = ["k8s", "worker", "managed-by-terraform"]
}

#############################################
# Bastion (관리망 VLAN 40)
# - Ansible runner 역할
# - kubectl, helm 등 도구 설치 위치
#############################################

module "bastion" {
  source = "./modules/vm"

  name             = var.bastion_node.name
  vmid             = var.bastion_node.vmid
  pve_node         = var.bastion_node.pve_node
  template_vm_id   = var.template_vm_id
  template_vm_node = var.template_vm_node

  cores     = var.bastion_node.cores
  memory    = var.bastion_node.memory
  disk_size = var.bastion_node.disk_size

  bridge   = var.bridge_lan
  vlan_tag = var.mgmt_vlan_tag # 관리망 VLAN 40

  ip_address     = "${cidrhost(var.mgmt_cidr, var.bastion_node.ip_suffix)}/${split("/", var.mgmt_cidr)[1]}"
  gateway        = var.mgmt_gateway
  dns_servers    = var.dns_servers
  ssh_public_key = var.ssh_public_key

  tags = ["bastion", "mgmt", "managed-by-terraform"]
}
