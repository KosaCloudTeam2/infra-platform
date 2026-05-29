locals {
  vm_disks = {
    for name, vm in var.vm_definitions : name => concat(
      [
        merge(vm.primary_disk, {
          datastore_id = coalesce(vm.primary_disk.datastore_id, vm.datastore_id)
        })
      ],
      vm.extra_disks
    )
  }

  vm_ip_configs = {
    for name, vm in var.vm_definitions : name => [
      for network in vm.networks : network
      if try(network.ipv4_address, null) != null
    ]
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = var.vm_definitions

  name        = each.value.name
  description = try(each.value.description, null)
  tags        = each.value.tags

  node_name = each.value.node_name
  vm_id     = each.value.vm_id

  started = each.value.started
  on_boot = each.value.on_boot

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-pci"

  clone {
    vm_id     = var.template_vm_id
    node_name = var.template_node_name
    full      = true
    retries   = 3
  }

  agent {
    enabled = true
    trim    = each.value.agent_trim
  }

  cpu {
    cores = each.value.cpu_cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = 0
  }

  dynamic "disk" {
    for_each = local.vm_disks[each.key]

    content {
      interface    = disk.value.interface
      datastore_id = disk.value.datastore_id
      size         = disk.value.size_gb
      cache        = disk.value.cache
      discard      = disk.value.discard
      aio          = disk.value.aio
      iothread     = disk.value.iothread
      backup       = disk.value.backup
      replicate    = disk.value.replicate
      ssd          = disk.value.ssd
    }
  }

  dynamic "network_device" {
    for_each = each.value.networks

    content {
      bridge      = network_device.value.bridge
      model       = network_device.value.model
      vlan_id     = try(network_device.value.vlan_id, null)
      firewall    = network_device.value.firewall
      mtu         = try(network_device.value.mtu, null)
      mac_address = try(network_device.value.mac_address, null)
    }
  }

  dynamic "initialization" {
    for_each = each.value.cloud_init ? [each.value] : []

    content {
      datastore_id = var.cloud_init_datastore_id
      interface    = "ide2"

      dns {
        servers = var.dns_servers
      }

      user_account {
        username = coalesce(try(each.value.cloud_user, null), var.default_user)
        keys     = var.ssh_public_keys
      }

      dynamic "ip_config" {
        for_each = local.vm_ip_configs[each.key]

        content {
          ipv4 {
            address = ip_config.value.ipv4_address
            gateway = try(ip_config.value.gateway, null)
          }
        }
      }
    }
  }

  operating_system {
    type = "l26"
  }

  serial_device {}

  vga {
    type = "serial0"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      agent[0].type,
      clone,
      keyboard_layout,
    ]
  }
}
