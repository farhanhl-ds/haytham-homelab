---
id: arch-terraform-strategy
title: Terraform Strategy
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, terraform, proxmox, iac, rbac]
retrievable: true
---

# Terraform Strategy

## 1. Provider and State

- Provider `bpg/proxmox ~> 0.111` (not `telmate/proxmox` — unmaintained).
- Local state lives outside the agent-readable Git workspace at `/var/lib/haytham-ops/terraform.tfstate` (`0600 homelab-ops:homelab-ops`, `ADR-008`) and is backed up off-host via `ops-bundle pack`.
- `.terraform.lock.hcl` is committed; `*.tfstate*`, `.terraform/`, and `terraform.tfvars` remain gitignored.
- Storage `local-lvm` (rootfs), bridge `vmbr0`, static IPs in Terraform (`ID = 100 + last_octet`), Ubuntu 24.04 LTS template, endpoint `https://192.168.100.2:8006/`.
- Always pass `-parallelism=1` (enforced automatically by `ops-tf-apply`) to avoid single-node `local-lvm` lock timeouts.

## 2. Scoped Proxmox Service Account (`ADR-008`)

User `terraform@pve`, token `terraform@pve!terraform` (`--privsep 0`), managed by `scripts/proxmox/harden-pve-rbac.sh`:

- **Baseline:** `PVEAuditor` on `/` (`Sys.Audit` for metadata queries), `PVESDNUser` on `/sdn/zones/localnetwork`, `PVEDatastoreUser` on `/storage/local` and `/storage/local-lvm`.
- **Zone 0 (VM `103` HAOS) & Zone 1 (`CT 110` Infisical, `/pool/homelab-immutable`):** **ZERO ACL** — `terraform@pve` receives HTTP 403.
- **Zone 2 (`/pool/homelab-protected` — `CT 120`, `CT 121`):** Custom role `HomelabProtectedOps` (`VM.Audit,VM.PowerMgmt,VM.Config.CPU,VM.Config.Memory,VM.Config.Disk,VM.Config.Network,VM.Console`) + `protection=1` — **cannot destroy or disable protection**. Intentional DR rebuilds use `harden-pve-rbac.sh --unlock-dr <120-129>` from Windows Break-Glass SSH and re-lock immediately.
- **Zones 3–5 (`/pool/homelab-ephemeral` — `CT 130–159`):** `PVEVMAdmin` (freely create/rebuild).

Provider SSH block (`ssh { agent = true, username = "root" }`) uses the ephemeral `ssh-agent` started by `/usr/local/libexec/haytham-ops/ops-tf-{plan,apply}` with the revocable `/var/lib/haytham-ops/.ssh/id_ed25519_control` key.

## 3. Secrets & Dual SSH Keys

- `pve_api_token` and `ct_root_password` are **never** written to `terraform.tfvars`; `ops-tf-{plan,apply}` injects them into memory as `TF_VAR_*` from Zone 1 Infisical (`/terraform`).
- `/var/lib/haytham-ops/terraform.tfvars` contains only non-secret values (`pve_endpoint`, `ssh_public_key_path`, `breakglass_ssh_public_key_path`).
- Baking **both** `id_ed25519_control.pub` and `windows_breakglass.pub` into every LXC ensures Windows off-host backup pulls and Break-Glass SSH survive control-node key rotation.

## 4. Project Layout

```text
terraform/
  versions.tf, providers.tf (insecure=true, ssh agent root)
  variables.tf (pve_endpoint, pve_api_token, ssh_public_key_path, breakglass_ssh_public_key_path, ct_root_password)
  locals.tf (domain, target_node=haytham, network{}, containers{} grouped by zone 2/3/4)
  templates.tf (static string only — ADR-002)
  containers.tf (module zone2_protected, zone3_infra, zone4_apps)
  modules/lxc/{versions.tf, main.tf, variables.tf, outputs.tf}
```

`modules/lxc/main.tf` sets `nesting = true`, `pool_id = var.pool_id`, `protection = var.protection`, and ignores `initialization[0].user_account` + `device_passthrough` (host-managed via `ansible/host_devices.yml`).

## 5. Template Lifecycle (ADR-002)

Templates are downloaded manually via GUI (`Datacenter → haytham → local → CT Templates`) and referenced as a static string in `templates.tf`. Do not use `proxmox_virtual_environment_download_file`.
