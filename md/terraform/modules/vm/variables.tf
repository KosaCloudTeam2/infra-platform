###############################################################################
# terraform/modules/vm/variables.tf
#
# 재사용 가능한 VM 모듈의 입력 변수.
# - 모든 변수는 호출하는 쪽(main.tf의 module 블록)에서 명시
# - 일부 변수는 default 있어 생략 가능
###############################################################################

variable "name" {
  description = "VM 이름 (Proxmox 표시명 및 cloud-init hostname)"
  type        = string
}

variable "vmid" {
  description = "Proxmox VMID (1~9999 사이 고유 정수)"
  type        = number
}

variable "pve_node" {
  description = "VM을 띄울 Proxmox 노드 (kosa1~kosa4)"
  type        = string
}

variable "template_vm_id" {
  description = "복제할 cloud-init 템플릿 VMID (예: 9000)"
  type        = number
}

variable "template_vm_node" {
  description = "템플릿이 위치한 Proxmox 노드 (clone 시 동일 노드 권장)"
  type        = string
}

variable "cores" {
  description = "vCPU 개수"
  type        = number
  default     = 2
}

variable "memory" {
  description = "메모리 (MB 단위). 예: 4096 = 4GB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "디스크 크기 (GB). 템플릿 디스크에서 resize"
  type        = number
  default     = 40
}

variable "datastore_id" {
  description = "디스크 저장소 (Proxmox storage 이름)"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "네트워크 브리지 (VLAN-aware vmbr0)"
  type        = string
}

variable "vlan_tag" {
  description = "VLAN 태그 (예: 30 = Internal, 40 = Management)"
  type        = number
}

variable "ip_address" {
  description = "VM에 할당할 정적 IPv4 (CIDR 형식, 예: 172.16.23.10/24)"
  type        = string
}

variable "gateway" {
  description = "기본 게이트웨이 IP (pfSense CARP VIP)"
  type        = string
}

variable "dns_servers" {
  description = "DNS 서버 목록"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_public_key" {
  description = "ubuntu 사용자에 등록할 SSH 공개키"
  type        = string
}

variable "tags" {
  description = "VM 태그 (Proxmox UI 식별/검색용. 예: [\"k8s\", \"worker\"])"
  type        = list(string)
  default     = []
}
