---
id: ops-backup-and-restore
title: Runbook — Automated Local-Network Backup and Restore
tier: "80"
ctid: "n/a"
ip: 192.168.100.2
status: planned
last_verified: unreleased
tags: [operations, backup, restore, restic, rsync, dr]
retrievable: true
---

# Runbook — Automated Local-Network Backup and Restore

## 1. Purpose

Protect critical homelab state (especially Vaultwarden credentials and Immich photos/metadata) across **two physical storages** (Proxmox 1 TB SSD + Windows workstation or external USB drive) with **zero cloud exposure and zero Samba shares**.

## 2. Architecture (Two-Track Model)

| Track | Scope | Mechanism | Schedule | Destination |
|---|---|---|---|---|
| **Track 1 — Critical State** | Vaultwarden SQLite (hot `.backup`) + keys/attachments, Immich `pg_dumpall`, NPM data, Pi-hole config, Homepage config, Uptime Kuma SQLite, `/etc/pve/lxc/*.conf` | Proxmox `systemd` timer (`roles/backup`) → encrypted `restic` repo (`/var/backups/homelab/restic`) | Daily `03:00` (retain 7 daily / 4 weekly) | Local SSD, then pulled over SSH via `pull-homelab-backups.bat` (Windows `cmd`) or `pull-homelab-backups.sh` (Linux/WSL) |
| **Track 1b — LXC Snapshots** | Lightweight LXCs (`110, 120, 130, 320, 440, 910`) | Proxmox `vzdump` (`zstd`, `mode=snapshot`) | Weekly Sun `03:30` (keep last 2) | Proxmox `local` storage |
| **Track 2 — Immich Originals** | `/opt/immich/library/{library,upload,profile}/` (excludes regeneratable `thumbs/` & `encoded-video/`) | Direct incremental SSH pull (`scripts/pull-homelab-backups.bat` on Windows `cmd`, `scripts/pull-homelab-backups.sh` on Linux/WSL) | On-logon / daily Task Scheduler or on-demand | Windows PC internal drive or external USB drive |

> Track 2 intentionally does **not** duplicate 500 GB of photos onto the same 1 TB Proxmox SSD. Pulling directly over SSH gives true 2-drive redundancy without halving SSD capacity.

## 3. Prerequisites

- `vault_restic_password` encrypted in `ansible/group_vars/proxmox.yml` (also store a copy of this password in Vaultwarden **and** an offline/printed emergency sheet — you cannot decrypt `restic` without it).
- `ansible-playbook tier80.yml` applied cleanly to `haytham` (`192.168.100.2`).
- Key-based SSH to `root@192.168.100.2` and `root@192.168.100.61` from either:
  - **Native Windows `cmd` (no WSL, zero third-party installs):** Built-in Windows `ssh.exe` + `tar.exe` (Device Guard / Smart App Control safe) + `scripts/pull-homelab-backups.bat`
  - **Linux / WSL Ubuntu 24.04:** `rsync`, `restic`, and `scripts/pull-homelab-backups.sh`

## 4. Off-Host Pull Setup

### Option A — Native Windows `cmd` (No WSL, Zero Third-Party Installs)

Uses only Microsoft-signed inbox Windows binaries (`cmd.exe`, `ssh.exe`, `tar.exe`), so it works cleanly under Windows Smart App Control / Device Guard.

1. Ensure your Windows SSH public key (`%USERPROFILE%\.ssh\id_ed25519.pub`) is authorized in `/root/.ssh/authorized_keys` on CT `610` (`192.168.100.61`, for Track 2) and Proxmox (`192.168.100.2`, for Track 1).
2. Run `scripts\pull-homelab-backups.bat` in `cmd`:

```bat
REM Track 2 only (Immich original photos -> Windows D: or external USB drive, incremental)
set "PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals"
scripts\pull-homelab-backups.bat --photos-only

REM Track 1 only (tiny encrypted restic repo -> Windows internal drive, atomic swap)
set "STATE_BACKUP_DIR=C:\Users\<you>\Backups\haytham\state"
scripts\pull-homelab-backups.bat --state-only

REM Both Track 1 + Track 2 in one run
scripts\pull-homelab-backups.bat
```

To automate via **Windows Task Scheduler** without WSL:
1. Create a task triggered **At log on** (or daily).
2. Action: Start a program → `cmd.exe`
3. Arguments (example):
   `/c "set STATE_BACKUP_DIR=C:\Users\<you>\Backups\haytham\state&& set PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals&& C:\path\to\haytham-homelab\scripts\pull-homelab-backups.bat"`

### Option B — Linux / WSL

Test manually from Linux or WSL first:

```bash
chmod +x scripts/pull-homelab-backups.sh

# Track 1 only (tiny encrypted restic repo -> Windows internal drive)
STATE_BACKUP_DIR="/mnt/c/Users/<you>/Backups/haytham/state" \
  ./scripts/pull-homelab-backups.sh --state-only

# Track 2 only (Immich original photos -> Windows D: or external USB drive)
PHOTOS_BACKUP_DIR="/mnt/d/Backups/haytham/immich-originals" \
  ./scripts/pull-homelab-backups.sh --photos-only
```

Automate via **Windows Task Scheduler** (WSL):
1. Create a task triggered **At log on** (and optionally daily at a time your PC is usually awake).
2. Action: Start a program → `wsl.exe`
3. Arguments (example):
   `-e bash -lc 'STATE_BACKUP_DIR="/mnt/c/Users/<you>/Backups/haytham/state" PHOTOS_BACKUP_DIR="/mnt/d/Backups/haytham/immich-originals" /home/<wsl-user>/haytham-homelab/scripts/pull-homelab-backups.sh'`

## 5. Verification

On Proxmox host `haytham`:

```bash
systemctl list-timers 'homelab-*'
systemctl start homelab-backup.service
journalctl -u homelab-backup.service -n 50 --no-pager

restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass snapshots
```

From Linux / WSL (verify mirrored off-host repo integrity):

```bash
restic -r "/mnt/c/Users/<you>/Backups/haytham/state/restic" check
```

From Windows `cmd` (verify Track 2 incremental idempotency):

```bat
REM Re-running immediately after a sync should report: [Track 2] 0 new/changed files
scripts\pull-homelab-backups.bat --photos-only
```

## 6. Restore Drills

### Vaultwarden (P0 — test after initial build)

```bash
# Restore latest Track 1 snapshot to a temp directory
restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass \
  restore latest --target /tmp/vw-restore --include /var/backups/homelab/staging/vaultwarden

# Stop Vaultwarden, replace db.sqlite3 + vw-data files, start Vaultwarden
pct exec 320 -- docker compose -f /opt/vaultwarden/docker-compose.yml down
pct push 320 /tmp/vw-restore/var/backups/homelab/staging/vaultwarden/db.sqlite3 /opt/vaultwarden/vw-data/db.sqlite3
pct exec 320 -- docker compose -f /opt/vaultwarden/docker-compose.yml up -d
rm -rf /tmp/vw-restore
```

### Immich (Full Recovery)

1. Provision fresh CT `610` via `terraform apply` + `host_devices.yml` + `tier60.yml`.
2. Push original photos back from your PC to CT `610`:
   ```bash
   # From Linux / WSL
   rsync -avh --progress "$PHOTOS_BACKUP_DIR/" root@192.168.100.61:/opt/immich/library/
   ```
   ```bat
   REM Or from native Windows cmd (inbox tar.exe + ssh.exe)
   tar -C "%PHOTOS_BACKUP_DIR%" -cf - library upload profile | ssh -i "%USERPROFILE%\.ssh\id_ed25519" root@192.168.100.61 "tar -xf - -C /opt/immich/library"
   ```
3. Restore `immich-postgres.sql.gz` from the Track 1 `restic` snapshot into `immich_postgres` (with `immich_server` stopped, `database` running):
   ```bash
   gunzip -c immich-postgres.sql.gz | pct exec 610 -- docker exec -i immich_postgres psql -U postgres
   pct exec 610 -- docker compose -f /opt/immich/docker-compose.yml up -d
   ```

## 7. Manual Gaps

- Keep `vault_restic_password` and `.vault_pass` backed up offline (emergency sheet / encrypted USB) outside the `restic` repo itself.
- If using an external USB drive for Track 2 photos, plug it in periodically and run `--photos-only` (it transfers only newly added photos).
- Both `pull-homelab-backups.sh` and `pull-homelab-backups.bat` deliberately omit deletes on Track 2 so an accidental deletion inside Immich does not wipe your PC backup copy.
- If you pull from a separate Windows PC whose SSH public key is not in `terraform.tfvars` (`ssh_public_key_path`), re-authorize that `.pub` key on CT `610` and `haytham` after any full CT rebuild.

## 8. FAQ

**Q: Why pull from Windows instead of pushing from Proxmox?**
A: Windows workstations sleep or power off overnight; pull never fails while asleep, requires no Samba/SMB shares, and keeps Proxmox free of write credentials to your PC.

**Q: Why does `pull-homelab-backups.bat` use built-in `ssh.exe` + `tar.exe` instead of `rclone` or `scp`?**
A: Third-party unsigned binaries like `rclone.exe` can be blocked by Windows Smart App Control / Device Guard, while `scp -r` is not incremental (re-copies every file on every run). Streaming a local manifest (`size?path`) to CT `610`'s `python3` + GNU `tar` and piping into Windows inbox `tar.exe` uses only Microsoft-signed built-in binaries while keeping Track 2 fast, incremental, and resumable.
