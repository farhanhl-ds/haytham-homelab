---
id: ops-update-reboot-all
title: Runbook — System Update and Reboot All LXC
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, update, reboot, maintenance, zones]
retrievable: true
---

# Runbook — System Update and Reboot All LXC

## 1. Purpose

Patch all active LXCs (`apt upgrade`) and reboot in dependency-safe Security-Zone order without crashing consumers. Also applies Terraform resource resizes (cgroup limits require a container reboot).

## 2. When to Use / Not Use

- Use: routine patching, post-`locals.tf` resize, post-maintenance fresh-start.
- Do not use for full builds — see `build-from-scratch.md`.

## 3. Dependency Order (Phase 1 Active LXCs — `ID = 100 + last_octet`)

Always reboot Zone 2 Protected Data → Zone 4 Ephemeral Apps & Ops → **Zone 3 Core Infra (`130 131 132`) last**. Zone 1 `CT 110` (Infisical) is patched separately on demand so secrets remain available throughout maintenance.

| Order | Security Zone | CTIDs | Reason |
|---|---|---|---|
| 1 | Zone 2 Protected Data | `120 121` | Vaultwarden & Immich before consumers |
| 2 | Zone 4 Apps & Ops | `140 141` | Homepage & Uptime Kuma leaf consumers |
| 3 | Zone 3 Core Infra | `130 131 132` | Pi-hole, NPM, Tailscale last; brief downtime OK |

*(When deferred Zone 2 Postgres `122` / Zone 3 Redis `133` revive after 16 GB RAM, reboot `122 133` before `120 121`.)*

```bash
MANAGED_CTIDS="120 121 130 131 132 140 141"
```

## 4. Pre-Update Checklist

- [ ] No active bulk Immich uploads or ML/transcoding jobs.
- [ ] Run `systemctl start homelab-backup.service` on `haytham` (Windows Break-Glass SSH) before major upgrades.
- [ ] If `locals.tf` resized: `ops-tf-plan` shows `~` in-place (not `-/+`), human `ops-tf-apply` succeeded.
- [ ] Snapshot lightweight containers before risky upgrades (be mindful of free space before snapshotting 500 GB `CT 121`):
  ```bash
  for ctid in 110 120 130 131 132 140 141; do pct snapshot $ctid "pre-update-$(date +%Y%m%d)"; done
  ```

## 5. Update (All, Then Reboot All — Not Interleaved)

From Windows Break-Glass SSH on `haytham` (`192.168.100.2`):

```bash
for ctid in 120 121 130 131 132 140 141; do
  echo "=== Updating CT $ctid ==="
  pct exec $ctid -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y"
done
```

## 6. Reboot (Dependency-Safe)

```bash
set -e
reboot_group() {
  local label="$1"; shift
  for ctid in "$@"; do
    echo ">> Rebooting CT $ctid ($label)..."
    pct reboot "$ctid"
    sleep 8
  done
  echo ">> Waiting extra 10s for $label to stabilize..."
  sleep 10
}
reboot_group "zone2-protected" 120 121
reboot_group "zone4-apps-ops"  140 141
reboot_group "zone3-infra"     130 131 132
echo "All active Phase 1 managed containers rebooted in dependency-safe order."
```

## 7. Post-Reboot Verification

Run read-only verification on `haytham-ctl`:
```bash
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
```

And on `haytham`:
```bash
for ctid in 110 120 121 130 131 132 140 141; do
  echo "=== CT $ctid ==="
  pct status $ctid
  pct config $ctid | grep -E "^(memory|swap|cores|protection):"
done
```

- [ ] All running, `protection: 1` intact on `110`, `120`, `121`.
- [ ] `/dev/net/tun` present on `CT 132` and `/dev/dri/renderD128` present on `CT 121`.
- [ ] Browser smoke: `https://haytham.internal`, `https://infisical.haytham.internal`, `https://vaultwarden.haytham.internal`, `https://immich.haytham.internal`, `https://uptime.haytham.internal`.

## 8. Rollback

```bash
pct rollback <ctid> pre-update-YYYYMMDD
```

## 9. Manual Gaps

- Clean up temporary `pre-update-YYYYMMDD` Proxmox snapshots once verified healthy so `local-lvm` stays lean.
- Patch Zone 1 `CT 110` (Infisical) separately from Windows Break-Glass SSH during quiet windows.
