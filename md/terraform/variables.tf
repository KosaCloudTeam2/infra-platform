###############################################################################
# variables.tf
# 환경별로 달라지는 값들은 전부 변수화. 실제 값은 terraform.tfvars 에 작성.
###############################################################################

#############################################
# Proxmox 접속 정보
#############################################

variable "proxmox_endpoint" {
  description = "Proxmox API 엔드포인트 (예: https://192.168.21.2:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API 토큰 (root@pam!<id>=<secret>)"
  type        = string
  sensitive   = true
}

variable "proxmox_ssh_private_key_path" {
  description = "Proxmox host SSH 접근용 private key 경로 (provider 내부 작업용)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

#############################################
# Proxmox 클러스터 노드 식별자
# (terraform이 어떤 PVE 노드에 VM 띄울지 지정할 때 사용)
#############################################

variable "proxmox_nodes" {
  description = "Proxmox 노드 이름 → 식별자 매핑"
  type        = map(string)
  default = {
    kosa1 = "kosa1"
    kosa2 = "kosa2"
    kosa3 = "kosa3"
    kosa4 = "kosa4"
  }
}

#############################################
# Cloud-init 템플릿 (사전에 만들어둔 VM)
#############################################

variable "template_vm_id" {
  description = "Ubuntu 22.04 cloud-init 템플릿 VMID"
  type        = number
  default     = 9000
}

variable "template_vm_node" {
  description = "템플릿 VM이 있는 Proxmox 노드"
  type        = string
  default     = "kosa1"
}

#############################################
# SSH 키 (cloud-init으로 VM에 주입)
#############################################

variable "ssh_public_key" {
  description = "VM의 ubuntu 사용자에 등록할 SSH 공개키"
  type        = string
}

#############################################
# 네트워크 설정
#############################################

variable "bridge_lan" {
  description = "VM이 붙을 LAN 브리지 (VLAN-aware vmbr0)"
  type        = string
  default     = "vmbr0"
}

variable "internal_vlan_tag" {
  description = "K8s 노드용 VLAN (Internal = VLAN 30)"
  type        = number
  default     = 30
}

variable "mgmt_vlan_tag" {
  description = "관리망 VLAN (Bastion = VLAN 40)"
  type        = number
  default     = 40
}

variable "internal_cidr" {
  description = "Internal 네트워크 CIDR (게이트웨이, DNS 계산용)"
  type        = string
  default     = "172.16.23.0/24"
}

variable "mgmt_cidr" {
  description = "관리망 CIDR"
  type        = string
  default     = "172.16.24.0/24"
}

variable "internal_gateway" {
  description = "Internal VLAN 게이트웨이 VIP (pfSense CARP)"
  type        = string
  default     = "172.16.23.1"
}

variable "mgmt_gateway" {
  description = "관리망 VLAN 게이트웨이 VIP"
  type        = string
  default     = "172.16.24.1"
}

variable "dns_servers" {
  description = "VM이 사용할 DNS 서버 목록"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

#############################################
# K8s 클러스터 노드 정의
# - 각 노드의 VMID, 호스트, IP, 사양을 한곳에서 관리
#############################################

variable "control_plane_nodes" {
  description = "K8s Control Plane 노드 정의"
  type = list(object({
    name      = string
    vmid      = number
    pve_node  = string
    ip_suffix = number  # 172.16.23.X의 X
    cores     = number
    memory    = number  # MB
    disk_size = number  # GB
  }))
  default = [
    { name = "k8s-cp1", vmid = 110, pve_node = "kosa1", ip_suffix = 10, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp2", vmid = 111, pve_node = "kosa2", ip_suffix = 11, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp3", vmid = 112, pve_node = "kosa3", ip_suffix = 12, cores = 2, memory = 4096, disk_size = 40 },
  ]
}

variable "worker_nodes" {
  description = "K8s Worker 노드 정의"
  type = list(object({
    name      = string
    vmid      = number
    pve_node  = string
    ip_suffix = number
    cores     = number
    memory    = number
    disk_size = number
  }))
  default = [
    { name = "k8s-w1", vmid = 120, pve_node = "kosa3", ip_suffix = 20, cores = 4, memory = 8192, disk_size = 80 },
    { name = "k8s-w2", vmid = 121, pve_node = "kosa4", ip_suffix = 21, cores = 4, memory = 8192, disk_size = 80 },
  ]
}

variable "bastion_node" {
  description = "Bastion / Ansible runner VM 정의 (VLAN 40 관리망)"
  type = object({
    name      = string
    vmid      = number
    pve_node  = string
    ip_suffix = number
    cores     = number
    memory    = number
    disk_size = number
  })
  default = {
    name      = "bastion"
    vmid      = 130
    pve_node  = "kosa4"
    ip_suffix = 10
    cores     = 1
    memory    = 2048
    disk_size = 20
  }
}
