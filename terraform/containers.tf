# ============================================
# Zone 2 · Protected Data / Stateful P0 (.20-.29 -> CT 120-129)
# Vaultwarden (120) + Immich (121); Postgres (122) & Karakeep (123) deferred
# Pool: homelab-protected | Hypervisor protection = true
# ============================================

module "zone2_protected" {
  source = "./modules/lxc"

  for_each = local.zone2_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Zone 2 Protected Data"
  pool_id          = each.value.pool_id
  protection       = each.value.protected
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
  ssh_public_keys  = local.ssh_public_keys
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}

# ============================================
# Zone 3 · Core Infra / Network (.30-.39 -> CT 130-139)
# Pi-hole (130) + NPM (131) + Tailscale (132); Redis (133) deferred
# Pool: homelab-ephemeral | Freely rebuildable
# ============================================

module "zone3_infra" {
  source = "./modules/lxc"

  for_each = local.zone3_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Zone 3 Core Infra"
  pool_id          = each.value.pool_id
  protection       = each.value.protected
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
  ssh_public_keys  = local.ssh_public_keys
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}

# ============================================
# Zone 4 · Ephemeral Apps & Ops (.40-.49 -> CT 140-149)
# Homepage (140) + Uptime Kuma (141); pgAdmin (142) deferred
# Pool: homelab-ephemeral | Freely rebuildable
# ============================================

module "zone4_apps" {
  source = "./modules/lxc"

  for_each = local.zone4_containers

  node_name        = local.target_node
  vm_id            = each.value.ctid
  hostname         = each.value.hostname
  description      = "Managed by Terraform - Zone 4 Ephemeral Apps & Ops"
  pool_id          = each.value.pool_id
  protection       = each.value.protected
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
  ssh_public_keys  = local.ssh_public_keys
  root_password    = var.ct_root_password
  tags             = each.value.tags
  nesting          = true
}
