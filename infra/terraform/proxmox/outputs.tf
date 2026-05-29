output "planned_vm_inventory" {
  description = "VM values used by Terraform and Ansible inventory checks."
  value = {
    for name, vm in var.vm_definitions : name => {
      vm_id     = vm.vm_id
      node_name = vm.node_name
      role      = vm.role
      cpu_cores = vm.cpu_cores
      memory_mb = vm.memory_mb
      addresses = [
        for network in vm.networks : network.ipv4_address
        if try(network.ipv4_address, null) != null
      ]
      tags = vm.tags
    }
  }
}

output "terraform_import_ids" {
  description = "Import IDs for the current Proxmox VMs."
  value = {
    for name, vm in var.vm_definitions : name => "${vm.node_name}/${vm.vm_id}"
  }
}
