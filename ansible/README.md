# Haytham Homelab — Ansible

Ansible configuration for the `haytham` homelab organized by **Security Zones (`ID = 100 + IP`, `ADR-008`)**.

> Canonical docs live in `kb/`:
> - Zero-Trust Control Node & Security Zones: [kb/decisions/ADR-008-zero-trust-security-zones-and-infisical.md](../kb/decisions/ADR-008-zero-trust-security-zones-and-infisical.md)
> - Hardening & Recovery Runbook: [kb/operations/control-node-hardening-and-recovery.md](../kb/operations/control-node-hardening-and-recovery.md)
> - Full build runbook: [kb/operations/build-from-scratch.md](../kb/operations/build-from-scratch.md)
> - Backup & restore: [kb/operations/backup-and-restore.md](../kb/operations/backup-and-restore.md)

## Execution Model (OS Privilege Split)

Secrets are **not** stored in `ansible/.vault_pass` or `group_vars/*.yml`. All secrets live in **Zone 1 Immutable Infisical (`CT 110` @ `192.168.100.10`)** and are injected into RAM (`/dev/shm`) at runtime by `/usr/local/libexec/haytham-ops/ops-ansible-*`.

```bash
# AI Agent (homelab-agent) — read-only dry-run ONLY:
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check host_devices.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone3_infra.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone2_protected.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone4_apps.yml
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check host_backups.yml

# Human Operator (sudo -iu homelab-ops) — live apply in dependency order:
ops-ansible-apply host_devices.yml
ops-ansible-apply zone3_infra.yml
ops-ansible-apply zone2_protected.yml
ops-ansible-apply zone4_apps.yml
ops-ansible-apply host_backups.yml
```
