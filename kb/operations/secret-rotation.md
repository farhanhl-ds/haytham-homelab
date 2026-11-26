---
id: ops-secret-rotation
title: Runbook — Secret Rotation (Zone 1 Infisical)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, security, infisical, rotation]
retrievable: true
---

# Runbook — Secret Rotation (Zone 1 Infisical)

## 1. Purpose

Rotate homelab application secrets, Proxmox/Terraform credentials, the `homelab-ops-ro` Infisical Machine Identity, or the revocable `haytham-ctl` SSH key without ever exposing plaintext values to `homelab-agent` or storing static `.vault_pass` files on disk (`ADR-008`).

## 2. When to Use

- Scheduled credential rotation or immediate regeneration after a suspected exposure/compromise.
- Rebuilding `haytham-ctl` after a suspected prompt-injection incident.

## 3. Prerequisites

- Zone 1 Infisical (`CT 110` @ `http://192.168.100.10:8080`) accessible from your Windows PC browser (Human Admin account + MFA).
- Human operator access to `homelab-ops` on `haytham-ctl` (`sudo -iu homelab-ops`) and Windows Break-Glass SSH to `haytham` (`192.168.100.2`).

## 4. Steps

### A. Rotate an Application or Terraform Secret

1. Open **Infisical Web UI** (`http://192.168.100.10:8080` or `https://infisical.haytham.internal`) from your Windows PC.
2. Navigate to Project `haytham-homelab` → Environment `prod` → target folder:
   - `/terraform`: `TF_VAR_pve_api_token`, `TF_VAR_ct_root_password`
   - `/proxmox`: `vault_restic_password`
   - `/zone2`: `vault_vaultwarden_admin_token`, `vault_immich_db_password`
   - `/zone3`: `vault_pihole_webpassword`, `vault_tailscale_authkey`
3. Replace the secret value with a fresh random 32-character value and save (Infisical records full version history & audit log).
4. Re-apply the owning Ansible playbook as human operator (`sudo -iu homelab-ops` on `haytham-ctl`):
   ```bash
   ops-ansible-apply zone3_infra.yml      # Pi-hole / Tailscale
   ops-ansible-apply zone2_protected.yml  # Vaultwarden / Immich
   ops-ansible-apply host_backups.yml     # Proxmox restic password
   ```

> **Special caution for `vault_restic_password` (`/proxmox`):** Before running `ops-ansible-apply host_backups.yml` against an *existing* `restic` repository, add the new key to the repo on `haytham` first (`restic -r /var/backups/homelab/restic --password-file /etc/homelab-backup/restic.pass key add`), verify unlock with the new key, then update Infisical + run `host_backups.yml`, and remove the old key (`restic key remove`). Update your offline emergency sheet immediately.

### B. Rotate `homelab-ops-ro` Machine Identity (After `haytham-ctl` Compromise)

1. In Infisical UI → Access Control → Machine Identities → `homelab-ops-ro` → revoke the compromised Universal Auth Client Secret and create a new one.
2. On `haytham-ctl` (`sudo -iu homelab-ops`), update `INFISICAL_CLIENT_SECRET` in `/var/lib/haytham-ops/infisical-ops.env` (`chmod 0600`).
3. Refresh your encrypted off-host recovery bundle: `ops-bundle pack`.

### C. Rotate Proxmox API Token (`terraform@pve!terraform`)

1. From Windows Break-Glass SSH on `haytham` (`192.168.100.2`):
   ```bash
   pveum user token remove terraform@pve terraform
   pveum user token add terraform@pve terraform --privsep 0
   ```
2. Store the new `terraform@pve!terraform=<uuid>` value in Infisical (`/terraform` → `TF_VAR_pve_api_token`) and test `ops-tf-plan`.

## 5. Verification

- Validate read-only wrappers succeed with the rotated secret:
  ```bash
  sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan
  sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone3_infra.yml
  sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
  ```
- Confirm login smoke per rotated service and inspect Infisical Audit Logs.

## 6. Rollback

In Infisical UI, click the secret's **Version History** to revert to the previous value if an application fails to restart, then re-run `ops-ansible-apply <playbook>`.

## 7. Manual Gaps

- **Non-Infisical UI accounts** (NPM admin `.31`, Vaultwarden master `.20`, Immich admin `.21`, Uptime Kuma admin `.41`, deferred pgAdmin `.42`) are rotated inside each web UI.
- **Infisical `ENCRYPTION_KEY` (`CT 110`):** Never modify after secrets exist; back up offline (`services/zone1-infisical-110.md §4`).
