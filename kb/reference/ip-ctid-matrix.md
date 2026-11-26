---
id: ref-ip-ctid-matrix
title: IP and CTID Matrix (canonical)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [reference, ip, ctid, network, zones]
retrievable: true
---

# IP and CTID Matrix (canonical)

> The only source of truth for Security Zone ↔ VMID/CTID ↔ IP ↔ hostname (`ADR-008`). All other pages link here.

## Universal Addressing Scheme (`ID = 100 + last_octet`)

- Subnet `192.168.100.0/24`, gateway `192.168.100.1`.
- **Universal formula for BOTH VMs and LXCs:** `Proxmox ID = 100 + last_octet` (e.g., `.10 → CT 110`, `.21 → CT 121`, `.3 → VM 103`).
- **10 slots per Security Zone:**
  - `.1` Router / Gateway; `.2` Proxmox host `haytham` (+ Host Backups).
  - `.3–.9` (`VM 103–109`): **Zone 0 · Virtual Machines** (out-of-band, zero `terraform@pve` ACL).
  - `.10–.19` (`CT 110–119`): **Zone 1 · Immutable Core** (`homelab-immutable`, outside Terraform, `protection=1`, zero `terraform@pve` ACL).
  - `.20–.29` (`CT 120–129`): **Zone 2 · Protected Data / Stateful P0** (`homelab-protected`, `protection=1`, `HomelabProtectedOps` NO destroy, P0 Backup).
  - `.30–.39` (`CT 130–139`): **Zone 3 · Core Infra / Network** (`homelab-ephemeral`, freely rebuildable).
  - `.40–.49` (`CT 140–149`): **Zone 4 · Ephemeral Apps & Ops** (`homelab-ephemeral`, freely rebuildable).
  - `.50–.59` (`CT 150–159`): **Zone 5 · Sandbox / Lab** (`homelab-ephemeral`, future disposable experiments).
  - `.60–.99`: **Open Reserve** (unallocated, blocked in `devbox` UFW until expanded).
  - `.100–.254`: **DHCP Pool** (LAN clients, blocked in `devbox` UFW).

## Active Phase 1 Matrix (8 GB RAM Lean Scope — ADR-007 + ADR-008)

| Zone | ID | Service | IP | DNS | Proxmox Pool / Protection |
|---|---|---|---|---|---|
| **Zone 0** | host | Proxmox `haytham` + Host Backups | `192.168.100.2` | `pve.haytham.internal` | Physical host |
| **Zone 1** | `110` | **Infisical** *(Immutable, outside Terraform)* | `192.168.100.10` | `infisical.haytham.internal` *(CLI uses direct IP `:8080`)* | `homelab-immutable` / `protection=1` / ZERO ACL |
| **Zone 2** | `120` | **Vaultwarden** | `192.168.100.20` | `vaultwarden.haytham.internal` | `homelab-protected` / `protection=1` |
| **Zone 2** | `121` | **Immich** (500 GB + `/dev/dri` Quick Sync) | `192.168.100.21` | `immich.haytham.internal` | `homelab-protected` / `protection=1` |
| **Zone 3** | `130` | **Pi-hole** | `192.168.100.30` | `pihole.haytham.internal` | `homelab-ephemeral` |
| **Zone 3** | `131` | **NPM** (Wildcard `*.haytham.internal`) | `192.168.100.31` | `npm.haytham.internal` | `homelab-ephemeral` |
| **Zone 3** | `132` | **Tailscale** (`/dev/net/tun` subnet router) | `192.168.100.32` | — (VPN router) | `homelab-ephemeral` |
| **Zone 4** | `140` | **Homepage** | `192.168.100.40` | `haytham.internal` (root) | `homelab-ephemeral` |
| **Zone 4** | `141` | **Uptime Kuma** | `192.168.100.41` | `uptime.haytham.internal` | `homelab-ephemeral` |

## Deferred & Planned Future Slots (Not Provisioned in Phase 1)

| Zone | ID | Service | IP | DNS | Status / Trigger |
|---|---|---|---|---|---|
| **Zone 0** | `103` (VM) | Home Assistant OS | `192.168.100.3` (DHCP reservation, MAC-pinned) | — (direct IP `:8123`) | Deferred until 16 GB RAM (`ADR-007`) |
| **Zone 0** | `104–109` (VM) | Reserved future VMs | `192.168.100.4 – .9` | — | Reserved (6 VM slots) |
| **Zone 1** | `111–119` | Future immutable platform (CA / Bastion) | `192.168.100.11 – .19` | — | Reserved |
| **Zone 2** | `122` | PostgreSQL (shared) | `192.168.100.22` | — (non-HTTP) | Deferred until DB consumer (`ADR-007`) |
| **Zone 2** | `123` | Karakeep | `192.168.100.23` | `karakeep.haytham.internal` | Deferred until 16 GB RAM (`ADR-007`) |
| **Zone 2** | `124–129` | Future protected stateful (`124` Gitea, `125` Neo4j, `126` Paperless-ngx, `127` Frigate) | `192.168.100.24 – .29` | — | Reserved |
| **Zone 3** | `133` | Redis (shared cache) | `192.168.100.33` | — (non-HTTP) | Deferred until consumer (`ADR-007`) |
| **Zone 3** | `134–139` | Future infra / SSO auth proxy | `192.168.100.34 – .39` | — | Reserved (`ADR-004`) |
| **Zone 4** | `142` | pgAdmin | `192.168.100.42` | `pgadmin.haytham.internal` | Deferred with Postgres (`ADR-007`) |
| **Zone 4** | `143–149` | Future stateless tools/ops (`143` Stirling-PDF, `144` CI Runner, `145` Portainer) | `192.168.100.43 – .49` | — | Reserved |
| **Zone 5** | `150–159` | Sandbox / AI Lab (Ollama, experiments) | `192.168.100.50 – .59` | — | Reserved |

## FAQ

**Q: How do I derive any Proxmox ID from its IP (or vice versa)?**
A: `ID = 100 + last_octet` for EVERY VM and LXC (`192.168.100.21` ↔ `CT 121`, `192.168.100.3` ↔ `VM 103`).

**Q: Why are `.60–.99` unallocated and blocked in UFW?**
A: Keeping the active footprint tightly packed into `.10–.49` minimizes the firewall surface on `devbox` while leaving 40 clean static IPs if Zone 2 or Zone 4 ever needs expansion later.
