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

> Single source of truth for the `haytham` homelab. Written before the first build — all pages are prescriptive. English only. Git + Markdown, RAG-ready.

## How to use this KB

1. **Humans:** start here → `architecture/overview.md` → `roadmap/build-sequence.md` → the service page you need.
2. **AI / RAG:** ingest all `*.md` under `kb/` where frontmatter `retrievable: true`. Exclude `templates/` and `eval/`. Use frontmatter fields (`tier`, `ctid`, `status`, `tags`) for metadata-filtered retrieval.
3. **Status semantics:**
   - `planned` — specified, not yet verified on this host.
   - `verified` — passes its verification block on a clean build (flip after green build).
   - `reserved` — specified in `roadmap/future-services.md`, not built.
   - `deprecated` — superseded, do not use for new work.

## Scope

| Area | Entry point |
|---|---|
| Architecture | `architecture/overview.md` |
| Lean 8 GB Scope (ADR-007) | `decisions/ADR-007-lean-8gb-phase1.md` |
| Tier 10 Network (Pi-hole 110, NPM 120, Tailscale 130) | `services/network-pihole-110.md`, `services/network-npm-120.md`, `services/network-tailscale-130.md` |
| Tier 30 Identity (Vaultwarden 320) | `services/identity-vaultwarden-320.md` |
| Tier 40 App (Homepage 440; Karakeep 420 deferred) | `services/app-homepage-440.md` |
| Tier 60 Media (Immich 610) | `services/media-immich-610.md` |
| Tier 80 Backup (Host `restic` + WSL SSH pull) | `operations/backup-and-restore.md` |
| Tier 90 Observability (Uptime Kuma 910) | `services/obs-uptime-kuma-910.md` |
| Deferred (Tier 20 Data 210/220/230, Karakeep 420, VM 100 HAOS) | `services/data-postgres-210.md`, `services/app-karakeep-420.md`, `services/vm-haos-100.md` |
| Build order | `roadmap/build-sequence.md` |
| Deferred & future services | `roadmap/future-services.md` |
| Persistence & backups | `architecture/persistence-design.md` |

## Map

```
kb-v2/
  index.md                  # this file
  architecture/             # design, schemes, strategies
  services/                 # one page per deployable unit (CTID/VM)
  operations/               # runbooks (procedural only)
  troubleshooting/          # required-setup notes, linked from services
  decisions/                # ADRs — reserved / structural choices
  roadmap/                  # build-sequence (only chronology) + future-services
  reference/                # glossary, IP matrix, inventory (no secrets)
  eval/                     # golden Q/A for RAG evaluation
  templates/                # page templates (do not ingest as content)
```

## Conventions

- One concept per file, 150–400 lines max.
- Frontmatter required on every content file (see `templates/frontmatter-reference.md`).
- IPs/CTIDs are canonical only in `reference/ip-ctid-matrix.md`. All other pages link there.
- Secrets are never stored here — only `vault_*` variable *names*, never values.
- The only chronological document is `roadmap/build-sequence.md`.

## Maintenance

- Flip `planned` → `verified` with `last_verified` date only after a green build.
- Fix goes to KB first, then to infra (reproducibility policy).
- See `CONTRIBUTING.md` for authoring rules.
