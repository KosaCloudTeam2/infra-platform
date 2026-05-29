proxmox_endpoint = "https://192.168.21.4:8006/"
proxmox_insecure = true

template_node_name      = "kosa1"
template_vm_id          = 9000
cloud_init_datastore_id = "local-lvm"

ssh_public_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMmlQ8CPeQbIvYXpG64j8ZKDxhrjqe8yg1SNE6b0qTso kosa-iac",
]

vm_definitions = {
  "k8s-cp1" = {
    vm_id     = 210
    name      = "k8s-cp1"
    node_name = "kosa4"
    role      = "control-plane"
    tags      = ["control-plane", "k8s", "managed-by-terraform"]
    cpu_cores = 2
    memory_mb = 8192
    primary_disk = {
      size_gb = 40
    }
    extra_disks = [
      {
        interface    = "scsi1"
        datastore_id = "local-lvm"
        size_gb      = 10
      },
    ]
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:EE:69:10"
        ipv4_address = "172.16.23.10/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:F8:3A:03"
        ipv4_address = "10.10.10.110/24"
      },
    ]
  }

  "k8s-cp2" = {
    vm_id     = 211
    name      = "k8s-cp2"
    node_name = "kosa2"
    role      = "control-plane"
    tags      = ["control-plane", "k8s", "managed-by-terraform"]
    cpu_cores = 2
    memory_mb = 8192
    primary_disk = {
      size_gb = 40
    }
    extra_disks = [
      {
        interface    = "scsi1"
        datastore_id = "local-lvm"
        size_gb      = 10
      },
    ]
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:9C:46:FA"
        ipv4_address = "172.16.23.11/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:22:32:74"
        ipv4_address = "10.10.10.111/24"
      },
    ]
  }

  "k8s-cp3" = {
    vm_id     = 212
    name      = "k8s-cp3"
    node_name = "kosa3"
    role      = "control-plane"
    tags      = ["control-plane", "k8s", "managed-by-terraform"]
    cpu_cores = 2
    memory_mb = 8192
    primary_disk = {
      size_gb = 40
    }
    extra_disks = [
      {
        interface    = "scsi1"
        datastore_id = "local-lvm"
        size_gb      = 10
      },
    ]
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:2E:5D:AE"
        ipv4_address = "172.16.23.12/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:06:B8:CF"
        ipv4_address = "10.10.10.112/24"
      },
    ]
  }

  "k8s-w1" = {
    vm_id      = 220
    name       = "k8s-w1"
    node_name  = "kosa3"
    role       = "worker"
    tags       = ["k8s", "managed-by-terraform", "worker"]
    cpu_cores  = 4
    memory_mb  = 8192
    agent_trim = true
    primary_disk = {
      size_gb = 80
    }
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:BF:46:28"
        ipv4_address = "172.16.23.20/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:4E:B5:A0"
        ipv4_address = "10.10.10.120/24"
      },
    ]
  }

  "k8s-w2" = {
    vm_id      = 221
    name       = "k8s-w2"
    node_name  = "kosa4"
    role       = "worker"
    tags       = ["k8s", "managed-by-terraform", "worker"]
    cpu_cores  = 4
    memory_mb  = 8192
    agent_trim = true
    primary_disk = {
      size_gb = 80
    }
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:EA:94:C4"
        ipv4_address = "172.16.23.21/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:34:C8:B2"
        ipv4_address = "10.10.10.121/24"
      },
    ]
  }

  "k8s-w3" = {
    vm_id      = 222
    name       = "k8s-w3"
    node_name  = "kosa2"
    role       = "worker"
    tags       = ["k8s", "managed-by-terraform", "worker"]
    cpu_cores  = 4
    memory_mb  = 8192
    agent_trim = true
    primary_disk = {
      size_gb = 80
    }
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:1E:AE:46"
        ipv4_address = "172.16.23.22/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:64:A4:B1"
        ipv4_address = "10.10.10.122/24"
      },
    ]
  }

  "k8s-sys1" = {
    vm_id      = 223
    name       = "k8s-sys1"
    node_name  = "kosa1"
    role       = "worker"
    tags       = ["k8s", "managed-by-terraform", "worker"]
    cpu_cores  = 4
    memory_mb  = 16384
    agent_trim = true
    primary_disk = {
      size_gb = 80
    }
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 30
        mac_address  = "BC:24:11:7E:BF:AE"
        ipv4_address = "172.16.23.23/24"
        gateway      = "172.16.23.1"
      },
      {
        bridge       = "vmbr1"
        mtu          = 9000
        mac_address  = "BC:24:11:06:39:50"
        ipv4_address = "10.10.10.123/24"
      },
    ]
  }

  "bastion" = {
    vm_id     = 230
    name      = "bastion"
    node_name = "kosa3"
    role      = "bastion"
    tags      = ["bastion", "managed-by-terraform", "mgmt"]
    cpu_cores = 1
    memory_mb = 8192
    primary_disk = {
      size_gb = 20
    }
    networks = [
      {
        bridge       = "vmbr0"
        vlan_id      = 40
        mac_address  = "BC:24:11:AB:F0:1F"
        ipv4_address = "172.16.24.10/24"
        gateway      = "172.16.24.1"
      },
      {
        bridge      = "vmbr1"
        firewall    = true
        mac_address = "BC:24:11:66:BA:95"
      },
    ]
  }
}
