###############################################################################
# terraform/onprem/variables.tf
#
# 환경별로 달라지는 값들은 전부 변수화.
# 실제 값은 terraform.tfvars 에 작성 (gitignore!).
###############################################################################

#######################################
# 1) Proxmox 접속 정보
#######################################

variable "proxmox_endpoint" {
  description = "Proxmox API 엔드포인트 (예: https://192.168.21.2:8006/)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API 토큰 (root@pam!<id>=<secret> 형식)"
  type        = string
  sensitive   = true # terraform plan 출력에서 마스킹
}

variable "proxmox_ssh_private_key_path" {
  description = "Proxmox host SSH 접근용 private key 경로 (bpg provider 내부 사용)"
  type        = string
  default     = "~/.ssh/id_ed25519"
}

#######################################
# 2) Proxmox 노드 식별자
#  - VM을 어떤 PVE 호스트에 띄울지 지정할 때 사용
#######################################

variable "proxmox_nodes" {
  description = "Proxmox 노드 이름 매핑 (kosa1 ~ kosa4)"
  type        = map(string)
  default = {
    kosa1 = "kosa1"
    kosa2 = "kosa2"
    kosa3 = "kosa3"
    kosa4 = "kosa4"
  }
}

#######################################
# 3) Cloud-init 템플릿
#  - 사전에 Lab 2에서 만든 Ubuntu 22.04 cloud-init 템플릿 VM
#######################################

variable "template_vm_id" {
  description = "Ubuntu 22.04 cloud-init 템플릿 VMID"
  type        = number
  default     = 9000
}

variable "template_vm_node" {
  description = "템플릿 VM이 위치한 Proxmox 노드 (clone 시 동일 노드 권장)"
  type        = string
  default     = "kosa1"
}

#######################################
# 4) SSH 키 (cloud-init으로 VM에 주입)
#######################################

variable "ssh_public_key" {
  description = "ubuntu 사용자에 등록할 SSH 공개키 (cat ~/.ssh/kosa_iac.pub)"
  type        = string
}

#######################################
# 5) 네트워크 설정
#######################################

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

#######################################
# 6) K8s 클러스터 노드 정의 (CP3 + W3 + Bastion)
#  - 각 노드의 VMID, 호스트, IP, 사양을 한곳에서 관리
#  - 메모리 분배: CLAUDE.md 참고 (Proxmox 32GB, 사용률 75%)
#######################################

# Control Plane: HA 구성 (etcd quorum 3개 필수)
# - 각 PVE 노드에 1대씩 분산해서 단일 PVE 다운 시에도 cluster 유지
variable "control_plane_nodes" {
  description = "K8s Control Plane 노드 정의 (3개)"
  type = list(object({
    name      = string
    vmid      = number
    pve_node  = string
    ip_suffix = number # 172.16.23.X의 X
    cores     = number
    memory    = number # MB
    disk_size = number # GB
  }))
  default = [
    # PVE 노드 분산 (kosa1, kosa2는 pfSense와 공존)
    { name = "k8s-cp1", vmid = 110, pve_node = "kosa1", ip_suffix = 10, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp2", vmid = 111, pve_node = "kosa2", ip_suffix = 11, cores = 2, memory = 4096, disk_size = 40 },
    { name = "k8s-cp3", vmid = 112, pve_node = "kosa3", ip_suffix = 12, cores = 2, memory = 4096, disk_size = 40 },
  ]
}

# Worker: 3대 (3개 다른 PVE 노드에 완전 분산 → 단일 노드 장애 시에도 워커 2대 보존)
# - W1: kosa3, W2: kosa4, W3: kosa2 (pfSense 노드와 공존하지만 HA 우선)
# - 워커당 6GB로 합리적 사양 (Percona/Redis 한 개씩은 띄울 수 있음)
#
# HA 효과:
#   kosa1 다운 → CP1 lost, pfSense 페일오버 → 워커 3대 OK
#   kosa2 다운 → CP2 + W3 lost → 워커 2대 (W1, W2)
#   kosa3 다운 → CP3 + W1 + Bastion lost → 워커 2대 (W2, W3)
#   kosa4 다운 → W2 lost → 워커 2대 (W1, W3) ← 최대 1대만 잃음
variable "worker_nodes" {
  description = "K8s Worker 노드 정의 (3개, 3개 다른 PVE 노드에 분산)"
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
    { name = "k8s-w1", vmid = 120, pve_node = "kosa3", ip_suffix = 20, cores = 4, memory = 6144, disk_size = 80 },
    { name = "k8s-w2", vmid = 121, pve_node = "kosa4", ip_suffix = 21, cores = 4, memory = 6144, disk_size = 80 },
    { name = "k8s-w3", vmid = 122, pve_node = "kosa2", ip_suffix = 22, cores = 4, memory = 6144, disk_size = 80 },
  ]
}

# Bastion: Ansible runner + kubectl 도구 위치
# - VLAN 40 (Management 망)에 배치
# - 노트북에서 Bastion으로 SSH 후 모든 운영 명령 실행
# - kosa3에 배치 (kosa4 부담 줄임)
variable "bastion_node" {
  description = "Bastion / Ansible runner VM 정의"
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
    pve_node  = "kosa3"
    ip_suffix = 10
    cores     = 1
    memory    = 2048
    disk_size = 20
  }
}
