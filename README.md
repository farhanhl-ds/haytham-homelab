# Haytham Homelab

Single-node Proxmox VE homelab on a **Lenovo ThinkCentre M910q Tiny** (**Intel Core i5 7th gen / HD 630 Quick Sync, 8 GB RAM → 16 GB planned, 1 TB SSD**). Infrastructure as Code with Terraform (LXC shells) and Ansible (host devices, app configuration, automated backups).

## Architecture

```
Terraform (bpg/proxmox)     →     Ansible (WSL control node)
LXC shell, CPU/RAM/swap     →     Host device passthrough (/dev/net/tun, /dev/dri)
Network + static IP         →     Package install, Docker Compose, app config
Cloud-init user + SSH key   →     Automated local-network backups (restic + vzdump)
```

Terraform stops when each container exists with the correct IP and is SSH-reachable. Everything after is Ansible (one role per app, idempotent).

## Phase 1 Tier Map (Lean 8 GB Stack — `ADR-007`)

| Tier | Scope | Active Services | CTIDs | IPs |
|---|---|---|---|---|
| 10 | Network / Ingress | Pi-hole, NPM, Tailscale | 110, 120, 130 | .11, .12, .13 |
| 30 | Identity & Access | Vaultwarden | 320 | .32 |
| 40 | Application | Homepage (root `haytham.internal`) | 440 | .44 |
| 60 | Media | Immich (500 GB, Intel Quick Sync) | 610 | .61 |
| 80 | Backup & DR | Host `restic` + `vzdump` + WSL SSH pull | host | .2 |
| 90 | Observability | Uptime Kuma | 910 | .91 |

*Deferred until 16 GB RAM upgrade or concrete DB consumer (preserved in-repo): Tier 20 (`210` Postgres, `220` Redis, `230` pgAdmin), Karakeep (`420`), HAOS (`VM 100`).*

Domain base: `haytham.internal` (RFC 9476). Wildcard `*.haytham.internal → NPM (.12)` via Pi-hole DNS (and Tailscale Split DNS remotely). One self-signed wildcard cert reused across all NPM Proxy Hosts.

## Directory Layout

```
haytham-homelab/
├── terraform/                 # Proxmox LXC provisioning (bpg/proxmox)
│   ├── locals.tf              # Container definitions (enabled flag + swap)
│   ├── containers.tf          # Per-tier module calls (10/20/30/40/60/90)
│   └── modules/lxc/           # Reusable LXC module
├── ansible/                   # App & host configuration
│   ├── host_devices.yml       # Proxmox /dev/net/tun & /dev/dri passthrough
│   ├── tier{10,20,30,40,60,80,90}.yml
│   ├── group_vars/            # Per-group vars + inline !vault secrets
│   └── roles/                 # docker, pve_devices, pihole, npm, tailscale,
│                              # vaultwarden, homepage, immich, uptime_kuma,
│                              # backup (+ deferred postgres, redis, pgadmin, karakeep)
├── scripts/
│   └── pull-homelab-backups.sh  # Off-host WSL SSH pull (zero cloud, zero Samba)
└── kb/                        # Canonical Knowledge Base (RAG-ready Markdown)
```

## Build Sequence (High Level)

1. Provision 7 active LXCs with `terraform init && terraform apply`.
2. From WSL (`ansible/`): run `host_devices.yml → tier10.yml → tier30.yml → tier40.yml → tier60.yml → tier90.yml → tier80.yml`.
3. Complete manual gaps (NPM Proxy Hosts + cert import, Tailscale route approval + Split DNS, Vaultwarden signup lock, Immich Quick Sync toggle, Uptime Kuma monitors, Windows Task Scheduler backup pull).

Full runbook: [kb/operations/build-from-scratch.md](kb/operations/build-from-scratch.md)

## Knowledge Base Entry Points

- [kb/index.md](kb/index.md) — KB index & status semantics
- [kb/architecture/overview.md](kb/architecture/overview.md) — Hardware & architecture overview
- [kb/decisions/ADR-007-lean-8gb-phase1.md](kb/decisions/ADR-007-lean-8gb-phase1.md) — Lean 8 GB scope & deferrals
- [kb/reference/ip-ctid-matrix.md](kb/reference/ip-ctid-matrix.md) — Canonical IP ↔ CTID ↔ DNS matrix
- [kb/roadmap/build-sequence.md](kb/roadmap/build-sequence.md) — Chronological build order
- [kb/operations/backup-and-restore.md](kb/operations/backup-and-restore.md) — Two-track zero-cloud backup & restore drills
- [kb/operations/secret-rotation.md](kb/operations/secret-rotation.md) — Vault secret rotation

## Secrets Handling

Never commit `.vault_pass`, `terraform.tfvars`, `service-account.txt`, or `*.tfstate*` (all gitignored). Generate secrets with `openssl rand`, encrypt inline with `ansible-vault encrypt_string`, and run `unset SECRET; history -c`.
