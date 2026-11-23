---
id: arch-tier-ctid
title: Tier and CTID Scheme
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, tier, ctid]
retrievable: true
---

# Tier and CTID Scheme

## 1. Numbering

Steps of 10 per tier with gaps for expansion without renumbering. VMs are outside CTID numbering.

| Tier | Name | CTID range | Phase 1 Status | Services |
|---|---|---|---|---|
| 10 | Network / Ingress | 110–190 | **Active** | Pi-hole (`110`), NPM (`120`), Tailscale (`130`) |
| 20 | Data / Persistence | 210–290 | Deferred (`ADR-007`) | Postgres (`210`), Redis (`220`), pgAdmin (`230`) |
| 30 | Identity & Access | 310–390 | **Active** | Vaultwarden (`320`); SSO (`310`) & secrets manager (`330`) reserved |
| 40 | Application | 410–490 | **Active** | Homepage (`440`); Karakeep (`420`) deferred (`ADR-007`) |
| 50 | AI / ML | 510–590 | Reserved | Ollama (`510`), OpenWebUI (`520`) |
| 60 | Media | 610–690 | **Active** | Immich (`610`) |
| 70 | CI/CD & Automation | 710–790 | Reserved | — |
| 80 | Backup & DR | host / 810–890 | **Active (host)** | Automated `restic` + `vzdump` on `haytham` + WSL SSH pull |
| 90 | Observability | 910–990 | **Active** | Uptime Kuma (`910`); Portainer (`920`) optional |
| VM | Virtual machines | 100, 101+ | Deferred (`ADR-007`) | HAOS (`100` at `.3`); `.4–.10` reserved for next VMs |

Future reservations and revival triggers live in `../roadmap/future-services.md` and `../decisions/ADR-007-lean-8gb-phase1.md`.

## 2. Per-tier notes

- **1 service = 1 LXC** remains the architectural standard even on 8 GB RAM (`ADR-007`).
- **Immich (`610`)** is a self-contained 4-container bundle (server + ML + Valkey + Postgres/VectorChord) in one LXC — same sanctioned multi-container exception as Karakeep (`420`). Do not wire Immich to shared Tier 20 Postgres/Redis.
- **Tier 20 (Postgres/Redis/pgAdmin)** is preserved in IaC (`enabled = false` in `terraform/locals.tf`) and revives cleanly when an app actually requires shared Postgres or Redis.
- **Tier 80 (Backup)** runs directly on Proxmox host `haytham` via `systemd` timers (`tier80.yml`) for zero idle container overhead.

## 3. FAQ

**Q: Can I insert a new service without renumbering?**
A: Yes — use the next free multiple of 10 in the matching tier (e.g. next Tier 10 = `140`, next Tier 40 = `410`/`430`).

**Q: Why is Immich CTID `610` and Uptime Kuma `910`?**
A: Tiers 60 (Media) and 90 (Observability) are built into the 9-tier scheme (`10–90`). Dividing CTID by 10 gives `.61` and `.91` without colliding with other tiers.

**Q: Does CTID appear in DNS?**
A: No. DNS is human-memorable (`immich.haytham.internal`, `uptime.haytham.internal`); CTID is infra bookkeeping.
