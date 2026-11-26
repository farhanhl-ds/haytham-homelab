---
name: homelab-add-service
description: >-
  Use this skill when the user asks to add a new homelab service or revive a
  deferred service (Postgres 122, Karakeep 123, Redis 133, pgAdmin 142, VM 103 HAOS)
  across Terraform, Ansible, Infisical, NPM, UFW, and the KB.
---

# Add or Revive a Homelab Service (Security-Zone Scheme)

Reference files (read only what applies):
- `kb/reference/ip-ctid-matrix.md` — canonical Security Zone ↔ ID ↔ IP ↔ DNS table
- `kb/architecture/tier-and-ctid-scheme.md` — 1-question placement rule & zone ranges
- `kb/decisions/ADR-007-lean-8gb-phase1.md` — 8 GB RAM budget & deferred services
- `kb/decisions/ADR-008-zero-trust-security-zones-and-infisical.md` — zero-trust & UFW boundaries
- `kb/CONTRIBUTING.md` — KB authoring rules

## 1. Security-Zone Placement & Resource Check

1. Check RAM headroom on `haytham` (`ops-health-check` / human `free -h`). On 8 GB RAM, ensure the new service will not starve Immich (`CT 121`) or Infisical (`CT 110`); set LXC swap `>= 512 MB`.
2. Classify using the **1-question rule** (`ID = 100 + last_octet`):
   - **Bootstrap dependency for all other services** → **Zone 1 (`110–119`, `.10–.19`)** — out-of-band, NEVER in Terraform.
   - **Holds irreplaceable personal/DB/repo data?** → **Zone 2 (`120–129`, `.20–.29`)** — `homelab-protected`, `protection = true`, P0 Track 1/2 backup.
   - **Stateless network/ingress/cache?** → **Zone 3 (`130–139`, `.30–.39`)** — `homelab-ephemeral`.
   - **Stateless dashboard/tool/monitoring/CI runner?** → **Zone 4 (`140–149`, `.40–.49`)** — `homelab-ephemeral`.
   - **Disposable sandbox / AI experiment?** → **Zone 5 (`150–159`, `.50–.59`)** — `homelab-ephemeral`.
   - **Needs its own kernel/OS?** → **Zone 0 VM (`103–109`, `.3–.9`)** — manual `qm`, outside Terraform.
3. Size rootfs conservatively: **minimum 8 GB** for Docker/Node/Python apps.

## 2. Reviving a Deferred Service (`ADR-007`)

For `postgres (122)`, `karakeep (123)`, `redis (133)`, or `pgadmin (142)`:
1. Flip `enabled = true` in `terraform/locals.tf`.
2. Uncomment host entries in `ansible/inventory/hosts.yml` and play in `ansible/zone{2_protected,3_infra,4_apps}.yml`.
3. Ask the human operator to populate required secrets in **Zone 1 Infisical** (`http://192.168.100.10:8080`, paths `/zone2`, `/zone3`, or `/zone4`).
4. Validate via `ops-tf-plan` + `ops-ansible-check`; hand off `ops-tf-apply` + `ops-ansible-apply` to human `homelab-ops` (if Zone 2, temporarily unlock pool with `harden-pve-rbac.sh` then `--lock`).
5. Flip KB page frontmatter from `status: reserved` → `planned` → `verified` and move its row in `kb/reference/ip-ctid-matrix.md`.

*(For `VM 103 HAOS`, follow `kb/services/vm-haos-103.md` — manual `qm`, not Terraform.)*

## 3. Adding a Brand-New Service

1. **Terraform (`terraform/locals.tf`):** Add entry under `local.containers` with `zone`, `ctid = 100 + octet`, `ip`, `protected`, and `pool_id`.
2. **Firewall (`scripts/hardening/harden-control-node-ufw.sh`):** Add the new static IP (ports `22, 443`) to the UFW allowlist if not already listed.
3. **Host Devices (if needed):** Add `/dev/*` passthrough to `ansible/roles/pve_devices/defaults/main.yml` (never Terraform `device_passthrough`).
4. **Ansible:** Add host to `ansible/inventory/hosts.yml`, create `ansible/roles/<service>/`, add play to `ansible/zone{2_protected,3_infra,4_apps}.yml`, and add non-secret defaults to `ansible/group_vars/zone*.yml`. For Zone 2 stateful services, add backup staging to `ansible/roles/backup/templates/homelab-backup.sh.j2` and CTID to `backup_vzdump_ctids` in `ansible/group_vars/proxmox.yml`.
5. **Proxmox RBAC (`scripts/proxmox/harden-pve-rbac.sh`):** Add the CTID to `ZONE2_CTIDS` or `EPHEMERAL_CTIDS` so `--lock` enforces its pool and protection flag.
6. **KB Sync:** Update `kb/reference/ip-ctid-matrix.md`, create `kb/services/zone<N>-<name>-<ctid>.md`, and add NPM Proxy Host row to `kb/services/zone3-npm-131.md §4` if HTTP-exposed.

## 4. Verification

Run `ops-tf-plan`, `ops-ansible-check`, and after human apply run `ops-health-check`. Remind the user to add the NPM Proxy Host (`<service>.haytham.internal`, wildcard cert, Force SSL + HTTP/2) and an Uptime Kuma monitor.
