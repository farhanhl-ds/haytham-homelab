---
id: ops-build-from-scratch
title: Runbook — Build Homelab from Scratch
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, build, terraform, ansible]
retrievable: true
---

# Runbook — Build Homelab from Scratch

> Procedural only. For rationale see `architecture/` and `decisions/`. Canonical per-service config lives in `services/` — if this runbook diverges, `services/` wins.
>
> **Read §8 Destroy = data loss before step 1 on any loaded system (especially once iPhone photos live in Immich CT 610).**

## 1. When to use / not use

- Use: initial build, full validation, disaster recovery drill.
- Do not use `-target` for full builds (only for exceptional partial work). Plain `terraform apply` / `terraform destroy` is the supported path.
- Active Phase 1 scope (8 GB RAM lean stack — see `decisions/ADR-007-lean-8gb-phase1.md`): **7 LXCs** (`110, 120, 130, 320, 440, 610, 910`) + host-managed backups (`tier80.yml`). Tier 20 (`210/220/230`), Karakeep (`420`), and HAOS (`VM 100`) are deferred until the 16 GB RAM upgrade.

## 2. Prerequisites

- Proxmox host `haytham` at `192.168.100.2` (Intel i5 7th gen, 8 GB RAM, 1 TB SSD), `vmbr0`, `local` + `local-lvm`. Template `local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst` downloaded via GUI.
- Service account `terraform@pve!terraform` with the four role grants (see `architecture/terraform-strategy.md`).
- SSH key pair. Public key path passed to Terraform; private key in both Windows and WSL (`chmod 600` in WSL) with key-based `root@192.168.100.2` access working.
- WSL tooling: `ansible openssh-client bind9-dnsutils rsync restic`, plus `ansible-galaxy collection install -r requirements.yml`.
- Filled `terraform.tfvars` (`pve_endpoint=https://192.168.100.2:8006/`, `pve_api_token`, absolute `ssh_public_key_path`, `ct_root_password`).
- Secrets: `.vault_pass` created, every `CHANGEME` in active `group_vars/{proxmox,tier10,tier30,tier60}.yml` replaced via `encrypt_string` (`vault_tailscale_authkey` may stay `CHANGEME` for interactive login).
- SSL cert generated (`~/homelab-cert/` + Windows backup) — needed for the NPM manual step.
- Router: DHCP pool `.100-.254`. Router DNS stays ISP default until §6 passes.

## 3. Step 0 — Workstation DNS (before touching Pi-hole)

Destroying or absent Pi-hole while the workstation resolves only via Pi-hole = circular failure. Set safe mode first:

```powershell
# Safe-to-build (public first; internal names will NOT resolve yet)
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("1.1.1.1", "192.168.100.11")
# Normal use (Pi-hole first) — restore after §6 verifies green
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.100.11", "1.1.1.1")
ipconfig /flushdns
```

Requires Administrator. Detail: `dns-workstation-swap.md`.

## 4. Step 1 — Provision LXC with Terraform

```bash
cd terraform
terraform init
terraform validate
terraform plan
# Expect: 7 LXC (110, 120, 130, 320, 440, 610, 910), 0 errors
terraform apply
```

`ssh_public_key_path` must be absolute — Terraform `file()` does not expand `~`.

Known gotcha (single-node `local-lvm`): parallel LXC allocations can hit `can't lock file .../pve-storage-local-lvm - got timeout`. Retry serially: `terraform apply -parallelism=1`.

## 5. Step 2 — SSH known-hosts + Host Device Passthrough + Ansible

From WSL:

```bash
for ip in 192.168.100.11 192.168.100.12 192.168.100.13 192.168.100.32 192.168.100.44 192.168.100.61 192.168.100.91; do
  ssh-keygen -f ~/.ssh/known_hosts -R "$ip"
done
```

From `ansible/`:

```bash
ansible-galaxy collection install -r requirements.yml
ansible-playbook host_devices.yml   # attaches /dev/net/tun (CT 130) & /dev/dri/* (CT 610)
ansible-playbook tier10.yml         # Pi-hole, NPM, Tailscale
ansible-playbook tier30.yml         # Vaultwarden
ansible-playbook tier40.yml         # Homepage
ansible-playbook tier60.yml         # Immich (4-container bundle)
ansible-playbook tier90.yml         # Uptime Kuma
ansible-playbook tier80.yml         # Proxmox host daily restic + weekly vzdump timers
# Expect: failed=0 on all hosts
```

Vaultwarden first-run flow: set `vaultwarden_signups_allowed: "true"` → create master account → set `"false"` → re-run `tier30.yml`.

## 6. Step 3 — Verify end-to-end

```bash
dig haytham.internal @192.168.100.11 +short
dig immich.haytham.internal @192.168.100.11 +short
# Expect both: 192.168.100.12

ssh root@192.168.100.12 "docker ps"      # npm
ssh root@192.168.100.13 "tailscale status"
ssh root@192.168.100.32 "docker ps"      # vaultwarden
ssh root@192.168.100.44 "docker ps"      # homepage
ssh root@192.168.100.61 "ls -la /dev/dri && docker ps"  # immich (4 containers healthy)
ssh root@192.168.100.91 "docker ps"      # uptime_kuma
ssh root@192.168.100.2  "systemctl list-timers 'homelab-*'"
```

Browser (DNS → Pi-hole): `https://haytham.internal`, `https://{pihole,npm,vaultwarden,immich,uptime,pve}.haytham.internal`.

## 7. Step 4 — Manual gaps (redo per rebuild, cannot be IaC'd)

- **NPM (.12):** create admin account → import `haytham-internal` cert → add 7 Proxy Hosts (`services/network-npm-120.md §4`) → Pi-hole `/` rewrite → Websockets ON for Vaultwarden, Immich, Uptime Kuma, Proxmox → Immich upload size buffer.
- **Tailscale (.13):** if no auth key was vaulted, run `tailscale up --advertise-routes=192.168.100.0/24 --accept-dns=false`; approve route in Tailscale Admin Console + configure Split DNS `haytham.internal → 192.168.100.11`.
- **Vaultwarden (.32):** create master account, then `signups_allowed=false` + re-run `tier30.yml`. Store wildcard cert + `vault_restic_password` as attachments.
- **Immich (.61):** create admin account → **Administration → Settings → Video Transcoding → Quick Sync** → pair Immich iOS app for photo migration.
- **Uptime Kuma (.91):** create admin account → add internal HTTPS/DNS/TCP monitors (ignore self-signed TLS per monitor).
- **Backup verification:** run `systemctl start homelab-backup.service` on `haytham`, run `scripts/pull-homelab-backups.sh` from WSL, and schedule the Windows Task Scheduler pull (`operations/backup-and-restore.md`).
- **Workstation:** restore Normal DNS order (§3).

## 8. Destroy = data loss

All container disks (including up to 500 GB of Immich photos in CT `610`) live on `local-lvm` and are wiped by `terraform destroy`. Before any destroy on a loaded host, confirm Track 1 (`restic check`) and Track 2 (`pull-homelab-backups.sh`) are up to date on your PC or external drive (`operations/backup-and-restore.md`).
