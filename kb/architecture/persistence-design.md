---
id: arch-persistence-design
title: Persistence Design and Two-Track Local Backup
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, storage, backup, risk]
retrievable: true
---

# Persistence Design and Two-Track Local Backup

## 1. Storage reality

Host `haytham` has a **single 1 TB SSD** (no RAID / ZFS redundancy — see `../decisions/ADR-003-no-truenas-paperless.md`). All active LXC data lives on `local-lvm` thin-provisioned rootfs volumes and is destroyed by `terraform destroy`.

To achieve true **2-drive redundancy with zero cloud exposure and zero Samba shares**, Phase 1 ships with automated **Tier 80 local-network backups** (`../operations/backup-and-restore.md`):

- **Track 1 (Critical small state — daily):** Proxmox `systemd` timer dumps Vaultwarden SQLite (online `.backup`), Immich Postgres (`pg_dumpall`), NPM SQLite, Pi-hole config, Homepage config, Uptime Kuma SQLite, and `/etc/pve/lxc/*.conf` into an encrypted local `restic` repository (`/var/backups/homelab/restic`, 7 daily / 4 weekly). Weekly `vzdump` snapshots cover lightweight LXCs (`110, 120, 130, 320, 440, 910`).
- **Track 2 (Immich 500 GB original photos/videos — incremental SSH pull):** `scripts/pull-homelab-backups.bat` (native Windows `cmd` using inbox `ssh.exe` + `tar.exe`) and `scripts/pull-homelab-backups.sh` (Linux/WSL `rsync`) pull both the Track 1 encrypted `restic` repo and Immich originals (`/opt/immich/library/{library,upload,profile}/`, excluding regeneratable `thumbs/` and `encoded-video/`) directly over SSH to the Windows workstation or an external USB drive.

## 2. Per-service blast radius

| Service | Data at risk on destroy / SSD failure | Protection in Phase 1 |
|---|---|---|
| **Vaultwarden (`320`)** | Vault items — **P0 lockout risk** | Daily online SQLite `.backup` + attachments in encrypted `restic` (Track 1) + off-host PC pull |
| **Immich (`610`)** | Up to 500 GB iPhone photos/videos + Postgres metadata | Daily `pg_dumpall` in Track 1 `restic` + incremental original media SSH pull to PC/USB (Track 2) |
| **NPM (`120`)** | Proxy Hosts, imported cert, admin account | Daily tarball in Track 1 `restic` + weekly `vzdump` |
| **Pi-hole (`110`)** | Blocklists, custom dnsmasq, query DB | Daily `/etc/pihole` + `/etc/dnsmasq.d` in Track 1 `restic` + weekly `vzdump` |
| **Homepage (`440`)** | Custom `services.yaml` / `widgets.yaml` | Daily config tarball in Track 1 `restic` + weekly `vzdump` |
| **Uptime Kuma (`910`)** | Monitor definitions & uptime history | Daily online SQLite `.backup` in Track 1 `restic` + weekly `vzdump` |
| **Tailscale (`130`)** | Node identity (`tailscaled.state`) | Weekly `vzdump` (or quick re-auth via `tailscale up`) |
| **SSL cert** | Safe — stored in `~/homelab-cert` + Windows backup + Vaultwarden attachment | Guard `.key`, `.crt`, `.cnf` outside containers |

## 3. Required practices from day one

- **Never run `terraform destroy` on a loaded host** (especially after migrating iPhone photos to CT `610`) without confirming both Track 1 (`restic check`) and Track 2 (`pull-homelab-backups.{sh,bat}`) completed cleanly on your PC/USB drive.
- **Snapshot before risky updates:** `pct snapshot <ctid> pre-update-YYYYMMDD` (see `../operations/update-and-reboot.md`). Snapshots are rollback aids, not off-host backups.
- **Run a Vaultwarden restore drill** immediately after Phase 1 comes up (`../operations/backup-and-restore.md §6`).
- **Offline emergency keys:** Keep `vault_restic_password` and Ansible `.vault_pass` on an offline/printed sheet or encrypted USB outside the `restic` repo.

## 4. FAQ

**Q: Why aren't Immich's 500 GB photos copied into the local `restic` repo on Proxmox?**
A: Copying 500 GB onto the same 1 TB SSD would consume the entire disk and still provide zero protection if that single SSD fails. Direct incremental SSH pull to a second physical drive solves both problems.
