---
name: homelab-secret-rotation
description: >-
  Use this skill when the user asks to rotate Ansible Vault secrets, rekey
  .vault_pass, or bootstrap encrypted CHANGEME secrets in ansible/group_vars/.
---

# Homelab Secret Rotation & Vault Bootstrap

Canonical runbook: `kb/operations/secret-rotation.md`.

## Security Hygiene (Non-Negotiable)

- **Never print, echo, or paste plaintext secrets** into chat, tool output, or commit messages.
- **User-generated secrets:** When generating a new secret that must stay private (especially `vault_restic_password` or `.vault_pass`), give the user the exact shell command to run in their own terminal so plaintext never enters the agent transcript, and remind them to run `unset SECRET; history -c`.
- **Compromised secret = regenerate**, not just rekey. Rekeying only changes the `.vault_pass` wrapper around the same plaintext values.

## Workflow A — Bootstrap or Rotate an Individual `vault_*` Secret

1. Generate and encrypt inline in `ansible/` (never whole-file encrypt `group_vars/*.yml`):
   ```bash
   cd /home/farhan/haytham-homelab/ansible
   SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
   ansible-vault encrypt_string "$SECRET" --name 'vault_<var_name>'
   unset SECRET; history -c
   ```
2. Paste the resulting `!vault |` block into the target `ansible/group_vars/<group>.yml`.
3. Re-run the owning tier playbook (`ansible-playbook tier<N>.yml`) so the service picks up the new value.
4. **Special caution for `vault_restic_password` (`proxmox.yml`):** Changing the password on an *existing* `restic` repo requires `restic key add` / `restic key remove` on `haytham` before updating `/etc/homelab-backup/restic.pass`, otherwise backups fail to unlock the repo. Record the new password offline immediately.

## Workflow B — Rotate Master Vault Password (`.vault_pass` Rekey)

Because `group_vars/*.yml` mixes plaintext YAML with inline `!vault` strings, `ansible-vault rekey` does **not** work directly. Follow `kb/operations/secret-rotation.md §3`:
1. Copy `.vault_pass` → `.vault_pass.old` and generate `.vault_pass.new` (`chmod 600`).
2. For every `vault_*` block across `group_vars/{proxmox,tier10,tier20,tier30,tier40,tier60}.yml`, decrypt with `.vault_pass.old`, re-encrypt with `ansible-vault encrypt_string --vault-password-file .vault_pass.new`, and replace the block.
3. Swap `mv .vault_pass.new .vault_pass && rm -f .vault_pass.old`. No service restart needed.

## Non-Vault Exceptions (Do Not Look in Ansible Vault)

- **NPM admin, Vaultwarden master, Immich admin, Uptime Kuma admin:** App-level accounts in SQLite/Postgres — rotate inside each web UI.
- **pgAdmin (`230`, deferred):** `PGADMIN_DEFAULT_PASSWORD` applies on first run only — rotate in UI.

## Verification

- Validate YAML + Vault decryption without printing secrets:
  ```bash
  cd /home/farhan/haytham-homelab/ansible
  ansible-inventory --list >/dev/null && echo "Vault & inventory OK"
  ```
- Re-run the affected tier playbook with `--check` or apply cleanly and confirm `failed=0` and healthy service login.
