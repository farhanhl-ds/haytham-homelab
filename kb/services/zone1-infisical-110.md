---
id: svc-zone1-infisical-110
title: Zone 1 — Infisical Secrets Manager (CT 110)
tier: "zone1"
ctid: "110"
ip: 192.168.100.10
status: planned
last_verified: unreleased
tags: [service, zone1, immutable, infisical, secrets-manager]
retrievable: true
---

# Zone 1 — Infisical Secrets Manager (CT 110)

## 1. Purpose

Self-hosted, immutable machine secrets manager serving as the single source of truth for all `haytham-homelab` provisioning and application secrets (`ADR-008`). Provisioned out-of-band right after Proxmox host installation so it survives full Terraform destroys/rebuilds of Zones 2–4 without circular dependencies.

## 2. Spec

| Attribute | Value |
|---|---|
| CTID / IP | `110` / `192.168.100.10/24` (`ID = 100 + last_octet`) |
| Zone / Pool | Zone 1 Immutable Core / `homelab-immutable` |
| Proxmox ACL | **ZERO ACL** for `terraform@pve` (HTTP 403) |
| Hypervisor Lock | `protection: 1` (permanent) |
| CPU / RAM / Swap | 2 cores / `1536 MB` / `1024 MB` (tuned lean for 8 GB host: ~600–900 MB RSS idle) |
| Disk | `8 GB` on `local-lvm` |
| DNS (Container) | `1.1.1.1` (avoids circular dependency on Zone 3 Pi-hole `.30`) |
| Stack | Self-contained Docker Compose: `infisical` (`v0.104.0-postgres`, `NODE_OPTIONS=--max-old-space-size=512`), `db-migration` (`npm run migration:latest`), `postgres:16-alpine` (`shared_buffers=64MB`), `redis:7-alpine` (`maxmemory 64mb`, `maxmemory-policy noeviction`) |
| Direct API URL | `http://192.168.100.10:8080` (used by `homelab-ops` wrappers so automation works even when Pi-hole/NPM are down) |
| Optional NPM Host | `https://infisical.haytham.internal → 192.168.100.10:8080` (WebSockets ON) |
| SSH Access | **Windows Break-Glass key ONLY** (`haytham-ctl` control node has zero SSH access to CT `110`) |

## 3. Provisioning Ref

- Out-of-band bootstrap script (run directly on Proxmox host `haytham` as `root`): `scripts/zone1/bootstrap-infisical.sh /root/windows_breakglass.pub`
- **Never** declared in `terraform/locals.tf` or `ansible/inventory/hosts.yml`.
- Pool & ACL lock enforced by `scripts/proxmox/harden-pve-rbac.sh --lock`.

## 4. Configuration

### Project & Secret Path Layout

Create Project `haytham-homelab` (Environment: `prod`) in Infisical Web UI (`http://192.168.100.10:8080`) with the following folder structure:

| Folder Path | Secret Keys | Consumed By |
|---|---|---|
| `/terraform` | `TF_VAR_pve_api_token`, `TF_VAR_ct_root_password` | `ops-tf-plan`, `ops-tf-apply` |
| `/proxmox` | `vault_restic_password` | `ops-ansible-{check,apply} host_backups.yml` |
| `/zone2` | `vault_vaultwarden_admin_token`, `vault_immich_db_password` *(deferred: `vault_postgres_superuser_password`, `vault_karakeep_*`)* | `ops-ansible-{check,apply} zone2_protected.yml` |
| `/zone3` | `vault_pihole_webpassword`, `vault_tailscale_authkey` *(deferred: `vault_redis_password`)* | `ops-ansible-{check,apply} zone3_infra.yml` |
| `/zone4` | *(deferred: `vault_pgadmin_default_password`)* | `ops-ansible-{check,apply} zone4_apps.yml` |

### Machine Identity RBAC (Zero-Trust)

- **`homelab-ops-ro` (Universal Auth):** Granted **Viewer / Read-Only** role strictly on Project `haytham-homelab` (`prod`). Credentials stored exclusively in `/var/lib/haytham-ops/infisical-ops.env` (`0600 homelab-ops:homelab-ops`) on `haytham-ctl`.
- **`homelab-agent`:** Receives **ZERO** Infisical credentials and is blocked at the Linux kernel (`iptables --uid-owner`) from reaching `192.168.100.10`.
- **Human Admin:** Logs into Infisical Web UI from the Windows PC (with MFA) to create, rotate, and audit secrets.

### Backup & Catastrophic DR

- **Daily Track 1 (`restic`):** `ansible/roles/backup/templates/homelab-backup.sh.j2` dumps `infisical_postgres` (`pg_dumpall`) and archives `/opt/infisical/{docker-compose.yml,.env}` into the encrypted local `restic` repo, then mirrored to Windows via `scripts/pull-homelab-backups.bat`.
- **Weekly Track 1b (`vzdump`):** `CT 110` is included in `backup_vzdump_ctids`.
- **Mandatory Offline Emergency Sheet:** Store `ENCRYPTION_KEY` and `AUTH_SECRET` from `/opt/infisical/.env` (along with `vault_restic_password`) in Windows KeePassXC and a printed offline sheet. Without `ENCRYPTION_KEY`, restored database dumps cannot be decrypted.

## 5. Verification

```bash
# From Windows PC or homelab-ops on haytham-ctl:
curl -fsS http://192.168.100.10:8080/api/status

# From Proxmox host haytham:
pct config 110 | grep -E '^(hostname|net0|protection|tags):'
pct exec 110 -- docker ps
```

## 6. Gotchas

- **Never change `ENCRYPTION_KEY` after storing secrets:** Doing so renders existing encrypted database rows unreadable.
- **Do not add `CT 110` to `terraform/locals.tf`:** Importing `CT 110` into Terraform would expose it to `terraform destroy`.
- **Direct IP over DNS in CLI:** Always keep `INFISICAL_API_URL=http://192.168.100.10:8080/api` in `infisical-ops.env` so Terraform and Ansible continue working while Pi-hole (`130`) or NPM (`131`) are being rebuilt.
- **Explicit `db-migration` + Redis `noeviction`:** `infisical/infisical:v0.104.0-postgres` predates auto-migrations on startup (added Feb 2025), so Compose must run the one-shot `db-migration` (`npm run migration:latest`) service before `backend`, and Redis must use `--maxmemory-policy noeviction` for BullMQ queues.

## 7. FAQ

**Q: Why is Infisical in Zone 1 instead of Zone 2 or Zone 3?**
A: Zone 1 is completely outside Terraform state and `terraform@pve` ACLs, ensuring secrets remain available across every Zone 2–4 rebuild and eliminating circular bootstrap dependencies (`ADR-008`).

**Q: What if `haytham-ctl` is compromised?**
A: `homelab-ops-ro` is strictly read-only on Infisical and cannot delete or alter stored secrets. Revoke `homelab-ops-ro` in the Infisical UI, rotate any exposed credentials, revert `haytham-ctl` to VMware snapshot `clean-base`, and issue a fresh Machine Identity secret.
