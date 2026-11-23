# ============================================
# Tier 10 · Network / Ingress
# Pi-hole (DNS) + NPM (reverse proxy) + Tailscale (subnet router)
# ============================================

module "tier10" {
  source = "./modules/lxc"

  for_each = local.tier10_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 10 Network/Ingress"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}


# ============================================
# Tier 20 · Data / Persistence (deferred until consumer exists — ADR-007)
# Postgres (shared) + Redis (shared) + pgAdmin
# ============================================

module "tier20" {
  source = "./modules/lxc"

  for_each = local.tier20_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 20 Data/Persistence"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}


# ============================================
# Tier 30 · Identity & Access Management
# Vaultwarden (password manager)
# ============================================

module "tier30" {
  source = "./modules/lxc"

  for_each = local.tier30_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 30 Identity & Access Mgmt"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}


# ============================================
# Tier 40 · Application Services
# Homepage (dashboard at root haytham.internal); Karakeep deferred (ADR-007)
# ============================================

module "tier40" {
  source = "./modules/lxc"

  for_each = local.tier40_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 40 Application Services"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}


# ============================================
# Tier 60 · Media Services
# Immich (self-contained 4-container bundle: server + ML + Valkey + Postgres/VectorChord)
# Device passthrough (/dev/dri) managed via ansible/host_devices.yml
# ============================================

module "tier60" {
  source = "./modules/lxc"

  for_each = local.tier60_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 60 Media Services"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}


# ============================================
# Tier 90 · Observability & Monitoring
# Uptime Kuma (service health monitoring)
# ============================================

module "tier90" {
  source = "./modules/lxc"

  for_each = local.tier90_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Tier 90 Observability & Monitoring"
  cores            = each.value.cores
  memory_mb        = each.value.memory
  swap_mb          = each.value.swap
  disk_gb          = each.value.disk_gb
  datastore_id     = "local-lvm"
  bridge           = local.network.bridge
  ip_address_cidr  = "${each.value.ip}/${local.network.cidr}"
  gateway          = local.network.gateway
  template_file_id = local.template_ubuntu_2404
  os_type          = "ubuntu"
  ssh_public_keys  = [trimspace(file(var.ssh_public_key_path))]
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}
