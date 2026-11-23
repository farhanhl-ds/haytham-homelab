resource "proxmox_virtual_environment_container" "this" {
  description   = var.description
  node_name     = var.node_name
  vm_id         = var.vm_id
  unprivileged  = var.unprivileged
  start_on_boot = var.start_on_boot
  started       = true
  tags          = var.tags

  dynamic "features" {
    for_each = var.nesting ? [1] : []
    content {
      nesting = true
    }
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = var.swap_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = var.disk_gb
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = var.os_type
  }

  initialization {
    hostname = var.hostname

    dns {
      servers = var.dns_servers
    }

    ip_config {
      ipv4 {
        address = var.ip_address_cidr
        gateway = var.gateway
      }
    }

    user_account {
      keys     = var.ssh_public_keys
      password = var.root_password
    }
  }

  network_interface {
    name   = "veth0"
    bridge = var.bridge
  }

  lifecycle {
    # Changing the SSH key/password in initialization makes the provider want
    # to replace the container. Device passthrough (/dev/net/tun, /dev/dri) is
    # managed via Proxmox host Ansible (host_devices.yml) because non-root API
    # tokens receive HTTP 403 on device_passthrough. Ignore both so apply never
    # destroys containers or strips host-managed devices.
    ignore_changes = [
      initialization[0].user_account,
      device_passthrough,
    ]
  }
}
