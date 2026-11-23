# Haytham Homelab — Ansible

Ansible configuration for the `haytham` homelab. Run from a WSL Ubuntu 24.04 checkout of this repository.

> Canonical docs live in `kb/`:
> - Strategy & Vault workflow: [kb/architecture/ansible-strategy.md](../kb/architecture/ansible-strategy.md)
> - Full build runbook: [kb/operations/build-from-scratch.md](../kb/operations/build-from-scratch.md)
> - Secret rotation: [kb/operations/secret-rotation.md](../kb/operations/secret-rotation.md)
> - Backup & restore: [kb/operations/backup-and-restore.md](../kb/operations/backup-and-restore.md)
> - Lean 8 GB scope & deferred tiers: [kb/decisions/ADR-007-lean-8gb-phase1.md](../kb/decisions/ADR-007-lean-8gb-phase1.md)

## Quick Start

```bash
# 1. Control-node dependencies (fresh WSL)
sudo apt install -y ansible openssh-client bind9-dnsutils rsync
ansible-galaxy collection install -r requirements.yml

# 2. Replace any CHANGEME secret in group_vars/*.yml with `ansible-vault encrypt_string`
#    (see kb/architecture/ansible-strategy.md)

# 3. Run playbooks in dependency order (Phase 1 lean 8 GB stack)
ansible-playbook host_devices.yml
ansible-playbook tier10.yml
ansible-playbook tier30.yml
ansible-playbook tier40.yml
ansible-playbook tier60.yml
ansible-playbook tier90.yml
ansible-playbook tier80.yml
```

*Deferred playbooks (`tier20.yml`, `karakeep` in `tier40.yml`) are preserved in-repo for revival after the 16 GB RAM upgrade.*
