variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint. Credentials must be supplied with PROXMOX_VE_* environment variables."
  type        = string
  default     = "https://192.168.21.4:8006/"
}

variable "proxmox_insecure" {
  description = "Allow the current self-signed Proxmox TLS certificate."
  type        = bool
  default     = true
}

variable "template_node_name" {
  description = "Node that hosts the Ubuntu cloud-init template."
  type        = string
  default     = "kosa1"
}

variable "template_vm_id" {
  description = "Ubuntu cloud-init template VMID observed in Proxmox."
  type        = number
  default     = 9000
}

variable "ssh_public_keys" {
  description = "Public SSH keys injected through cloud-init. Do not put private keys here."
  type        = list(string)
  default     = []
}

variable "default_user" {
  description = "Cloud-init user for Ubuntu VMs."
  type        = string
  default     = "ubuntu"
}

variable "dns_servers" {
  description = "DNS servers injected through cloud-init."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "cloud_init_datastore_id" {
  description = "Datastore for cloud-init disks."
  type        = string
  default     = "local-lvm"
}

variable "vm_definitions" {
  description = "Observed Proxmox VM definitions for the on-prem Kubernetes and bastion baseline."
  type = map(object({
    vm_id       = number
    name        = string
    node_name   = string
    description = optional(string)
    tags        = optional(list(string), [])
    role        = optional(string, "generic")

    cpu_cores    = number
    memory_mb    = number
    started      = optional(bool, true)
    on_boot      = optional(bool, true)
    agent_trim   = optional(bool, false)
    cloud_init   = optional(bool, true)
    cloud_user   = optional(string)
    datastore_id = optional(string, "ceph-rbd-team2")

    primary_disk = object({
      size_gb      = number
      interface    = optional(string, "scsi0")
      datastore_id = optional(string)
      cache        = optional(string, "none")
      discard      = optional(string, "on")
      aio          = optional(string, "io_uring")
      iothread     = optional(bool, false)
      backup       = optional(bool, true)
      replicate    = optional(bool, true)
      ssd          = optional(bool, true)
    })

    extra_disks = optional(list(object({
      size_gb      = number
      interface    = string
      datastore_id = string
      cache        = optional(string, "none")
      discard      = optional(string, "ignore")
      aio          = optional(string, "io_uring")
      iothread     = optional(bool, false)
      backup       = optional(bool, true)
      replicate    = optional(bool, true)
      ssd          = optional(bool, false)
    })), [])

    networks = list(object({
      bridge       = optional(string, "vmbr0")
      model        = optional(string, "virtio")
      vlan_id      = optional(number)
      firewall     = optional(bool, false)
      mtu          = optional(number)
      mac_address  = optional(string)
      ipv4_address = optional(string)
      gateway      = optional(string)
    }))
  }))
}
