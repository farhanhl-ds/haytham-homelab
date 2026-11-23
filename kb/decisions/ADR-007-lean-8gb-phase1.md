---
id: adr-007-lean-8gb-phase1
title: ADR-007 — Lean 8 GB Phase 1 Scope and Deferrals
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [decision, hardware, ram, scope, immich, backup]
retrievable: true
---

# ADR-007 — Lean 8 GB Phase 1 Scope and Deferrals

## Context

Host `haytham` is a Lenovo ThinkCentre M910q Tiny with **Intel Core i5 7th gen (4 cores / 4 threads, Intel HD Graphics 630 Quick Sync), 8 GB RAM, and a 1 TB SSD**. Upgrading to 16 GB RAM is planned for the near future, but initial provisioning must operate comfortably within 8 GB RAM while serving the highest-value daily services.

The original blueprint allocated ~11.5–12 GB across Proxmox, Tier 20 (Postgres, Redis, pgAdmin — zero consumers), Karakeep (4 GB headless Chrome bundle), and HAOS VM 100 (4 GB static KVM memory). Adding Immich (photo/video management for iPhone migration) would exceed 8 GB unless unused or heavy workloads are deferred.

## Decision

1. **Activate lean Phase 1 stack (7 LXCs + host-managed backup):**
   - Tier 10: Pi-hole (`110`), NPM (`120`), Tailscale subnet router (`130`)
   - Tier 30: Vaultwarden (`320`)
   - Tier 40: Homepage (`440`, root `haytham.internal`)
   - Tier 60: Immich (`610`, LXC with 500 GB thin-provisioned disk, `/dev/dri` Quick Sync, ML tuned to 1 worker)
   - Tier 90: Uptime Kuma (`910`)
   - Tier 80 (host): Automated local-network backup (`restic` + `vzdump` + WSL SSH pull, zero cloud, zero Samba)
2. **Keep `1 service = 1 LXC`:** Consolidating small Docker apps saves only ~250–350 MB RAM while breaking the CTID/IP scheme (`last_octet = CTID / 10`), blast-radius isolation, and per-service `vzdump` backups.
3. **Run Immich as an LXC (`CT 610`), not a VM:** LXCs share host RAM dynamically (~1.3–1.8 GB idle vs. 4 GB static KVM reservation) and allow simple non-exclusive `/dev/dri` Quick Sync passthrough.
4. **Enable LXC swap (`256–2048 MB`):** Replaces `swap = 0` in `modules/lxc` so `apt upgrade` or Immich ML spikes do not trigger instant OOM kills on 8 GB RAM.
5. **Defer unused / heavy workloads cleanly without deleting code:**
   - **Tier 20 (`210` Postgres, `220` Redis, `230` pgAdmin):** zero active consumers (`enabled = false` in `terraform/locals.tf`, KB `status: reserved`).
   - **Tier 40 (`420` Karakeep):** deferred until post-Phase 1 evaluation (keep vs. lightweight alternative) or 16 GB RAM.
   - **VM 100 (HAOS):** deferred until 16 GB RAM so static KVM memory does not contend with Immich.
6. **Zero-cloud, zero-Samba backup:** Critical small state backs up daily via Proxmox `systemd` timer to an encrypted local `restic` repo and is pulled over SSH to the Windows workstation via `scripts/pull-homelab-backups.sh`. Immich original media (`library/`, `upload/`, `profile/`) is incrementally pulled over SSH directly from CT `610` to the workstation/external drive (never duplicated on the single 1 TB Proxmox SSD).

## Alternatives considered

- **Consolidate small Docker apps into one LXC:** Rejected — minimal RAM savings (~300 MB) at high architectural cost; irrelevant after the 16 GB upgrade.
- **Run Immich in a KVM VM:** Rejected — locks 4 GB RAM statically and complicates iGPU passthrough.
- **Push backups to cloud storage or Windows SMB share:** Rejected — avoids sending private secrets/photos to third-party cloud and avoids Samba daemon/firewall/sleep-mount complexity.

## Consequences

- Steady-state host + 7 LXCs consume ~3.0–3.5 GB RAM, leaving ~4.5 GB headroom for Immich ML/upload bursts.
- All deferred IaC definitions and KB pages remain intact in the repository.
- **Revival trigger (16 GB RAM upgrade or DB consumer):** flip `enabled = true` in `terraform/locals.tf`, uncomment inventory/playbook entries, run `terraform apply` + the tier playbook, and flip KB pages from `reserved` back to `planned` → `verified`.

## Status

Accepted.
