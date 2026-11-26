---
id: kb-index
title: Haytham Homelab Knowledge Base (index)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [index, reference]
retrievable: true
---

# Haytham Homelab Knowledge Base

> Single source of truth for the `haytham` homelab. English only. Git + Markdown, RAG-ready.

## How to Use This KB

1. **Humans:** start here → `decisions/ADR-008-zero-trust-security-zones-and-infisical.md` → `operations/control-node-hardening-and-recovery.md` → `operations/build-from-scratch.md`.
2. **AI / RAG:** ingest all `*.md` under `kb/` where frontmatter `retrievable: true`. Exclude `templates/` and `eval/`.
3. **Status semantics:** `planned` (prescriptive, awaiting verification), `verified` (green clean build), `reserved` (deferred), `superseded` (do not use for new work).

## Scope (Security Zones — `ID = 100 + last_octet`, `ADR-008`)

| Area | Entry Point |
|---|---|
| Zero-Trust Control Node & Security Zones (`ADR-008`) | `decisions/ADR-008-zero-trust-security-zones-and-infisical.md` |
| Control Node Hardening & <10m Recovery | `operations/control-node-hardening-and-recovery.md` |
| Lean 8 GB Scope (`ADR-007`) | `decisions/ADR-007-lean-8gb-phase1.md` |
| Canonical IP & ID Matrix | `reference/ip-ctid-matrix.md` |
| Zone 1 Immutable Core (Infisical `110`) | `services/zone1-infisical-110.md` |
| Zone 2 Protected Data (Vaultwarden `120`, Immich `121`) | `services/zone2-vaultwarden-120.md`, `services/zone2-immich-121.md` |
| Zone 3 Core Infra (Pi-hole `130`, NPM `131`, Tailscale `132`) | `services/zone3-pihole-130.md`, `services/zone3-npm-131.md`, `services/zone3-tailscale-132.md` |
| Zone 4 Ephemeral Apps & Ops (Homepage `140`, Uptime Kuma `141`) | `services/zone4-homepage-140.md`, `services/zone4-uptime-kuma-141.md` |
| Zone 0 Host Backups (`restic` + `vzdump` + Windows pull) | `operations/backup-and-restore.md` |
| Deferred (Postgres `122`, Karakeep `123`, Redis `133`, pgAdmin `142`, `VM 103` HAOS) | `services/zone2-postgres-122.md`, `services/zone2-karakeep-123.md`, `services/zone3-redis-133.md`, `services/zone4-pgadmin-142.md`, `services/vm-haos-103.md` |
| Build order & future services | `roadmap/build-sequence.md`, `roadmap/future-services.md` |
| Persistence & backups | `architecture/persistence-design.md` |

## Conventions

- One concept per file, 150–400 lines max.
- Frontmatter required on every content file (see `templates/frontmatter-reference.md`).
- IPs/IDs are canonical only in `reference/ip-ctid-matrix.md`. All other pages link there.
- Secrets are never stored here — only variable *names*, never values.
- See `CONTRIBUTING.md` for authoring rules.
