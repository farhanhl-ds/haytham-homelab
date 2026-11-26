---
id: roadmap-build-sequence
title: Roadmap — Build Sequence (the only chronology)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [roadmap, build-order]
retrievable: true
---

# Roadmap — Build Sequence (the only chronology)

> This is the single chronological document in the KB. All other pages are timeless. Build strictly in this order; each step gates the next.

## Phase 1 — Foundation (Proxmox + Lean 8 GB Core)

1. Install Proxmox on `haytham` (`192.168.100.2`, i5 7th gen / 8 GB RAM / 1 TB SSD), `vmbr0`, `local` + `local-lvm`.
2. Shrink router DHCP pool to `.100-.254`. (Reserve MAC `BC:24:11:D7:75:C0` → `.3` if preparing for future HAOS.)
3. Download Ubuntu 24.04 CT template via GUI. Create `terraform@pve!terraform` with the four role grants.
4. Generate wildcard cert (`architecture/ssl-strategy.md`). Keep key/crt/cnf in `~/homelab-cert/` + Windows backup.
5. `terraform apply` — provisions 7 active Phase 1 LXCs (`110, 120, 130, 320, 440, 610, 910`). Workstation DNS in safe mode (public first).
6. `ansible-playbook host_devices.yml` — attaches `/dev/net/tun` to CT `130` and `/dev/dri/*` to CT `610`.

## Phase 2 — Network, Identity & Dashboard

7. `ansible-playbook tier10.yml` → verify `dig @192.168.100.30` and authenticate Tailscale subnet router (`192.168.100.0/24`) + Split DNS (`haytham.internal → 192.168.100.30`).
8. `ansible-playbook tier30.yml` → Vaultwarden signup → lock `SIGNUPS_ALLOWED="false"` → re-run. Migrate cert + vault/restic passwords to Vaultwarden attachments + offline emergency sheet.
9. `ansible-playbook tier40.yml` → Homepage at `192.168.100.40:3000`.
10. Manual NPM: admin account → import wildcard cert → create all 7 Proxy Hosts (`services/zone3-npm-131.md §4`).

## Phase 3 — Media, Observability & Automated Backups

11. `ansible-playbook tier60.yml` → Immich (`CT 121`, 500 GB) → enable Intel Quick Sync in Admin UI → test photo + video upload over `https://immich.haytham.internal`.
12. `ansible-playbook tier90.yml` → Uptime Kuma (`CT 141`) → add monitors for all active services.
13. `ansible-playbook tier80.yml` → trigger `systemctl start homelab-backup.service`, verify `restic snapshots`, and configure Windows Task Scheduler to run `scripts/pull-homelab-backups.sh` (Track 1 + Track 2).
14. Run Vaultwarden restore drill (`operations/backup-and-restore.md §6`) — P0 acceptance gate.
15. Switch workstation DNS to normal mode (Pi-hole first). Browser + Tailscale cellular sweep of all 7 HTTPS URLs.
16. Begin iPhone photo migration via Immich iOS app / `immich-go` and verify first Track 2 off-host photo sync to PC/USB.

## Phase 4 — Post-16 GB RAM Upgrade & Future Expansion

17. Upgrade `haytham` RAM from 8 GB → 16 GB.
18. Router Primary DNS → `.11` cutover (multi-device LAN adblock + internal DNS).
19. Revive deferred workloads as needed (`ADR-007`):
    - **HAOS (VM 103, `.3`):** manual `qm` build (`services/vm-haos-103.md`).
    - **Karakeep (`420`)** or lighter bookmark alternative (e.g., Linkding).
    - **Tier 20 (`210/220/230`)** once an app actually consumes shared Postgres/Redis (e.g., Outline).
20. Next apps from `future-services.md` in dependency order.

## FAQ

**Q: Can I skip `host_devices.yml` before `tier10.yml` and `tier60.yml`?**
A: No. Tailscale fails without `/dev/net/tun`, and Immich skips Intel Quick Sync without `/dev/dri/renderD128`.
