---
id: ops-update-reboot-all
title: Runbook — System Update and Reboot All LXC
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, update, reboot, maintenance]
retrievable: true
---

# Runbook — System Update and Reboot All LXC

## 1. Purpose

Patch all active LXC (`apt upgrade`) and reboot in dependency-safe order without crashing consumers. Also applies Terraform resource resizes (cgroup limits require a container reboot).

## 2. When to use / not use

- Use: routine patching, post-`locals.tf` resize, post-maintenance fresh-start.
- Do not use for full builds — see `build-from-scratch.md`.

## 3. Dependency order (Phase 1 active LXCs)

Always reboot in depended-upon-first order (and network/ingress last):

| Order | Tier | CTIDs | Reason |
|---|---|---|---|
| 1 | 30 identity | 320 | Vaultwarden before apps |
| 2 | 60 media | 610 | Immich (self-contained DB + app) |
| 3 | 40 app + 90 obs | 440 910 | Homepage & Uptime Kuma leaf consumers |
| 4 | 10 network | 110 120 130 | Pi-hole, NPM, Tailscale last; brief downtime OK |

*(When Tier 20 is revived after the 16 GB RAM upgrade, prepend `210 220` then `230` before Tier 30.)*

Current active set (sourced from `../reference/ip-ctid-matrix.md`):

```bash
ALL_CTIDS="110 120 130 320 440 610 910"
```

## 4. Pre-update checklist

- [ ] No active bulk Immich uploads or ML/transcoding jobs.
- [ ] Run `systemctl start homelab-backup.service` on `haytham` before major upgrades.
- [ ] If `locals.tf` resized: `terraform plan` shows `~` in-place (not `-/+`), `apply` succeeded.
- [ ] Snapshot lightweight containers before risky upgrades (skip or be mindful of space on CT `610` if near SSD capacity):
  ```bash
  for ctid in 110 120 130 320 440 910; do pct snapshot $ctid "pre-update-$(date +%Y%m%d)"; done
  ```

## 5. Update (all, then reboot all — not interleaved)

```bash
for ctid in 110 120 130 320 440 610 910; do
  echo "=== Updating CT $ctid ==="
  pct exec $ctid -- bash -c "apt update && apt upgrade -y"
done
```

## 6. Reboot (dependency-safe)

Save as `reboot-all-lxc.sh` on node `haytham`, `chmod +x`:

```bash
#!/bin/bash
set -e
reboot_group() {
  local label="$1"; shift
  for ctid in "$@"; do
    echo ">> Rebooting CT $ctid ($label)..."
    pct reboot $ctid
    sleep 8
  done
  echo ">> Waiting extra 10s for $label to stabilize..."
  sleep 10
}
reboot_group "identity"     320
reboot_group "media"        610
reboot_group "app-and-obs"  440 910
reboot_group "network"      110 120 130
echo "All active Phase 1 containers rebooted in dependency-safe order."
```

`pct reboot` suffices for new cgroup limits; no manual shutdown/start needed.

## 7. Post-reboot verification

```bash
for ctid in 110 120 130 320 440 610 910; do pct status $ctid; done
# Expect all: status: running
for ctid in 110 120 130 320 440 610 910; do echo "=== CT $ctid ==="; pct config $ctid | grep -E "^(memory|swap|cores):"; done
# Cross-check vs locals.tf after resize
```

- [ ] All running, resources match `locals.tf`.
- [ ] Smoke: open `https://haytham.internal`, `https://vaultwarden.haytham.internal`, `https://immich.haytham.internal`, `https://uptime.haytham.internal`.
- [ ] Check `/dev/net/tun` on CT `130` and `/dev/dri/renderD128` on CT `610`.
- [ ] Suspicious logs: `pct exec <ctid> -- journalctl -p err -b`.

## 8. Rollback

```bash
pct rollback <ctid> pre-update-YYYYMMDD
# or for bad resize:
git checkout HEAD~1 -- terraform/locals.tf
terraform apply
pct reboot <ctid>
```

## 9. FAQ

**Q: Can I update+reboot one-by-one?**
A: Avoid — creates long per-service windows. Update all, then reboot in order.
