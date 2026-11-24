---
name: homelab-backup-restore
description: >-
  Use this skill when the user asks to run, verify, pull, troubleshoot, or test
  homelab backups (Track 1 restic, Track 1b vzdump, Track 2 Immich rsync) or
  perform Vaultwarden/Immich restore drills.
---

# Homelab Backup & Restore

Canonical runbook: `kb/operations/backup-and-restore.md` (zero-cloud, zero-Samba two-track model).

## Backup Tracks Overview

- **Track 1 (Critical State — Daily 03:00):** Proxmox systemd `homelab-backup.timer` dumps Vaultwarden SQLite (hot `.backup`), Immich `pg_dumpall`, NPM, Pi-hole, Homepage, Uptime Kuma SQLite, and `/etc/pve/lxc/*.conf` into encrypted `restic` repo `/var/backups/homelab/restic` (retain 7 daily / 4 weekly).
- **Track 1b (LXC Snapshots — Sun 03:30):** `homelab-vzdump.timer` snapshots lightweight CTs (`110, 120, 130, 320, 440, 910`) to Proxmox `local` storage (keep last 2).
- **Track 2 (Immich Originals — On-Demand / Scheduled Pull):** Incremental `rsync` over SSH directly from CT `610` (`/opt/immich/library/{library,upload,profile}/`) via `scripts/pull-homelab-backups.sh` (excludes `thumbs/` & `encoded-video/`, intentionally omits `--delete`).

## Routine Backup Verification

Run from your control node (Linux workstation or WSL):

```bash
# 1. Check timers, trigger on-demand Track 1 backup, inspect snapshots on haytham
ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 \
  "systemctl list-timers 'homelab-*' --no-pager && \
   systemctl start homelab-backup.service && \
   journalctl -u homelab-backup.service -n 30 --no-pager && \
   restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass snapshots && \
   restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass check"

# 2. Pull off-host backups
/home/farhan/haytham-homelab/scripts/pull-homelab-backups.sh --state-only
# Optional Track 2 photos pull (set PHOTOS_BACKUP_DIR if using an external/D: drive):
# PHOTOS_BACKUP_DIR="/path/to/immich-originals" /home/farhan/haytham-homelab/scripts/pull-homelab-backups.sh --photos-only
```

To verify the off-host `restic` mirror without exposing the password in shell history, ask the user to run `restic -r "<STATE_BACKUP_DIR>/restic" check` interactively.

## Restore Drills & Recovery

Always confirm with the user before stopping live containers or overwriting data! Read `kb/operations/backup-and-restore.md §6` for exact commands:

- **Vaultwarden (P0 drill):** Restore `/var/backups/homelab/staging/vaultwarden` to `/tmp/vw-restore` on `haytham` → `pct exec 320 -- docker compose -f /opt/vaultwarden/docker-compose.yml down` → `pct push 320` `db.sqlite3` (and keys/attachments if full restore) → `up -d` → clean `/tmp/vw-restore` → verify login.
- **Immich (Full DR):** Reprovision CT `610` (`terraform apply` + `host_devices.yml` + `tier60.yml`) → `rsync` Track 2 originals back to `root@192.168.100.61:/opt/immich/library/` → stop `immich_server` (keep `database` running) → pipe `immich-postgres.sql.gz` from Track 1 snapshot into `immich_postgres` → `docker compose up -d`.

## Safety Guardrails

- Never print `/etc/homelab-backup/restic.pass` or `vault_restic_password`.
- Remind the user that `vault_restic_password` and `.vault_pass` must have an offline copy outside the `restic` repo.
