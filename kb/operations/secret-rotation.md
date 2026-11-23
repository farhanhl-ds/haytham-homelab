---
id: ops-secret-rotation
title: Runbook — Secret Rotation
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, security, vault, rotation]
retrievable: true
---

# Runbook — Secret Rotation

## 1. Purpose

Rotate the Ansible Vault master password and/or individual secrets. Covers the pgAdmin first-run exception.

## 2. Hygiene rules (apply from day one)

- Any secret exposed outside its intended store counts as compromised — regenerate, not just re-wrap.
- Exclude `.vault_pass` from every archive: `zip -r project.zip . -x ".vault_pass"` (`.gitignore` does not protect `zip`).
- Never paste generated values into chat or logs. Generate, encrypt, then `unset SECRET; history -c`.

## 3. Rotate master password only (re-wrap same values)

Because `group_vars/*.yml` uses **inline `!vault` strings** mixed with plaintext YAML (not whole-file encryption), `ansible-vault rekey` cannot be run directly on those files. To rotate the master vault password:

```bash
cd ansible
cp .vault_pass .vault_pass.old
openssl rand -base64 24 > .vault_pass.new && chmod 600 .vault_pass.new

# For each vault_* variable across group_vars/{proxmox,tier10,tier20,tier30,tier40,tier60}.yml:
# 1. Read current plaintext with .vault_pass.old:
#    ansible localhost -m debug -a "var=vault_pihole_webpassword" -e @group_vars/tier10.yml --vault-password-file .vault_pass.old
# 2. Re-encrypt with .vault_pass.new:
#    ansible-vault encrypt_string '<plaintext>' --name 'vault_pihole_webpassword' --vault-password-file .vault_pass.new
# 3. Replace the !vault block in group_vars/<group>.yml.
# 4. Once all blocks are replaced:
mv .vault_pass.new .vault_pass && rm -f .vault_pass.old
```

No service restart is needed when only the vault master password changes (decrypted values are unchanged).

## 4. Regenerate individual secrets (new values)

```bash
SECRET1=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32)
ansible-vault encrypt_string "$SECRET1" --name 'vault_karakeep_nextauth_secret'
# paste !vault block into group_vars/tier40.yml, replacing old block
unset SECRET1; history -c
```

Then re-run the owning playbook:

```bash
ansible-playbook tier10.yml  # etc. per tier
```

Cross-tier constraint: if an app ever consumes another tier's secret, both copies must share plaintext (generate once, encrypt twice under tier-scoped names). No such pairs exist in the initial build.

## 5. Exceptions

- **pgAdmin login password:** `PGADMIN_DEFAULT_PASSWORD` applies on first run only. Vault change + re-run is ignored for existing accounts. Rotate via UI (User Management → Change Password) or wipe `./data` to replay first run.
- **NPM admin:** not in Vault at all (SQLite in container). Change in NPM UI.
- **Service self-registrations** (Vaultwarden master, Karakeep user): app-level accounts, rotated in-app, not via Vault.

## 6. Verification

- Read-back check (never `cat` vault files for values):
  ```bash
  ansible localhost -m debug -a "var=vault_pgadmin_default_password" -e @group_vars/tier20.yml --vault-password-file .vault_pass
  ```
- Login smoke per service (see each `services/*.md §5`).

## 7. FAQ

**Q: Rekey or regenerate?**
A: Rekey = same secrets, new master password (fast, `.vault_pass` exposure only). Regenerate = new secret values (required if a secret value itself was exposed).
