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
| **Track 1 — Critical State** | Vaultwarden SQLite (hot `.backup`) + keys/attachments, Immich `pg_dumpall`, NPM data, Pi-hole config, Homepage config, Uptime Kuma SQLite, `/etc/pve/lxc/*.conf` | Proxmox `systemd` timer (`roles/backup`) → encrypted `restic` repo (`/var/backups/homelab/restic`) | Daily `03:00` (retain 7 daily / 4 weekly) | Local SSD, then pulled to Windows PC via WSL `rsync` over SSH |
| **Track 1b — LXC Snapshots** | Lightweight LXCs (`110, 120, 130, 320, 440, 910`) | Proxmox `vzdump` (`zstd`, `mode=snapshot`) | Weekly Sun `03:30` (keep last 2) | Proxmox `local` storage |
| **Track 2 — Immich Originals** | `/opt/immich/library/{library,upload,profile}/` (excludes regeneratable `thumbs/` & `encoded-video/`) | Direct incremental `rsync` over SSH (`scripts/pull-homelab-backups.sh`) | On-logon / daily Task Scheduler or on-demand | Windows PC internal drive or external USB drive |

> Track 2 intentionally does **not** duplicate 500 GB of photos onto the same 1 TB Proxmox SSD. Pulling directly over SSH gives true 2-drive redundancy without halving SSD capacity.

## 3. Prerequisites

- `vault_restic_password` encrypted in `ansible/group_vars/proxmox.yml` (also store a copy of this password in Vaultwarden **and** an offline/printed emergency sheet — you cannot decrypt `restic` without it).
- `ansible-playbook tier80.yml` applied cleanly to `haytham` (`192.168.100.2`).
- WSL Ubuntu 24.04 on Windows with `rsync`, `restic`, and key-based SSH to `root@192.168.100.2` and `root@192.168.100.61`.

## 4. Off-Host Pull Setup (Windows / WSL)

Test manually from WSL first:

```bash
chmod +x scripts/pull-homelab-backups.sh

# Track 1 only (tiny encrypted restic repo -> Windows internal drive)
STATE_BACKUP_DIR="/mnt/c/Users/<you>/Backups/haytham/state" \
  ./scripts/pull-homelab-backups.sh --state-only

# Track 2 only (Immich original photos -> Windows D: or external USB drive)
PHOTOS_BACKUP_DIR="/mnt/d/Backups/haytham/immich-originals" \
  ./scripts/pull-homelab-backups.sh --photos-only
```

Automate via **Windows Task Scheduler**:
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

From WSL (verify mirrored off-host repo integrity):

```bash
restic -r "/mnt/c/Users/<you>/Backups/haytham/state/restic" check
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
   rsync -avh --progress "$PHOTOS_BACKUP_DIR/" root@192.168.100.61:/opt/immich/library/
   ```
3. Restore `immich-postgres.sql.gz` from the Track 1 `restic` snapshot into `immich_postgres` (with `immich_server` stopped, `database` running):
   ```bash
   gunzip -c immich-postgres.sql.gz | pct exec 610 -- docker exec -i immich_postgres psql -U postgres
   pct exec 610 -- docker compose -f /opt/immich/docker-compose.yml up -d
   ```

## 7. Manual Gaps

- Keep `vault_restic_password` and `.vault_pass` backed up offline (emergency sheet / encrypted USB) outside the `restic` repo itself.
- If using an external USB drive for Track 2 photos, plug it in periodically and run `--photos-only` (it transfers only newly added photos).
- Note `pull-homelab-backups.sh` deliberately omits `--delete` on Track 2 so an accidental deletion inside Immich does not wipe your PC backup copy.

## 8. FAQ

**Q: Why pull from Windows instead of pushing from Proxmox?**
A: Windows workstations sleep or power off overnight; pull never fails while asleep, requires no Samba/SMB shares, and keeps Proxmox free of write credentials to your PC.
