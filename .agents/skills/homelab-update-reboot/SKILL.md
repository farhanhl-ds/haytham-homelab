---
name: homelab-update-reboot
description: >-
  Use this skill when the user asks to patch/update LXC containers (apt upgrade),
  apply Terraform CPU/RAM/swap/disk resizes, or reboot homelab containers in
  dependency-safe order.
---

# Homelab Update & Dependency-Safe Reboot

Canonical runbook: `kb/operations/update-and-reboot.md`.

## Active Phase 1 CTIDs

`110 120 130 320 440 610 910` *(update this list if Tier 20 or Karakeep are revived).*

## 1. Pre-Update Checklist

1. Confirm no active bulk Immich uploads or heavy transcoding jobs.
2. Trigger a fresh Track 1 backup on `haytham` before major patches:
   ```bash
   ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 "systemctl start homelab-backup.service"
   ```
3. For risky upgrades, take Proxmox snapshots of lightweight CTs (be mindful of free space before snapshotting 500 GB CT `610`):
   ```bash
   ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 \
     'for ctid in 110 120 130 320 440 910; do pct snapshot $ctid "pre-update-$(date +%Y%m%d)"; done'
   ```
4. If applying a `terraform/locals.tf` resize first, verify `terraform plan` shows `~` in-place (NOT `-/+` replace!), then run `terraform apply -parallelism=1` with `ssh-agent`.

## 2. Patch All Containers (Do Not Interleave Reboots)

```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 '
  for ctid in 110 120 130 320 440 610 910; do
    echo "=== Updating CT $ctid ==="
    pct exec $ctid -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y"
  done
'
```

## 3. Dependency-Safe Reboot Order

Always reboot depended-upon tiers first and **network/ingress (`110 120 130`) last** (prepend `210 220` then `230` if Tier 20 is active):
1. **Identity:** `320` (Vaultwarden)
2. **Media:** `610` (Immich)
3. **App & Observability:** `440` (Homepage), `910` (Uptime Kuma)
4. **Network / Ingress:** `110` (Pi-hole), `120` (NPM), `130` (Tailscale)

```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 '
  set -e
  reboot_group() {
    local label="$1"; shift
    for ctid in "$@"; do
      echo ">> Rebooting CT $ctid ($label)..."
      pct reboot "$ctid"
      sleep 8
    done
    sleep 10
  }
  reboot_group "identity"    320
  reboot_group "media"       610
  reboot_group "app-and-obs" 440 910
  reboot_group "network"     110 120 130
'
```

## 4. Post-Reboot Verification & Rollback

```bash
ssh -i ~/.ssh/id_ed25519 root@192.168.100.2 '
  pct list
  echo "--- passthrough devices ---"
  pct exec 130 -- ls -la /dev/net/tun
  pct exec 610 -- ls -la /dev/dri
  echo "--- docker containers ---"
  for ctid in 120 320 440 610 910; do
    echo "=== CT $ctid ==="
    pct exec $ctid -- docker ps --format "table {{.Names}}\t{{.Status}}"
  done
'
dig haytham.internal @192.168.100.11 +short
```

- **Rollback:** `pct rollback <ctid> pre-update-YYYYMMDD` (and clean up old snapshots once healthy so `local-lvm` stays lean).
