# Haytham Homelab

Infrastructure-as-Code and dual-use Knowledge Base for a single-node Proxmox VE homelab (`haytham` @ `192.168.100.2`, Lenovo ThinkCentre M910q Tiny — Intel i5 7th gen / HD 630 Quick Sync, 8 GB RAM → 16 GB planned, 1 TB SSD).

Built on a **4-layer Zero-Trust Disposable Control Node** architecture with **Security-Zone Addressing (`ID = 100 + last_octet`)** and an out-of-band **Zone 1 Immutable Infisical** secrets manager (`kb/decisions/ADR-008-zero-trust-security-zones-and-infisical.md`).

## Security-Zone Map (`ID = 100 + last_octet`, 10 Slots / Zone)

| Zone | ID / IP Range | Lifecycle & Protection | Active Phase 1 Services |
|---|---|---|---|
| **Zone 0** | Host / `VM 103–109` (`.2`, `.3–.9`) | Physical Host & VMs (out-of-band, ZERO `terraform@pve` ACL) | Proxmox `haytham` (`.2`) + Host Backups; deferred: `VM 103` HAOS (`.3`) |
| **Zone 1** | `CT 110–119` (`.10–.19`) | **Immutable Core** (outside Terraform, `protection=1`, ZERO ACL) | `110` **Infisical** (`.10`) |
| **Zone 2** | `CT 120–129` (`.20–.29`) | **Protected Data P0** (`homelab-protected`, `protection=1`, NO destroy) | `120` **Vaultwarden** (`.20`), `121` **Immich** (`.21`) *(deferred: `122` Postgres, `123` Karakeep)* |
| **Zone 3** | `CT 130–139` (`.30–.39`) | **Core Infra / Network** (`homelab-ephemeral`, freely rebuildable) | `130` **Pi-hole** (`.30`), `131` **NPM** (`.31`), `132` **Tailscale** (`.32`) *(deferred: `133` Redis)* |
| **Zone 4** | `CT 140–149` (`.40–.49`) | **Ephemeral Apps & Ops** (`homelab-ephemeral`, freely rebuildable) | `140` **Homepage** (`.40`), `141` **Uptime Kuma** (`.41`) *(deferred: `142` pgAdmin)* |
| **Zone 5** | `CT 150–159` (`.50–.59`) | **Sandbox / Lab** (`homelab-ephemeral`) | *(Reserved for future AI/dev experiments)* |

## Repository Layout

- `terraform/` — Declarative LXC shells for Zones 2–4 (`bpg/proxmox`, `pool_id`, `protection`, dual SSH keys).
- `ansible/` — Zone playbooks (`host_devices.yml`, `zone3_infra.yml`, `zone2_protected.yml`, `zone4_apps.yml`, `host_backups.yml`) with runtime RAM-only secrets from Zone 1 Infisical.
- `scripts/`
  - `hardening/` — Windows Defender Firewall VMnet8 lockdown (`harden-windows-firewall.ps1`) + Control Node UFW & kernel UID LAN-block (`harden-control-node-ufw.sh`).
  - `zone1/` — Out-of-band Zone 1 Infisical bootstrap (`bootstrap-infisical.sh`).
  - `proxmox/` — Hypervisor RBAC pools & `protection=1` lock/unlock (`harden-pve-rbac.sh`).
  - `control-node/` — Disposable VM bootstrap (`bootstrap-control-node.sh`), OS privilege split (`setup-privilege-split.sh`), `age` recovery bundle (`ops-bundle.sh`), and audited wrappers (`wrappers/ops-*`).
  - `pull-homelab-backups.{bat,sh}` — Pull-only off-host backup sync (Windows inbox `ssh.exe`+`tar.exe` or Linux/WSL `rsync`) using a separate Windows-only SSH key.
- `kb/` — Canonical Knowledge Base (architecture, ADRs, per-service specs, operational runbooks, troubleshooting).

## Key Runbooks

1. **Harden Windows/VMware, Bootstrap Zone 1 Infisical & Control Node:** [kb/operations/control-node-hardening-and-recovery.md](kb/operations/control-node-hardening-and-recovery.md)
2. **Build Homelab from Scratch (Zones 2–4):** [kb/operations/build-from-scratch.md](kb/operations/build-from-scratch.md)
3. **Backup & Restore Drills (Track 1 restic + Track 2 Immich):** [kb/operations/backup-and-restore.md](kb/operations/backup-and-restore.md)
4. **Secret Rotation (Infisical UI):** [kb/operations/secret-rotation.md](kb/operations/secret-rotation.md)
5. **Patching & Reboot Order:** [kb/operations/update-and-reboot.md](kb/operations/update-and-reboot.md)
