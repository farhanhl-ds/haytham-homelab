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
  # Tier & CTID scheme
  # ------------------------------------------------------------------
  # 10 = Network / Ingress            70 = (reserved) CI/CD & Automation
  # 20 = Data / Persistence           80 = Backup & DR (host-managed)
  # 30 = Identity & Access Mgmt       90 = Observability & Monitoring
  # 40 = Application Services
  # 50 = AI / ML Services
  # 60 = Media Services
  #
  # IP formula   : last_octet = CTID / 10
  # Static range : 192.168.100.2  - 192.168.100.99
  # DHCP pool    : 192.168.100.100 - 192.168.100.254
  # Companion block (used when CTID/10 is not a round number, e.g. CTID x11-x19):
  #                192.168.100.180 - 192.168.100.199 (recorded manually per case)
  # ============================================

  # Lean 8 GB RAM Phase 1 scope (see kb/decisions/ADR-007-lean-8gb-phase1.md).
  # Toggle `enabled = true` to revive deferred services after the 16 GB RAM upgrade
  # or once a concrete consumer exists.
  containers = {
    # --- Tier 10 · Network / Ingress ---
    pihole = {
      enabled  = true
      tier     = 10
      ctid     = 110
      hostname = "pihole"
      ip       = "192.168.100.11"
      cores    = 1
      memory   = 512
      swap     = 512
      disk_gb  = 4
      tags     = ["tier-network", "dns"]
    }
    npm = {
      enabled  = true
      tier     = 10
      ctid     = 120
      hostname = "npm"
      ip       = "192.168.100.12"
      cores    = 1
      memory   = 384
      swap     = 512
      disk_gb  = 8
      tags     = ["tier-network", "reverse-proxy"]
    }
    tailscale = {
      enabled  = true
      tier     = 10
      ctid     = 130
      hostname = "tailscale"
      ip       = "192.168.100.13"
      cores    = 1
      memory   = 256
      swap     = 256
      disk_gb  = 2
      tags     = ["tier-network", "vpn"]
    }

    # --- Tier 20 · Data / Persistence (deferred until consumer exists — ADR-007) ---
    postgres = {
      enabled  = false
      tier     = 20
      ctid     = 210
      hostname = "postgres"
      ip       = "192.168.100.21"
      cores    = 1
      memory   = 512
      swap     = 512
      disk_gb  = 16
      tags     = ["tier-data", "database"]
    }
    redis = {
      enabled  = false
      tier     = 20
      ctid     = 220
      hostname = "redis"
      ip       = "192.168.100.22"
      cores    = 1
      memory   = 256
      swap     = 256
      disk_gb  = 4
      tags     = ["tier-data", "cache"]
    }
    pgadmin = {
      enabled  = false
      tier     = 20
      ctid     = 230
      hostname = "pgadmin"
      ip       = "192.168.100.23"
      cores    = 1
      memory   = 512
      swap     = 512
      disk_gb  = 8
      tags     = ["tier-data", "admin-tool"]
    }

    # --- Tier 30 · Identity & Access Management ---
    vaultwarden = {
      enabled  = true
      tier     = 30
      ctid     = 320
      hostname = "vaultwarden"
      ip       = "192.168.100.32"
      cores    = 1
      memory   = 256
      swap     = 512
      disk_gb  = 8
      tags     = ["tier-identity", "password-manager"]
    }
    # NOTE: Infisical (330) deferred — see kb/decisions/ADR-006-infisical-deferred.md.

    # --- Tier 40 · Application Services ---
    karakeep = {
      enabled  = false # Deferred until post-Phase 1 evaluation / 16 GB RAM (ADR-007)
      tier     = 40
      ctid     = 420
      hostname = "karakeep"
      ip       = "192.168.100.42"
      cores    = 2
      memory   = 4096
      swap     = 1024
      disk_gb  = 24
      tags     = ["tier-app", "bookmarks"]
    }
    homepage = {
      enabled  = true
      tier     = 40
      ctid     = 440
      hostname = "homepage"
      ip       = "192.168.100.44"
      cores    = 1
      memory   = 384
      swap     = 512
      disk_gb  = 4
      tags     = ["tier-app", "dashboard"]
    }

    # --- Tier 60 · Media Services ---
    immich = {
      enabled  = true
      tier     = 60
      ctid     = 610
      hostname = "immich"
      ip       = "192.168.100.61"
      cores    = 3
      memory   = 4096
      swap     = 2048
      disk_gb  = 500
      tags     = ["tier-media", "photos"]
    }

    # --- Tier 90 · Observability & Monitoring ---
    uptime_kuma = {
      enabled  = true
      tier     = 90
      ctid     = 910
      hostname = "uptime-kuma"
      ip       = "192.168.100.91"
      cores    = 1
      memory   = 384
      swap     = 512
      disk_gb  = 8
      tags     = ["tier-observability", "monitoring"]
    }
  }

  # Per-tier active subsets, used for for_each in the root module calls
  tier10_containers = { for k, v in local.containers : k => v if v.tier == 10 && v.enabled }
  tier20_containers = { for k, v in local.containers : k => v if v.tier == 20 && v.enabled }
  tier30_containers = { for k, v in local.containers : k => v if v.tier == 30 && v.enabled }
  tier40_containers = { for k, v in local.containers : k => v if v.tier == 40 && v.enabled }
  tier60_containers = { for k, v in local.containers : k => v if v.tier == 60 && v.enabled }
  tier90_containers = { for k, v in local.containers : k => v if v.tier == 90 && v.enabled }
}
