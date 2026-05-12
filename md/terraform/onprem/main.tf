###############################################################################
# terraform/onprem/main.tf
#
# K8s Control Plane × 3 + Worker × 3 + Bastion × 1 = 총 7대 VM 생성.
# - for_each로 variables.tf의 리스트 순회 → 코드 중복 없음
# - 각 VM은 modules/vm 모듈 사용 (재사용 가능)
###############################################################################

#######################################
# Control Plane × 3
#  - HA 구성 (etcd quorum 3개 필수)
#  - 각 Proxmox 노드(kosa1/2/3)에 1대씩 분산
#  - kosa1/2는 pfSense와 공존, kosa3는 워커 1대와 공존
#######################################

module "k8s_control_plane" {
  source = "../modules/vm"

  # for_each: control_plane_nodes 리스트의 각 객체를 순회
  # → 같은 모듈로 3개 VM 동시 생성 (병렬 처리됨)
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
  vlan_tag = var.internal_vlan_tag # VLAN 30 (Internal)

  # IP 계산: 172.16.23.X/24 형식 (X는 ip_suffix)
  # cidrhost(): CIDR에서 호스트 IP 계산하는 Terraform 내장 함수
  # 예: cidrhost("172.16.23.0/24", 10) = "172.16.23.10"
  ip_address  = "${cidrhost(var.internal_cidr, each.value.ip_suffix)}/${split("/", var.internal_cidr)[1]}"
  gateway     = var.internal_gateway
  dns_servers = var.dns_servers

  ssh_public_key = var.ssh_public_key

  # 태그 — Proxmox UI에서 식별, 검색 편의
  tags = ["k8s", "control-plane", "managed-by-terraform"]
}

#######################################
# Worker × 3
#  - kosa3 (1대) + kosa4 (2대) 배치
#  - HPA replica 분산 + Pod anti-affinity 가능한 최소 수
#  - 워커당 4 vCPU / 6GB / 80GB
#######################################

module "k8s_worker" {
  source = "../modules/vm"

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
  vlan_tag = var.internal_vlan_tag # 워커도 VLAN 30

  ip_address  = "${cidrhost(var.internal_cidr, each.value.ip_suffix)}/${split("/", var.internal_cidr)[1]}"
  gateway     = var.internal_gateway
  dns_servers = var.dns_servers

  ssh_public_key = var.ssh_public_key

  tags = ["k8s", "worker", "managed-by-terraform"]
}

#######################################
# Bastion (관리망 VLAN 40)
#  - Ansible runner: 모든 ansible-playbook 실행 위치
#  - kubectl/helm/argocd-cli 도구 설치
#  - 외부에서 노트북 → Bastion → 내부 클러스터 흐름
#######################################

module "bastion" {
  source = "../modules/vm"

  name             = var.bastion_node.name
  vmid             = var.bastion_node.vmid
  pve_node         = var.bastion_node.pve_node
  template_vm_id   = var.template_vm_id
  template_vm_node = var.template_vm_node

  cores     = var.bastion_node.cores
  memory    = var.bastion_node.memory
  disk_size = var.bastion_node.disk_size

  bridge   = var.bridge_lan
  vlan_tag = var.mgmt_vlan_tag # VLAN 40 (Management) — 관리망에만 노출

  ip_address  = "${cidrhost(var.mgmt_cidr, var.bastion_node.ip_suffix)}/${split("/", var.mgmt_cidr)[1]}"
  gateway     = var.mgmt_gateway
  dns_servers = var.dns_servers

  ssh_public_key = var.ssh_public_key

  tags = ["bastion", "mgmt", "managed-by-terraform"]
}
