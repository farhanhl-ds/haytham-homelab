---
name: homelab-backup-restore
description: >-
  Use this skill when the user asks to run, verify, pull, troubleshoot, or test
  homelab backups (Track 1 restic incl. Zone 1 CT 110 Infisical, Track 1b vzdump,
  Track 2 Immich pull) or perform Infisical/Vaultwarden/Immich restore drills.
---

# Homelab Backup & Restore

Canonical runbook: `kb/operations/backup-and-restore.md` (zero-cloud, zero-Samba, Windows pull-only model).

## Backup Tracks Overview

- **Track 1 (Critical State — Daily 03:00 on `haytham` `.2`):** Proxmox systemd `homelab-backup.timer` dumps **Zone 1 CT `110` Infisical (`pg_dumpall` + `/opt/infisical/.env`)**, Zone 2 **CT `120` Vaultwarden** SQLite (hot `.backup`) + keys/attachments, **CT `121` Immich** `pg_dumpall`, Zone 3 **CT `130` Pi-hole** & **CT `131` NPM**, Zone 4 **CT `140` Homepage** & **CT `141` Uptime Kuma** SQLite, and `/etc/pve/lxc/*.conf` into encrypted `restic` repo `/var/backups/homelab/restic` (retain 7 daily / 4 weekly).
- **Track 1b (LXC Snapshots — Sun 03:30):** `homelab-vzdump.timer` snapshots lightweight CTs (`110, 120, 130, 131, 132, 140, 141`) to Proxmox `local` storage (keep last 2).
- **Track 2 (Immich Originals — Windows Pull-Only):** Incremental SSH pull directly from **CT `121` (`192.168.100.21`)** (`/opt/immich/library/{library,upload,profile}/`) via `scripts/pull-homelab-backups.bat` (inbox Windows `ssh.exe` + `tar.exe`, Device Guard safe) or `scripts/pull-homelab-backups.sh` using the **Windows-only SSH key** (completely independent of `haytham-ctl`). Excludes `thumbs/` & `encoded-video/`, intentionally omits deletes.

## Routine Backup Verification

- **Agent (`homelab-agent`) read-only check:**
  ```bash
  sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
  ```
- **Human Operator (Windows `cmd`, Device Guard safe):**
  ```bat
  set "STATE_BACKUP_DIR=C:\Users\<you>\Backups\haytham\state"
  set "PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals"
  scripts\pull-homelab-backups.bat
  ```
- **Human Operator (Windows Break-Glass SSH on `haytham` `.2`):**
  ```bash
  systemctl start homelab-backup.service
  journalctl -u homelab-backup.service -n 30 --no-pager
  restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass check
  ```

## Restore Drills & Recovery (Human-Executed)

Always confirm with the user before stopping live containers or overwriting data! Details in `kb/operations/backup-and-restore.md §6`:

- **Zone 1 Infisical (`CT 110`, catastrophic SSD loss):** Re-run `scripts/zone1/bootstrap-infisical.sh`, restore `/opt/infisical/.env` (with original `ENCRYPTION_KEY` + `AUTH_SECRET`) and `infisical-postgres.sql.gz` from Track 1 `restic`, restart compose.
- **Zone 2 Vaultwarden (`CT 120`, P0 drill):** Restore `/var/backups/homelab/staging/vaultwarden` to `/tmp/vw-restore` on `haytham` → `pct exec 120 -- docker compose -f /opt/vaultwarden/docker-compose.yml down` → `pct push 120` `db.sqlite3` → `up -d` → clean `/tmp/vw-restore`.
- **Zone 2 Immich (`CT 121`, Full DR):** Unlock via `harden-pve-rbac.sh --unlock-dr 121` → reprovision CT `121` (`ops-tf-apply` + `host_devices.yml` + `zone2_protected.yml`) → re-lock (`--lock`) → push Track 2 originals from Windows to `root@192.168.100.21:/opt/immich/library/` → restore `immich-postgres.sql.gz` into `immich_postgres` → `docker compose up -d`.

## Safety Guardrails

- Never print `/etc/homelab-backup/restic.pass`, `vault_restic_password`, or `CT 110`'s `ENCRYPTION_KEY` / `AUTH_SECRET`.
- Remind the user to keep `vault_restic_password`, `ENCRYPTION_KEY`, `AUTH_SECRET`, and `haytham-control-bundle-*.tar.age` backed up on Windows PC + offline USB.
