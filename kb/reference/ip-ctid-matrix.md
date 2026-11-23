---
id: ref-ip-ctid-matrix
title: IP and CTID Matrix (canonical)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [reference, ip, ctid, network]
retrievable: true
---

# IP and CTID Matrix (canonical)

> The only source of truth for VMID/CTID ↔ IP ↔ hostname. All other pages link here.

## Scheme

- Subnet `192.168.100.0/24`, gateway `192.168.100.1`.
- Formula for LXC: `last_octet = CTID / 10`.
- `.1` gateway. `.2` Proxmox host. `.3` VM100 (deferred). `.4-.10` reserved VM block (next VM takes first free). `.11+` LXC via formula. `.100-.254` DHCP pool. `.180-.199` companion block for non-round CTIDs (manual per case).

## Active Phase 1 Matrix (8 GB RAM Lean Scope — ADR-007)

| CTID/VMID | Service | IP | DNS | Tier |
|---|---|---|---|---|
| — | Proxmox host `haytham` (+ Tier 80 backups) | 192.168.100.2 | `pve.haytham.internal` | host / 80 |
| 110 | Pi-hole | 192.168.100.11 | `pihole.haytham.internal` | 10 |
| 120 | NPM | 192.168.100.12 | `npm.haytham.internal` | 10 |
| 130 | Tailscale (subnet router) | 192.168.100.13 | — (VPN router) | 10 |
| 320 | Vaultwarden | 192.168.100.32 | `vaultwarden.haytham.internal` | 30 |
| 440 | Homepage | 192.168.100.44 | `haytham.internal` (root) | 40 |
| 610 | Immich | 192.168.100.61 | `immich.haytham.internal` | 60 |
| 910 | Uptime Kuma | 192.168.100.91 | `uptime.haytham.internal` | 90 |

## Deferred & Reserved (not provisioned in Phase 1)

| CTID/VMID | Service | IP | DNS | Tier | Status / Trigger |
|---|---|---|---|---|---|
| 100 (VM) | Home Assistant OS | 192.168.100.3 (DHCP reservation, MAC-pinned) | — (direct IP `:8123`) | vm | Deferred until 16 GB RAM (`ADR-007`) |
| 101+ (VM) | Reserved future VMs | 192.168.100.4 – 192.168.100.10 | — | vm | Reserved |
| 210 | Postgres (shared) | 192.168.100.21 | — (non-HTTP) | 20 | Deferred until DB consumer (`ADR-007`) |
| 220 | Redis (shared) | 192.168.100.22 | — (non-HTTP) | 20 | Deferred until cache consumer (`ADR-007`) |
| 230 | pgAdmin | 192.168.100.23 | `pgadmin.haytham.internal` | 20 | Deferred with Postgres (`ADR-007`) |
| 420 | Karakeep | 192.168.100.42 | `karakeep.haytham.internal` | 40 | Deferred for post-Phase 1 eval (`ADR-007`) |

Additional future reservations (see `../roadmap/future-services.md`): `310` SSO (`.31`), `330` secrets-manager (`.33`), `410` Outline (`.41`), `430` Postiz (`.43`), `450` Paperless-ngx (skipped, reserved), `510` Ollama (`.51`), `520` OpenWebUI (`.52`), `920` Portainer (`.92`, optional).

## FAQ

**Q: What IP is service X?**
A: Look it up above. For LXC, divide its CTID by 10.

**Q: Why are Tiers 20, Karakeep, and HAOS in the Deferred table?**
A: Host currently has 8 GB RAM; they remain preserved in Terraform/Ansible/KB and revive cleanly after the 16 GB RAM upgrade or once a consumer exists (`ADR-007`).
