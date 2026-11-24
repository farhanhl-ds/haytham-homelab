# Haytham Homelab — Agent Instructions

Single-node Proxmox VE homelab on a Lenovo ThinkCentre M910q Tiny (**Intel i5 7th gen / HD 630 Quick Sync, 8 GB RAM → 16 GB planned, 1 TB SSD**). IaC uses **Terraform** (`bpg/proxmox`, LXC shells only) + **Ansible** (host device passthrough, Docker Compose apps, automated backups).

## Canonical Facts

- **Proxmox host:** `haytham` at `192.168.100.2` (`vmbr0`, gateway `192.168.100.1`, subnet `192.168.100.0/24`, storage `local` + `local-lvm`).
- **Control nodes:** Linux `devbox` (`192.168.100.150`, key `~/.ssh/id_ed25519`) or Windows WSL.
- **Domain:** `haytham.internal` (wildcard `*.haytham.internal → 192.168.100.12` NPM via Pi-hole `.11`, self-signed wildcard TLS).
- **CTID ↔ IP formula:** `last_octet = CTID / 10` (static `.2–.99`, DHCP `.100–.254`).
- **Active Phase 1 scope (`ADR-007`, Lean 8 GB):** 7 LXCs + host backups:
  - Tier 10: `110` Pi-hole (`.11`), `120` NPM (`.12`), `130` Tailscale (`.13`)
  - Tier 30: `320` Vaultwarden (`.32`)
  - Tier 40: `440` Homepage (`.44`, root `haytham.internal`)
  - Tier 60: `610` Immich (`.61`, 500 GB thin-provisioned, Intel Quick Sync `/dev/dri`)
  - Tier 80: Proxmox host `restic` (daily 03:00) + `vzdump` (Sun 03:30) + off-host SSH pull (`scripts/pull-homelab-backups.sh`)
  - Tier 90: `910` Uptime Kuma (`.91`, 8 GB disk)
- **Deferred (preserved in-repo, `enabled = false`):** Tier 20 (`210` Postgres, `220` Redis, `230` pgAdmin), `420` Karakeep, `VM 100` HAOS (stopped).

## Hard Guardrails

1. **Never expose secrets:** Never print, echo, or commit `.vault_pass`, `terraform.tfvars`, `service-account.txt`, `*.tfstate*`, or plaintext vault values. Let the user generate/encrypt secrets in their own terminal when plaintext must stay private.
2. **Destroy = data loss:** Never run `terraform destroy` or wipe container disks without explicit user confirmation (especially once photos/credentials live in CT `610` / CT `320`).
3. **Terraform on `haytham`:** Always load `ssh-agent` (`eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`) before Terraform (`bpg/proxmox` SSH block) and use `-parallelism=1` to avoid single-node `local-lvm` lock timeouts.
4. **Device passthrough order:** Always run `ansible-playbook host_devices.yml` before `tier10.yml` (`/dev/net/tun` on CT `130`) and `tier60.yml` (`/dev/dri/*` on CT `610`). Non-root PVE API tokens get HTTP 403 on `device_passthrough`.
5. **KB-first fixes:** If you fix something via SSH or manually, port the fix into `kb/` + IaC (`terraform/` / `ansible/`) in the same session.

## Token-Saving KB Routing (Do NOT Bulk-Read `kb/`)

Use the matching `.agents/skills/homelab-*` skill first. When you need details from `kb/`, read **only** the single canonical file for the topic:

| Topic | Canonical File |
|---|---|
| IPs, CTIDs, DNS names | `kb/reference/ip-ctid-matrix.md` |
| 8 GB scope & deferrals | `kb/decisions/ADR-007-lean-8gb-phase1.md` |
| Tier numbering scheme | `kb/architecture/tier-and-ctid-scheme.md` |
| Wildcard SSL cert | `kb/architecture/ssl-strategy.md` |
| Workstation DNS safe-mode swap | `kb/operations/dns-workstation-swap.md` |
| Build / wipe / DR rebuild | `kb/operations/build-from-scratch.md` (skill: `homelab-rebuild`) |
| Backups & restore drills | `kb/operations/backup-and-restore.md` (skill: `homelab-backup-restore`) |
| Secret rotation / vault | `kb/operations/secret-rotation.md` (skill: `homelab-secret-rotation`) |
| LXC patching & reboot order | `kb/operations/update-and-reboot.md` (skill: `homelab-update-reboot`) |
| Single service config / NPM hosts | `kb/services/<tier>-<name>-<ctid>.md` (e.g. `network-npm-120.md`) |
| Troubleshooting (Docker/Pi-hole/HAOS) | `kb/troubleshooting/<topic>.md` |
| KB authoring rules | `kb/CONTRIBUTING.md` |
