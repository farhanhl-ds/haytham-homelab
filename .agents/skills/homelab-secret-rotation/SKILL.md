---
name: homelab-secret-rotation
description: >-
  Use this skill when the user asks to rotate homelab secrets in Zone 1 Infisical
  (CT 110), rotate the homelab-ops-ro Machine Identity, or rotate Proxmox/SSH credentials.
---

# Homelab Secret Rotation (Zone 1 Infisical — Zero Static Vault)

Canonical runbooks: `kb/operations/secret-rotation.md` and `kb/services/zone1-infisical-110.md`.

## Security Hygiene (Non-Negotiable)

- **Zero plaintext secrets in agent context:** `homelab-agent` has **zero** Infisical credentials and cannot read `/var/lib/haytham-ops/`. Never ask the user to paste plaintext secrets into chat.
- **Human-only rotation:** All secret creation and rotation happens inside the **Zone 1 Infisical Web UI** (`http://192.168.100.10:8080` or `https://infisical.haytham.internal`) from the Windows PC (with MFA & audit log). `homelab-ops-ro` is strictly read-only.
- **Compromised secret = regenerate immediately.**

## Workflow A — Rotate an Application or Terraform Secret

1. **Human (Windows browser → Infisical UI `haytham-homelab` / `prod`):**
   - `/terraform`: `TF_VAR_pve_api_token`, `TF_VAR_ct_root_password`
   - `/proxmox`: `vault_restic_password`
   - `/zone2`: `vault_vaultwarden_admin_token`, `vault_immich_db_password`
   - `/zone3`: `vault_pihole_webpassword`, `vault_tailscale_authkey`
   - Update the secret value in Infisical UI (previous version is retained in Infisical audit history).
2. **Human (`sudo -iu homelab-ops` on `devbox`):** Re-run the owning Ansible playbook so the service picks up the rotated value:
   ```bash
   ops-ansible-apply zone3_infra.yml     # for /zone3 secrets
   ops-ansible-apply zone2_protected.yml # for /zone2 secrets
   ops-ansible-apply host_backups.yml    # for /proxmox secrets
   ```
3. **Special caution for `vault_restic_password` (`/proxmox`):** Changing the password on an *existing* `restic` repo requires running `restic key add` / `restic key remove` on `haytham` BEFORE running `ops-ansible-apply host_backups.yml`, otherwise backups fail to unlock the repo. Update your offline emergency sheet immediately.

## Workflow B — Rotate `homelab-ops-ro` Machine Identity or Control-Node SSH Key

Required after any suspected `devbox` compromise:
1. In Infisical UI → Access Control → Machine Identities → `homelab-ops-ro` → revoke old Universal Auth Client Secret and issue a new one.
2. Update `/var/lib/haytham-ops/infisical-ops.env` (`0600 homelab-ops`) and re-pack recovery bundle (`ops-bundle pack`).
3. To rotate `id_ed25519_control`, regenerate in `/var/lib/haytham-ops/.ssh/`, authorize the new `.pub` key on `haytham` (`.2`) and active LXCs (never `CT 110`), and delete the old key from `/root/.ssh/authorized_keys` via Windows Break-Glass SSH.

## Non-Infisical Exceptions (UI Accounts)

- **NPM admin (`131`), Vaultwarden master (`120`), Immich admin (`121`), Uptime Kuma admin (`141`), pgAdmin (`142`, deferred):** App-level accounts rotated inside each web UI.
- **Infisical `ENCRYPTION_KEY` (`CT 110`):** NEVER change after storing secrets (breaks DB decryption).
