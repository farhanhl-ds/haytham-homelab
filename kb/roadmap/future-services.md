---
id: roadmap-future-services
title: Roadmap — Deferred and Future Services (not built in Phase 1)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [roadmap, future, reserved, deferred]
retrievable: true
---

# Roadmap — Deferred and Future Services

> Everything here is either **deferred** (IaC/KB already exists, disabled via `enabled = false` until the 16 GB RAM upgrade or a real consumer — see `../decisions/ADR-007-lean-8gb-phase1.md`) or **reserved** capacity with a build trigger.

## Hygiene backlog (after green Phase 1 build)

- [ ] Consolidate to one SSH keypair across Windows/WSL.
- [ ] Migrate SSL cert + `.vault_pass` + `vault_restic_password` → Vaultwarden attachments + offline emergency sheet; remove loose copies.
- [ ] Complete Vaultwarden + Immich DB restore drill (`../operations/backup-and-restore.md §6`).
- [ ] Router Primary DNS → `.11`; decide Secondary policy (strict vs. public fallback).
- [ ] Public domain + split-horizon + DNS-01 Let's Encrypt (replaces per-device self-signed CA trust).

## Deferred services (ready to revive in repo)

| CTID/VMID | IP | Service | Trigger / Revival Path |
|---|---|---|---|
| 100 (VM) | .3 | Home Assistant OS | 16 GB RAM upgrade — build via `../services/vm-haos-100.md` (`qm`) |
| 210 | .21 | Postgres (shared) | Concrete external-PG consumer (e.g., Outline) — set `enabled = true` in `locals.tf` + uncomment `hosts.yml` + `tier20.yml` |
| 220 | .22 | Redis (shared) | Concrete external-Redis consumer — revive with Tier 20 |
| 230 | .23 | pgAdmin | Revive alongside Postgres (`210`) |
| 420 | .42 | Karakeep | Post-Phase 1 evaluation (keep trimmed vs. replace with Linkding) or 16 GB RAM upgrade |

## Reserved future services (not yet built)

| CTID | IP | Service | Trigger / constraint |
|---|---|---|---|
| 310 | .31 | SSO (Authelia default, Authentik if multi-app) | Concrete OIDC requirement (see `../decisions/ADR-004-auth-reserved.md`) |
| 330 | .33 | Machine secrets manager | Consumers beyond Ansible Vault / rotation pain (see `../decisions/ADR-006-infisical-deferred.md`) |
| 410 | .41 | Outline | Needs Tier 20 shared Postgres revived first |
| 430 | .43 | Postiz | Heavy (PG + Redis + Temporal + app); prefer native scheduling unless need is concrete |
| 450 | — | Paperless-ngx | Skipped, reserved (see `../decisions/ADR-003-no-truenas-paperless.md`) |
| 510 | .51 | Ollama | Split LXC from OpenWebUI (requires RAM/hardware upgrade) |
| 520 | .52 | OpenWebUI | Split LXC from Ollama |
| 920 | .92 | Portainer | Optional; manages Docker LXCs only |
| 101+ | .4-.10 | Next VMs | First free IP after HAOS `.3`. Example: VM101 Linux dev VM at `.4` |

## Research rule before any new app

For each candidate confirm: DB support (shared PG vs. SQLite vs. bundled), image user (root vs. UID — pgAdmin 5050 lesson), ports, official compose vs. native install, and RAM footprint.
