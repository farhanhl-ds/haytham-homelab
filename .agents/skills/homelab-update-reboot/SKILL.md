---
name: homelab-update-reboot
description: >-
  Use this skill when the user asks to patch/update LXC containers (apt upgrade),
  apply Terraform CPU/RAM/swap/disk resizes, or reboot homelab containers in
  dependency-safe order.
---

# Homelab Update & Dependency-Safe Reboot (Security Zones)

Canonical runbook: `kb/operations/update-and-reboot.md`.

## Active Phase 1 CTIDs (`ID = 100 + last_octet`)

- **Zone 1 Immutable:** `110` (Infisical — patched separately via Windows Break-Glass SSH; rarely rebooted)
- **Zones 2–4 Managed:** `120 121 130 131 132 140 141` *(add `122 123 133 142` when deferred services revive).*

## 1. Pre-Update Checklist

1. Confirm no active bulk Immich uploads or heavy transcoding jobs.
2. Human triggers a fresh Track 1 backup on `haytham` (`192.168.100.2`) from Windows Break-Glass SSH:
   ```bash
   systemctl start homelab-backup.service
   ```
3. Optional Proxmox snapshots of lightweight CTs before major upgrades (skip 500 GB `CT 121` if SSD space is tight):
   ```bash
   for ctid in 110 120 130 131 132 140 141; do pct snapshot $ctid "pre-update-$(date +%Y%m%d)"; done
   ```
4. If applying a `terraform/locals.tf` CPU/RAM/swap/disk resize first:
   - Agent verifies `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan` shows `~` in-place (NOT `-/+` replace!).
   - Human applies via `sudo -iu homelab-ops && ops-tf-apply`.

## 2. Patch All Containers (Human on `haytham` `.2`)

```bash
for ctid in 120 121 130 131 132 140 141; do
  echo "=== Updating CT $ctid ==="
  pct exec $ctid -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y"
done
```

## 3. Dependency-Safe Reboot Order (Human on `haytham` `.2`)

Always reboot Zone 2 Protected Data → Zone 4 Apps & Ops → **Zone 3 Core Infra (`130 131 132`) LAST** (and leave Zone 1 `CT 110` running unless specifically patching it):

```bash
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
reboot_group "zone2-protected" 120 121
reboot_group "zone4-apps-ops"  140 141
reboot_group "zone3-infra"     130 131 132
```

## 4. Post-Reboot Verification & Rollback

- Agent runs: `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check` (verifies Zone 1 Infisical `.10`, Pi-hole DNS `@.30`, Docker containers on `.20/.21/.31/.40/.41`, `/dev/dri` on `.21`, Tailscale on `.32`, and backup timers on `.2`).
- **Rollback (Human on `haytham`):** `pct rollback <ctid> pre-update-YYYYMMDD` (clean up snapshots after verifying healthy).
