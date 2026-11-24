---
name: homelab-add-service
description: >-
  Use this skill when the user asks to add a new homelab service or revive a
  deferred service (Tier 20 Postgres/Redis/pgAdmin, Karakeep 420, VM 100 HAOS)
  across Terraform, Ansible, NPM, and the KB.
---

# Add or Revive a Homelab Service

Reference files (read only what applies):
- `kb/reference/ip-ctid-matrix.md` — canonical CTID ↔ IP ↔ DNS table
- `kb/architecture/tier-and-ctid-scheme.md` — tier ranges & multi-container exception rules
- `kb/decisions/ADR-007-lean-8gb-phase1.md` — 8 GB RAM budget & deferred services
- `kb/CONTRIBUTING.md` — KB authoring rules

## 1. Architecture & Resource Check

1. Check current RAM headroom on `haytham` (`ssh root@192.168.100.2 "free -h"`). If still on 8 GB RAM, verify the new workload will not starve Immich (`CT 610`) or trigger OOMs (enable LXC swap `>= 512 MB`).
2. Follow **1 service = 1 LXC** (exception: upstream multi-container bundles like Immich/Karakeep stay self-contained in one LXC).
3. Pick the next free multiple-of-10 CTID in the matching tier (`10` Network, `20` Data, `30` Identity, `40` App, `50` AI/ML, `60` Media, `70` CI/CD, `80` Backup, `90` Observability). Derive static IP via `last_octet = CTID / 10`.
4. Size rootfs conservatively for Docker images: **minimum 8 GB** for Node/Python/heavy Docker images (4 GB is only safe for tiny native/Alpine services).

## 2. Reviving a Deferred Service (`ADR-007`)

For `postgres (210)`, `redis (220)`, `pgadmin (230)`, or `karakeep (420)`:
1. Flip `enabled = true` in `terraform/locals.tf`.
2. Uncomment host entries in `ansible/inventory/hosts.yml` (and play in `ansible/tier40.yml` for Karakeep).
3. Encrypt any `CHANGEME` secrets in `ansible/group_vars/tier{20,40}.yml`.
4. Provision with `terraform apply -parallelism=1` (with `ssh-agent`), clear `known_hosts`, and run the tier playbook.
5. Flip the service's KB page frontmatter from `status: reserved` → `planned` → `verified` (once verified) and move its row in `kb/reference/ip-ctid-matrix.md`.

*(For `VM 100 HAOS`, follow `kb/services/vm-haos-100.md` — manual `qm`, not Terraform.)*

## 3. Adding a Brand-New Service

Touch these layers in order:
1. **Terraform (`terraform/locals.tf` & `containers.tf`):** Add container entry under `local.containers` (ensure its tier module exists in `containers.tf`).
2. **Host Devices (if needed):** If the service needs `/dev/*` passthrough, add it to `ansible/roles/pve_devices/defaults/main.yml` (never Terraform `device_passthrough`).
3. **Ansible:**
   - Add host to `ansible/inventory/hosts.yml`.
   - Create `ansible/roles/<service>/` (`meta/main.yml` depending on `docker` if containerized, `defaults/`, `tasks/`, `templates/`, `handlers/`).
   - Add play to `ansible/tier<N>.yml` and non-secret/vault vars to `ansible/group_vars/tier<N>.yml`.
   - If the service holds critical state, add its staging step to `ansible/roles/backup/templates/homelab-backup.sh.j2` and its CTID to `backup_vzdump_ctids` in `ansible/group_vars/proxmox.yml`.
4. **Provision & Configure:** Run `terraform apply -parallelism=1` (with `ssh-agent`) → `host_devices.yml` (if applicable) → `ansible-playbook tier<N>.yml` (and `tier80.yml` if backup config changed).
5. **KB Sync (`kb/CONTRIBUTING.md`):**
   - Add row to `kb/reference/ip-ctid-matrix.md`.
   - Create `kb/services/<tier>-<name>-<ctid>.md` using `kb/templates/service-page-template.md`.
   - Add Proxy Host row to `kb/services/network-npm-120.md §4` if HTTP-exposed.

## 4. Verification

- Container running & healthy (`pct status <ctid>`, `docker ps` / `systemctl status`).
- Disk headroom comfortable (`df -h /`).
- Remind user to add the NPM Proxy Host (`<service>.haytham.internal`, wildcard cert, Force SSL + HTTP/2; no Pi-hole DNS edit needed) and an Uptime Kuma monitor.
