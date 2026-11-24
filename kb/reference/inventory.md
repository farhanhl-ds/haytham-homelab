---
id: ref-inventory
title: Inventory (no secrets)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [reference, inventory]
retrievable: true
---

# Inventory (no secrets)

> What exists, where config lives, and which vault variable holds each secret. Values are never stored here.

## Proxmox Host

- Node `haytham` (`192.168.100.2`), bridge `vmbr0`, storage `local-lvm` (rootfs thin pool) + `local` (templates/ISO/weekly `vzdump`).
- Hardware: Lenovo ThinkCentre M910q Tiny — **Intel Core i5 7th gen (4c/4t, Intel HD 630 Quick Sync), 8 GB RAM (upgrade to 16 GB planned), 1 TB SSD**.
- Service account `terraform@pve!terraform` (privsep off). Roles: `PVEVMAdmin` on `/`, `PVESDNUser` on SDN zone, `PVEDatastoreUser` on `local` + `local-lvm`, `PVEAuditor` on `/` (for `query-url-metadata`).
- Template: `local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` (downloaded manually via GUI, referenced as static string — see ADR-002).
- Deferred VM: VM100 HAOS at `192.168.100.3` (DHCP reservation, MAC `BC:24:11:D7:75:C0`, deferred until 16 GB RAM per ADR-007). VM block `.4-.10` reserved.

## Terraform

- Modules: `modules/lxc` (generic, `nesting=true`, configurable `swap_mb`, ignores `user_account` and host-managed `device_passthrough`).
- Provider `bpg/proxmox ~> 0.111`. Local state (gitignored), `.terraform.lock.hcl` committed.
- Active Phase 1 containers (`enabled = true` in `locals.tf`): `pihole` (`110`), `npm` (`120`), `tailscale` (`130`), `vaultwarden` (`320`), `homepage` (`440`), `immich` (`610`, 500 GB), `uptime_kuma` (`910`).
- Deferred containers (`enabled = false` in `locals.tf`): `postgres` (`210`), `redis` (`220`), `pgadmin` (`230`), `karakeep` (`420`).

## Ansible

- Control node: WSL Ubuntu 24.04 checkout (`ansible/`). Collections in `requirements.yml` (`community.postgresql`, `community.docker`).
- `ansible.cfg`: `remote_user=root`, `vault_password_file=.vault_pass` (gitignored, never shared), `collections_path=./collections:~/.ansible/collections`.
- Playbook order (Phase 1): `host_devices.yml → tier10.yml → tier30.yml → tier40.yml → tier60.yml → tier90.yml → tier80.yml`.
- Vault pattern: single master password, per-value `encrypt_string`, one `group_vars/<group>.yml` per group.
- Vault variable index (names only):
  - `proxmox`: `vault_restic_password`
  - `tier10`: `vault_pihole_webpassword`, `vault_tailscale_authkey` (optional — leave `CHANGEME` for interactive login)
  - `tier20` *(deferred)*: `vault_postgres_superuser_password`, `vault_redis_password`, `vault_pgadmin_default_password`
  - `tier30`: `vault_vaultwarden_admin_token`
  - `tier40` *(Karakeep deferred)*: `vault_karakeep_nextauth_secret`, `vault_karakeep_meili_master_key`, `vault_karakeep_browser_token`
  - `tier60`: `vault_immich_db_password`

## Backups (Tier 80 — Host + Workstation Pull)

- Host timers (`tier80.yml` → `roles/backup`): daily encrypted `restic` repo (`/var/backups/homelab/restic`) + weekly lightweight LXC `vzdump`.
- Off-host pull scripts (`scripts/pull-homelab-backups.bat` on native Windows `cmd` using inbox `ssh.exe` + `tar.exe`, and `scripts/pull-homelab-backups.sh` on Linux/WSL using `rsync`): pull Track 1 `restic` repo from `haytham` (`.2`) and Track 2 Immich originals from CT `610` (`.61`) over SSH (zero cloud, zero Samba).

## SSL & DNS

- Wildcard `*.haytham.internal` self-signed cert (covers both `*.haytham.internal` and root `haytham.internal`). Key/crt/cnf in `~/homelab-cert/` (WSL) + Windows backup + Vaultwarden attachment. Imported to NPM as Custom Certificate.
- Wildcard `*.haytham.internal → 192.168.100.12` in Pi-hole (`/etc/dnsmasq.d/99-wildcard-haytham.conf`, `misc.etc_dnsmasq_d=true`).
- Tailscale Split DNS: `haytham.internal → 192.168.100.11` over subnet route `192.168.100.0/24`.
- Router DHCP pool `.100–.254`. Router DNS stays ISP default until Pi-hole cutover.
