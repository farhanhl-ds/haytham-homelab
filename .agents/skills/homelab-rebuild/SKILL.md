---
name: homelab-rebuild
description: >-
  Use this skill when the user asks to rebuild, wipe, reprovision, or reconcile
  the Haytham Homelab LXCs (Zones 2-4) from scratch using Terraform and Ansible.
---

# Homelab Rebuild (Security Zones 2–4, Zero-Trust Gate)

Canonical runbooks: `kb/operations/build-from-scratch.md` and `kb/operations/control-node-hardening-and-recovery.md`.

## 1. Clarify Before Acting (Mandatory)

Confirm with the user before any destructive step:
1. **Rebuild mode:** Ephemeral Zone 3–4 rebuild (`130–141`) vs. full Zone 2–4 DR rebuild vs. bare-metal Proxmox reinstall.
2. **Zone 1 & Zone 2 protection (`ADR-008`):**
   - **Zone 1 (`CT 110` Infisical @ `.10`)** is **immutable** and outside Terraform — it survives every rebuild untouched.
   - **Zone 2 (`CT 120` Vaultwarden @ `.20`, `CT 121` Immich @ `.21`)** is locked with `protection=1` + `HomelabProtectedOps`. Any destroy/recreate of Zone 2 requires the human operator to confirm backups first and run `scripts/proxmox/harden-pve-rbac.sh --unlock-dr <ctid>` from Windows Break-Glass SSH.
3. **DNS safe mode:** If the workstation uses `192.168.100.30` (Pi-hole) as primary DNS, remind them to switch to safe mode (`1.1.1.1` first — `kb/operations/dns-workstation-swap.md`) before touching `CT 130`.

## 2. Agent Read-Only Pre-Flight & Dry-Run (`homelab-agent`)

When running as `homelab-agent` inside `/srv/haytham-homelab`, invoke **only** the allowlisted read-only wrappers:

```bash
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check host_devices.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone3_infra.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone2_protected.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone4_apps.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check host_backups.yml
```

## 3. Human Operator Live Execution (`sudo -iu homelab-ops`)

Hand off these mutating commands to the human operator (NEVER auto-run by `homelab-agent`):

```bash
sudo -iu homelab-ops

# 1. Terraform apply (-parallelism=1, pulls /terraform secrets from Zone 1 Infisical into RAM)
ops-tf-apply

# 2. Clear stale SSH host keys for rebuilt CTs
for ip in 192.168.100.20 192.168.100.21 192.168.100.30 192.168.100.31 192.168.100.32 192.168.100.40 192.168.100.41; do
  ssh-keygen -f ~/.ssh/known_hosts -R "$ip" 2>/dev/null || true
done

# 3. Host device passthrough + zone playbooks in dependency order
ops-ansible-apply host_devices.yml
# Wait until CT 132 (.32) and CT 121 (.21) accept SSH after pct reboot
ops-ansible-apply zone3_infra.yml
ops-ansible-apply zone2_protected.yml
ops-ansible-apply zone4_apps.yml
ops-ansible-apply host_backups.yml

# 4. Refresh encrypted off-host control bundle & re-lock Proxmox RBAC
ops-bundle pack
```

Then from Windows Break-Glass SSH on `haytham` (`192.168.100.2`):
```bash
./harden-pve-rbac.sh --lock
```

## 4. Verification & Post-Build Manual Gaps

Run `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check` and remind the user of the non-IaC UI steps:
1. **NPM (`http://192.168.100.31:81`):** Admin account, import wildcard cert, add 8 Proxy Hosts (including `infisical.haytham.internal → 192.168.100.10:8080`).
2. **Tailscale (`CT 132`):** `tailscale up --advertise-routes=192.168.100.0/24 --accept-dns=false` → approve route & disable key expiry → Split DNS `haytham.internal → 192.168.100.30`.
3. **Vaultwarden (`CT 120`):** Create master account (temporarily allow signups) → lock `SIGNUPS_ALLOWED="false"`.
4. **Immich (`CT 121`):** Create admin account → enable Intel Quick Sync in Video Transcoding settings.
5. **Uptime Kuma (`CT 141`):** Create admin account → add internal monitors (ignore self-signed TLS).
6. **Workstation DNS:** Restore Pi-hole primary (`192.168.100.30`, fallback `1.1.1.1`).
