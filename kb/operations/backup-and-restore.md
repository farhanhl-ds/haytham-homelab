---
id: ops-backup-and-restore
title: Runbook — Automated Local-Network Backup and Restore
tier: "x"
ctid: "n/a"
ip: 192.168.100.2
status: planned
last_verified: unreleased
tags: [operations, backup, restore, restic, rsync, dr, infisical]
retrievable: true
---

# Runbook — Automated Local-Network Backup and Restore

## 1. Purpose

Protect critical homelab state — **Zone 1 Infisical (`CT 110`)**, **Zone 2 Vaultwarden (`CT 120`)**, and **Zone 2 Immich (`CT 121`)** — across **two physical storages** (Proxmox 1 TB SSD + Windows PC or external USB drive) with **zero cloud exposure, zero Samba shares, and complete independence from the disposable `devbox` control node**.

## 2. Architecture (Two-Track Model)

| Track | Scope | Mechanism | Schedule | Destination |
|---|---|---|---|---|
| **Track 1 — Critical State** | **CT `110` Infisical** (`pg_dumpall` + `/opt/infisical/.env`), **CT `120` Vaultwarden** (hot SQLite + keys/attachments), **CT `121` Immich** (`pg_dumpall`), CT `130` Pi-hole, CT `131` NPM, CT `140` Homepage, CT `141` Uptime Kuma SQLite, `/etc/pve/lxc/*.conf` | Proxmox `systemd` timer (`ansible/host_backups.yml`) → encrypted `restic` repo (`/var/backups/homelab/restic`) | Daily `03:00` (retain 7 daily / 4 weekly) | Local SSD, then pulled from Windows using Windows-only SSH key via `scripts/pull-homelab-backups.bat` |
| **Track 1b — LXC Snapshots** | Lightweight LXCs (`110, 120, 130, 131, 132, 140, 141`) | Proxmox `vzdump` (`zstd`, `mode=snapshot`) | Weekly Sun `03:30` (keep last 2) | Proxmox `local` storage |
| **Track 2 — Immich Originals** | `CT 121` (`192.168.100.21`) `/opt/immich/library/{library,upload,profile}/` (excludes regeneratable `thumbs/` & `encoded-video/`) | Direct incremental SSH pull (`scripts/pull-homelab-backups.bat` on Windows `cmd`, `scripts/pull-homelab-backups.sh` on Linux/WSL) | On-logon / daily Task Scheduler or on-demand | Windows PC internal drive or external USB drive (no deletes) |

> Track 2 intentionally does **not** duplicate 500 GB of photos onto the same 1 TB Proxmox SSD. Pulling directly from Windows with a **Windows-only SSH key** guarantees a compromised `devbox` cannot alter or delete off-host backups.

## 3. Prerequisites

- `vault_restic_password` populated in Zone 1 Infisical (`/proxmox`) and stored offline (Windows KeePassXC + printed sheet — you cannot decrypt `restic` without it).
- `ops-ansible-apply host_backups.yml` applied cleanly to `haytham` (`192.168.100.2`).
- Windows-only Break-Glass / Backup-Pull SSH public key (`%USERPROFILE%\.ssh\id_ed25519.pub`) authorized in `/root/.ssh/authorized_keys` on `haytham` (`192.168.100.2`) and `CT 121` (`192.168.100.21`, baked declaratively via `breakglass_ssh_public_key_path` in Terraform).

## 4. Off-Host Pull Setup

### Option A — Native Windows `cmd` (Recommended — Zero WSL, Device Guard Safe)

```bat
REM Track 2 only (Immich original photos from CT 121 @ .21 -> Windows D: or external USB)
set "PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals"
scripts\pull-homelab-backups.bat --photos-only

REM Track 1 only (tiny encrypted restic repo -> Windows internal drive, atomic swap)
set "STATE_BACKUP_DIR=C:\Users\<you>\Backups\haytham\state"
scripts\pull-homelab-backups.bat --state-only

REM Both Track 1 + Track 2 in one run
scripts\pull-homelab-backups.bat
```

Automate via **Windows Task Scheduler**: Trigger *At log on* (or daily), Program `cmd.exe`, Arguments:
`/c "set STATE_BACKUP_DIR=C:\Users\<you>\Backups\haytham\state&& set PHOTOS_BACKUP_DIR=D:\Backups\haytham\immich-originals&& C:\path\to\haytham-homelab\scripts\pull-homelab-backups.bat"`

### Option B — Linux / WSL

```bash
STATE_BACKUP_DIR="/mnt/c/Users/<you>/Backups/haytham/state" \
PHOTOS_BACKUP_DIR="/mnt/d/Backups/haytham/immich-originals" \
  ./scripts/pull-homelab-backups.sh
```

## 5. Verification

- From `devbox` (`homelab-agent` read-only check): `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check`
- From Windows Break-Glass SSH on `haytham` (`192.168.100.2`):
  ```bash
  systemctl start homelab-backup.service
  journalctl -u homelab-backup.service -n 50 --no-pager
  restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass snapshots
  restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass check
  ```
- From Windows `cmd` (idempotency check — should report `0 new/changed files`):
  ```bat
  scripts\pull-homelab-backups.bat --photos-only
  ```

## 6. Restore Drills

### Zone 1 Infisical (`CT 110` — Catastrophic SSD Loss Recovery)

```bash
# 1. Recreate CT 110 via scripts/zone1/bootstrap-infisical.sh /root/windows_breakglass.pub
# 2. Extract Track 1 snapshot to /tmp/inf-restore on haytham:
restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass \
  restore latest --target /tmp/inf-restore --include /var/backups/homelab/staging/infisical

# 3. Stop backend, restore original .env (ENCRYPTION_KEY + AUTH_SECRET) & Postgres dump:
pct exec 110 -- docker compose -f /opt/infisical/docker-compose.yml stop backend
pct push 110 /tmp/inf-restore/var/backups/homelab/staging/infisical/infisical-compose.tar.gz /tmp/infisical-compose.tar.gz
pct exec 110 -- tar -xzf /tmp/infisical-compose.tar.gz -C /opt/infisical
pct exec 110 -- rm -f /tmp/infisical-compose.tar.gz
gunzip -c /tmp/inf-restore/var/backups/homelab/staging/infisical/infisical-postgres.sql.gz \
  | pct exec 110 -- docker exec -i infisical_postgres psql -U infisical -d postgres
pct exec 110 -- docker compose -f /opt/infisical/docker-compose.yml up -d
rm -rf /tmp/inf-restore
```

### Zone 2 Vaultwarden (`CT 120` — P0 Drill)

```bash
restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass \
  restore latest --target /tmp/vw-restore --include /var/backups/homelab/staging/vaultwarden

pct exec 120 -- docker compose -f /opt/vaultwarden/docker-compose.yml down
pct push 120 /tmp/vw-restore/var/backups/homelab/staging/vaultwarden/db.sqlite3 /opt/vaultwarden/vw-data/db.sqlite3
pct exec 120 -- docker compose -f /opt/vaultwarden/docker-compose.yml up -d
rm -rf /tmp/vw-restore
```

### Zone 2 Immich (`CT 121` — Full Recovery)

1. From Windows Break-Glass SSH on `haytham`: `./harden-pve-rbac.sh --unlock-dr 121`.
2. From `homelab-ops` on `devbox`: `ops-tf-apply` → `ops-ansible-apply host_devices.yml` → `ops-ansible-apply zone2_protected.yml`.
3. Immediately re-lock on `haytham`: `./harden-pve-rbac.sh --lock`.
4. Push original photos back from Windows to `CT 121` (`192.168.100.21`):
   ```bat
   tar -C "%PHOTOS_BACKUP_DIR%" -cf - library upload profile | ssh -i "%USERPROFILE%\.ssh\id_ed25519" root@192.168.100.21 "tar -xf - -C /opt/immich/library"
   ```
5. Restore `immich-postgres.sql.gz` from Track 1 `restic` into `immich_postgres` (with `immich_server` stopped, `database` running):
   ```bash
   gunzip -c immich-postgres.sql.gz | pct exec 121 -- docker exec -i immich_postgres psql -U postgres
   pct exec 121 -- docker compose -f /opt/immich/docker-compose.yml up -d
   ```

## 7. Manual Gaps

- Keep `vault_restic_password`, `CT 110`'s `ENCRYPTION_KEY` + `AUTH_SECRET`, and `haytham-control-bundle-*.tar.age` backed up offline (Windows KeePassXC + encrypted USB).
- Periodically plug in your external USB drive for Track 2 photos and run `scripts\pull-homelab-backups.bat --photos-only`.
- Both pull scripts deliberately omit deletes on Track 2 so an accidental deletion inside Immich never wipes your PC backup copy.
