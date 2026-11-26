# Haytham Homelab — Agent Instructions

Single-node Proxmox VE homelab on a Lenovo ThinkCentre M910q Tiny (**Intel i5 7th gen / HD 630 Quick Sync, 8 GB RAM → 16 GB planned, 1 TB SSD**). IaC uses **Terraform** (`bpg/proxmox`, LXC shells for Zones 2–4) + **Ansible** (host device passthrough, Docker Compose apps, automated backups) + **Zone 1 Immutable Infisical** (out-of-band secrets manager, `ADR-008`).

## Canonical Facts

- **Proxmox host:** `haytham` at `192.168.100.2` (`vmbr0`, gateway `192.168.100.1`, subnet `192.168.100.0/24`, storage `local` + `local-lvm`).
- **Control node:** Disposable VMware NAT Ubuntu 24.04 VM (`haytham-ctl`), shared Git repo at `/srv/haytham-homelab`. AI agent runs as unprivileged `homelab-agent` (no `sudo`, no `lxd`, kernel-blocked from `192.168.0.0/16`); human operator runs `homelab-ops` (`ADR-008`).
- **Domain:** `haytham.internal` (wildcard `*.haytham.internal → 192.168.100.31` NPM via Pi-hole `.30`, self-signed wildcard TLS).
- **Universal ID ↔ IP formula (`ADR-008`):** `Proxmox ID = 100 + last_octet` for **both VMs and LXCs** (10 slots per Security Zone; `.60–.99` open reserve blocked in UFW; `.100–.254` DHCP).
- **Active Phase 1 scope (`ADR-007` + `ADR-008`, Lean 8 GB):** 1 Immutable Zone 1 LXC + 7 Terraform-managed LXCs + host backups:
  - **Zone 0 (Host & VMs, `.1–.9`):** Proxmox `haytham` (`.2`) + host `restic` (daily 03:00) + `vzdump` (Sun 03:30) + Windows SSH pull (`scripts/pull-homelab-backups.{bat,sh}`). Deferred: `VM 103` HAOS (`.3`).
  - **Zone 1 (Immutable Core, `.10–.19`, OUTSIDE Terraform, `protection=1`, ZERO `terraform@pve` ACL):** `CT 110` **Infisical** (`.10`, direct API `http://192.168.100.10:8080`).
  - **Zone 2 (Protected Data P0, `.20–.29`, `pool: homelab-protected`, `protection=1`, NO destroy):** `CT 120` **Vaultwarden** (`.20`), `CT 121` **Immich** (`.21`, 500 GB thin-provisioned, Intel Quick Sync `/dev/dri`). Deferred: `122` Postgres, `123` Karakeep.
  - **Zone 3 (Core Infra / Network, `.30–.39`, `pool: homelab-ephemeral`):** `CT 130` **Pi-hole** (`.30`), `CT 131` **NPM** (`.31`), `CT 132` **Tailscale** (`.32`, `/dev/net/tun`). Deferred: `133` Redis.
  - **Zone 4 (Ephemeral Apps & Ops, `.40–.49`, `pool: homelab-ephemeral`):** `CT 140` **Homepage** (`.40`, root `haytham.internal`), `CT 141` **Uptime Kuma** (`.41`, 8 GB disk). Deferred: `142` pgAdmin.

## Hard Guardrails

1. **Never expose secrets:** Never print, echo, read, or commit `/var/lib/haytham-ops/*`, `infisical-ops.env`, `terraform.tfvars`, `*.tfstate*`, `ENCRYPTION_KEY`, `AUTH_SECRET`, private keys, or plaintext secrets. All secrets live in Zone 1 Infisical (`CT 110`) and are injected into RAM (`/dev/shm`) only by `homelab-ops`.
2. **Destroy = data loss:** Never run `terraform destroy` or wipe container disks without explicit user confirmation. Zone 1 (`CT 110`) and Zone 2 (`CT 120`, `CT 121`) are hypervisor-locked (`protection=1`) and require human Windows Break-Glass unlock (`scripts/proxmox/harden-pve-rbac.sh --unlock-dr <120-129>`) for intentional DR rebuilds.
3. **Terraform on `haytham`:** Always run Terraform through the audited wrappers (`ops-tf-plan` / `ops-tf-apply`), which inject `/terraform` secrets from Infisical, start an ephemeral `ssh-agent`, and enforce `-parallelism=1` to avoid single-node `local-lvm` lock timeouts.
4. **Device passthrough order:** Always run `ops-ansible-apply host_devices.yml` before `zone3_infra.yml` (`/dev/net/tun` on `CT 132`) and `zone2_protected.yml` (`/dev/dri/*` on `CT 121`). Non-root PVE API tokens get HTTP 403 on `device_passthrough`.
5. **KB-first fixes:** If you fix something via SSH or manually, port the fix into `kb/` + IaC (`terraform/` / `ansible/`) in the same session.
6. **Privilege Split & Human Gate (`ADR-008`):** When running as `homelab-agent`, invoke **only** the 3 allowlisted read-only wrappers via `sudo -u homelab-ops`:
   - `/usr/local/libexec/haytham-ops/ops-tf-plan`
   - `/usr/local/libexec/haytham-ops/ops-ansible-check <playbook>`
   - `/usr/local/libexec/haytham-ops/ops-health-check`
   Hand off all mutating or secret actions (`ops-tf-apply`, `ops-ansible-apply`, `ops-bundle`, Infisical UI secret rotation, and `harden-pve-rbac.sh`) to the human operator.

## Token-Saving KB Routing (Do NOT Bulk-Read `kb/`)

Use the matching `.agents/skills/homelab-*` skill first. When you need details from `kb/`, read **only** the single canonical file for the topic:

| Topic | Canonical File |
|---|---|
| IPs, IDs, Security Zones, DNS | `kb/reference/ip-ctid-matrix.md` |
| Zero-trust control node & Zone 1 Infisical | `kb/decisions/ADR-008-zero-trust-security-zones-and-infisical.md` |
| Control node hardening & <10m recovery | `kb/operations/control-node-hardening-and-recovery.md` |
| Zone 1 Infisical service spec (`CT 110`) | `kb/services/zone1-infisical-110.md` |
| 8 GB scope & deferrals | `kb/decisions/ADR-007-lean-8gb-phase1.md` |
| Security-Zone placement rules | `kb/architecture/tier-and-ctid-scheme.md` |
| Wildcard SSL cert | `kb/architecture/ssl-strategy.md` |
| Workstation DNS safe-mode swap | `kb/operations/dns-workstation-swap.md` |
| Build / wipe / DR rebuild | `kb/operations/build-from-scratch.md` (skill: `homelab-rebuild`) |
| Backups & restore drills | `kb/operations/backup-and-restore.md` (skill: `homelab-backup-restore`) |
| Secret rotation (Infisical UI) | `kb/operations/secret-rotation.md` (skill: `homelab-secret-rotation`) |
| LXC patching & reboot order | `kb/operations/update-and-reboot.md` (skill: `homelab-update-reboot`) |
| Single service config / NPM hosts | `kb/services/<zone>-<name>-<id>.md` (e.g. `zone3-npm-131.md`) |
| Troubleshooting (Docker/Pi-hole/HAOS) | `kb/troubleshooting/<topic>.md` |
| KB authoring rules | `kb/CONTRIBUTING.md` |
