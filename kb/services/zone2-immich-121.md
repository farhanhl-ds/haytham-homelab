---
id: svc-immich-610
title: Immich — Tier 60 Media (CTID 121)
tier: "60"
ctid: "121"
ip: 192.168.100.21
status: planned
last_verified: unreleased
tags: [immich, photos, media, tier60, docker, quicksync]
retrievable: true
---

# Immich — Tier 60 Media (CTID 121)

## 1. Purpose

Self-hosted photo and video backup/management platform (primary home for migrated iPhone photos and Live Photos). Runs as an unprivileged LXC with a self-contained 4-container Docker Compose bundle and Intel Quick Sync hardware transcoding.

## 2. Spec

| Field | Value |
|---|---|
| CTID / IP | 610 / `192.168.100.21` (see `../reference/ip-ctid-matrix.md`) |
| Resources | 3 cores / 4,096 MB RAM / 2,048 MB swap / 500 GB thin-provisioned disk (`local-lvm`) |
| Base | Ubuntu 24.04 LXC + Docker (`roles/docker`), 4-container bundle: `immich-server`, `immich-machine-learning`, `valkey:9`, `postgres:14-vectorchord` |
| Device passthrough | `/dev/dri/renderD128` + `/dev/dri/card0` via `ansible/host_devices.yml` (Intel HD 630 Quick Sync) |
| DB | Bundled Postgres with VectorChord (do **not** wire to shared Tier 20 Postgres/Redis) |

## 3. Provisioning

- Terraform: `module.tier60["immich"]` (`nesting=true`, 500 GB thin-provisioned on `local-lvm`).
- Host device passthrough: `ansible-playbook host_devices.yml` (`roles/pve_devices` attaches `/dev/dri/renderD128` and `/dev/dri/card0` with matching `render`/`video` GIDs).
- Ansible: `tier60.yml` → `roles/immich` (depends on `roles/docker`), pinned to `immich_version: v3.4.2`.

## 4. Configuration

- **Secret:** `vault_immich_db_password` in `group_vars/tier60.yml` (32-char alphanumeric; written to `/opt/immich/.env` with `mode: 0600` and `no_log: true`).
- **8 GB RAM tuning:** `MACHINE_LEARNING_WORKERS=1` and `MACHINE_LEARNING_REQUEST_THREADS=2` prevent ML jobs from starving other containers during bulk iPhone uploads.
- **Intel HD 630 Hardware Acceleration:** After first login, open **Administration → Settings → Video Transcoding Settings → Hardware Acceleration** and select **VAAPI** (preferred over **Quick Sync / QSV** on 7th-gen Intel HD 630 Kaby Lake — uses the same `/dev/dri/renderD128` hardware engine while avoiding QSV `ffmpeg` deadlocks on iPhone `.mov` files).
- **NPM Proxy Host:** `immich.haytham.internal → 192.168.100.21:2283`, wildcard cert, Force SSL + HTTP/2, **Websockets Support ON**, and add Custom Nginx Configuration for large video uploads:
  ```nginx
  client_max_body_size 50000M;
  proxy_read_timeout 600s;
  proxy_send_timeout 600s;
  ```
- **iPhone Photo Migration (no Samba required):**
  - **Live sync:** Install the official **Immich iOS app**, point to `https://immich.haytham.internal` (over Wi-Fi or Tailscale), and enable Background Backup.
  - **Bulk archive import:** Use `immich-go` from your workstation/WSL to upload existing photo folders or iCloud exports directly via the Immich HTTP API.

## 5. Verification

```bash
pct exec 121 -- ls -la /dev/dri
# Expect: card0 and renderD128 present

ssh root@192.168.100.21 "docker ps"
# Expect: 4 containers Up (immich_server, immich_machine_learning, immich_redis, immich_postgres — healthy)
```

Browser: `https://immich.haytham.internal` → create admin account → enable VAAPI hardware acceleration → upload a test photo and short video → confirm thumbnail, Smart Search, and playback.

## 6. Data & Backup Criticality

> **Never run `terraform destroy` without verifying your off-host backup first.** CT `610` holds up to 500 GB of primary photos on a single SSD.

- **Track 1 (daily, automated):** Proxmox dumps `immich_postgres` via `pg_dumpall` into the encrypted `restic` repo (`/var/backups/homelab/restic`), pulled to your PC.
- **Track 2 (incremental SSH pull):** `scripts/pull-homelab-backups.bat` (native Windows `cmd` via inbox `ssh.exe` + `tar.exe`) or `scripts/pull-homelab-backups.sh` (Linux/WSL `rsync`) mirrors `/opt/immich/library/{library,upload,profile}/` directly to your Windows PC or external USB drive (excluding regeneratable `thumbs/` and `encoded-video/`). See `../operations/backup-and-restore.md`.

## 7. Known gotchas

- **Video transcoding stalls at 0% CPU with Quick Sync (`QSV`):** On 7th-gen Intel HD 630 (Kaby Lake), `h264_qsv` + `scale_qsv` can deadlock indefinitely at `0.0%` CPU on certain iPhone `.mov` files, blocking the entire Video Conversion queue while `immich_server` remains `Up (healthy)`. Switch Hardware Acceleration to **VAAPI** in Immich Admin UI; to unstick an active hung job without restarting Docker, find the wedged `ffmpeg` PID on CT `121` (`ps -eo pid,pcpu,args | grep ffmpeg`) and `kill -9 <pid>`.
- **Quick Sync / VAAPI fails with permission denied:** Re-run `ops-ansible-apply host_devices.yml` and confirm `/dev/dri/renderD128` GID inside CT `121` matches `getent group render`.
- **Large video upload fails with HTTP 413:** Missing `client_max_body_size 50000M;` in the NPM Proxy Host Advanced tab.
- **High CPU/RAM during initial iPhone bulk import:** Expected during first-time facial recognition and thumbnailing; pause ML jobs temporarily in Immich Administration → Jobs if needed, or let them finish overnight.

## 8. FAQ

**Q: Why LXC instead of a VM?**
A: Dynamic RAM sharing on 8 GB RAM (~1.3–1.8 GB idle vs. 4 GB static KVM lock) and straightforward non-exclusive `/dev/dri` Quick Sync passthrough. See `../decisions/ADR-007-lean-8gb-phase1.md`.

**Q: Do I need Samba to move photos in or out?**
A: No. Import via the Immich iOS app or `immich-go`; back up originals over SSH via `scripts/pull-homelab-backups.bat` (Windows `cmd`) or `scripts/pull-homelab-backups.sh` (Linux/WSL).
