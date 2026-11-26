locals {
  # ============================================
  # Base config
  # ============================================
  domain      = "haytham.internal"
  target_node = "haytham" # node name as shown in Datacenter -> haytham in the Proxmox UI

  network = {
    bridge  = "vmbr0"
    gateway = "192.168.100.1"
    cidr    = 24 # /24, same as subnet mask 255.255.255.0
  }

  # ============================================
  # Security-Zone & ID Scheme (ADR-008)
  # ------------------------------------------------------------------
  # Universal Formula (BOTH VMs & LXCs): ID = 100 + last_octet
  #
  #   Zone 0 (Host & VMs)   : .1 Router, .2 Proxmox haytham, .3-.9 VMs (VM 103 HAOS deferred)
  #                           -> Out-of-Band, ZERO terraform@pve ACL
  #   Zone 1 (Immutable)    : .10-.19 (CT 110-119) — CT 110 Infisical (.10)
  #                           -> Out-of-Band (scripts/zone1/bootstrap-infisical.sh),
  #                              NEVER declared here, protection=1, ZERO terraform@pve ACL
  #   Zone 2 (Protected P0) : .20-.29 (CT 120-129) — pool homelab-protected, protection=true
  #   Zone 3 (Core Infra)   : .30-.39 (CT 130-139) — pool homelab-ephemeral, protection=false
  #   Zone 4 (Apps & Ops)   : .40-.49 (CT 140-149) — pool homelab-ephemeral, protection=false
  #   Zone 5 (Sandbox/Lab)  : .50-.59 (CT 150-159) — pool homelab-ephemeral (future)
  #   Open Reserve          : .60-.99 (blocked in UFW until expanded)
  #   DHCP Pool             : .100-.254 (LAN clients, blocked in UFW)
  # ============================================

  # Lean 8 GB RAM Phase 1 scope (ADR-007 + ADR-008).
  # Toggle `enabled = true` to revive deferred services after the 16 GB RAM upgrade
  # or once a concrete consumer exists.
  containers = {
    # --- Zone 2 · Protected Data / Stateful P0 (pool: homelab-protected, protection=true) ---
    vaultwarden = {
      enabled   = true
      zone      = 2
      ctid      = 120
      hostname  = "vaultwarden"
      ip        = "192.168.100.20"
      cores     = 1
      memory    = 256
      swap      = 512
      disk_gb   = 8
      protected = true
      pool_id   = "homelab-protected"
      tags      = ["zone2-protected", "password-manager"]
    }
    immich = {
      enabled   = true
      zone      = 2
      ctid      = 121
      hostname  = "immich"
      ip        = "192.168.100.21"
      cores     = 3
      memory    = 4096
      swap      = 2048
      disk_gb   = 500
      protected = true
      pool_id   = "homelab-protected"
      tags      = ["zone2-protected", "photos"]
    }
    postgres = {
      enabled   = false # Deferred until consumer exists (ADR-007)
      zone      = 2
      ctid      = 122
      hostname  = "postgres"
      ip        = "192.168.100.22"
      cores     = 1
      memory    = 512
      swap      = 512
      disk_gb   = 16
      protected = true
      pool_id   = "homelab-protected"
      tags      = ["zone2-protected", "database"]
    }
    karakeep = {
      enabled   = false # Deferred until post-Phase 1 / 16 GB RAM (ADR-007)
      zone      = 2
      ctid      = 123
      hostname  = "karakeep"
      ip        = "192.168.100.23"
      cores     = 2
      memory    = 4096
      swap      = 1024
      disk_gb   = 24
      protected = true
      pool_id   = "homelab-protected"
      tags      = ["zone2-protected", "bookmarks"]
    }

    # --- Zone 3 · Core Infra / Network (pool: homelab-ephemeral, freely rebuildable) ---
    pihole = {
      enabled   = true
      zone      = 3
      ctid      = 130
      hostname  = "pihole"
      ip        = "192.168.100.30"
      cores     = 1
      memory    = 512
      swap      = 512
      disk_gb   = 4
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone3-infra", "dns"]
    }
    npm = {
      enabled   = true
      zone      = 3
      ctid      = 131
      hostname  = "npm"
      ip        = "192.168.100.31"
      cores     = 1
      memory    = 384
      swap      = 512
      disk_gb   = 8
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone3-infra", "reverse-proxy"]
    }
    tailscale = {
      enabled   = true
      zone      = 3
      ctid      = 132
      hostname  = "tailscale"
      ip        = "192.168.100.32"
      cores     = 1
      memory    = 256
      swap      = 256
      disk_gb   = 2
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone3-infra", "vpn"]
    }
    redis = {
      enabled   = false # Deferred until consumer exists (ADR-007)
      zone      = 3
      ctid      = 133
      hostname  = "redis"
      ip        = "192.168.100.33"
      cores     = 1
      memory    = 256
      swap      = 256
      disk_gb   = 4
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone3-infra", "cache"]
    }

    # --- Zone 4 · Ephemeral Apps & Ops (pool: homelab-ephemeral, freely rebuildable) ---
    homepage = {
      enabled   = true
      zone      = 4
      ctid      = 140
      hostname  = "homepage"
      ip        = "192.168.100.40"
      cores     = 1
      memory    = 384
      swap      = 512
      disk_gb   = 4
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone4-apps", "dashboard"]
    }
    uptime_kuma = {
      enabled   = true
      zone      = 4
      ctid      = 141
      hostname  = "uptime-kuma"
      ip        = "192.168.100.41"
      cores     = 1
      memory    = 384
      swap      = 512
      disk_gb   = 8
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone4-ops", "monitoring"]
    }
    pgadmin = {
      enabled   = false # Deferred with Postgres (ADR-007)
      zone      = 4
      ctid      = 142
      hostname  = "pgadmin"
      ip        = "192.168.100.42"
      cores     = 1
      memory    = 512
      swap      = 512
      disk_gb   = 8
      protected = false
      pool_id   = "homelab-ephemeral"
      tags      = ["zone4-ops", "admin-tool"]
    }
  }

  # Dual SSH public keys: revocable Control Node key + optional Windows Break-Glass/Backup-Pull key
  ssh_public_keys = compact([
    trimspace(file(var.ssh_public_key_path)),
    var.breakglass_ssh_public_key_path != "" ? trimspace(file(var.breakglass_ssh_public_key_path)) : "",
  ])

  # Per-zone active subsets used for for_each in containers.tf
  zone2_containers = { for k, v in local.containers : k => v if v.zone == 2 && v.enabled }
  zone3_containers = { for k, v in local.containers : k => v if v.zone == 3 && v.enabled }
  zone4_containers = { for k, v in local.containers : k => v if v.zone == 4 && v.enabled }
}
