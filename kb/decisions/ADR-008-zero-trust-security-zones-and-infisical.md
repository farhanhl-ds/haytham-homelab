---
id: adr-008-zero-trust-security-zones-and-infisical
title: ADR-008 — Zero-Trust Disposable Control Node, Security-Zone Addressing, and Zone 1 Infisical
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [decision, security, zero-trust, infisical, zones, control-node, rbac]
retrievable: true
---

# ADR-008 — Zero-Trust Disposable Control Node, Security-Zone Addressing, and Zone 1 Infisical

## Context

Running an AI coding/ops agent on a Linux control node (`haytham-ctl` inside VMware on a Windows host PC) introduces three structural risks when the control node holds unconstrained credentials:

1. **Host spillover:** Shared folders, bidirectional clipboard, USB auto-connect, or unrestricted VMware networking could let a compromised VM probe or tamper with the Windows host PC or LAN router.
2. **Prompt-injection blast radius:** Plaintext `.vault_pass`, `terraform.tfvars` (with `PVEVMAdmin` on `/`), and passwordless `root@192.168.100.2` SSH keys sitting inside the agent's UID would allow a single prompt-injected command to exfiltrate all secrets or destroy irreplaceable data (Immich photos, Vaultwarden credentials, local `restic` backups, or HAOS VM).
3. **Functional tiering friction:** The legacy `CTID = IP * 10` functional tier scheme scattered stateful P0 services across non-contiguous IDs (`320`, `610`), left empty tiers (`50`, `70`, host-only `80`), excluded VMs from the ID formula, and placed Infisical inside Tier 30 (creating a circular bootstrap dependency during full rebuilds).

## Decision

Adopt a **4-layer zero-trust provisioning architecture** paired with a **Security-Zone Addressing Scheme (`ID = 100 + last_octet`)** and an **out-of-band Zone 1 Immutable Infisical (`CT 110` at `192.168.100.10`)**:

### 1. Security-Zone Addressing (`ID = 100 + last_octet`, 10 Slots / Zone)

Every Proxmox guest (both VMs and LXCs) obeys `ID = 100 + last_octet`, grouped by **trust boundary and lifecycle** rather than application category:

- **Zone 0 · Host & VMs (`.1`, `.2`, `.3–.9` → `VM 103–109`):** Router (`.1`), Proxmox `haytham` + Host Backups (`.2`), HAOS (`VM 103` at `.3`, deferred). Completely outside `terraform@pve` ACLs.
- **Zone 1 · Immutable Core (`.10–.19` → `CT 110–119`):** Out-of-band bootstrap services provisioned once after Proxmox install, **never** in Terraform state, `pool: homelab-immutable`, `protection=1`, **zero** `terraform@pve` ACL. Houses **Infisical (`CT 110` at `.10`)**, superseding `ADR-006`.
- **Zone 2 · Protected Data / Stateful P0 (`.20–.29` → `CT 120–129`):** Irreplaceable user data (`Vaultwarden 120`, `Immich 121`; deferred `Postgres 122`, `Karakeep 123`; future `Gitea`, `Neo4j`, `Paperless-ngx`, `Frigate`). Managed in `pool: homelab-protected` with `protection=1` and non-destructive Proxmox role `HomelabProtectedOps` (no `VM.Allocate`, no `VM.Config.Options`).
- **Zone 3 · Core Infra / Network (`.30–.39` → `CT 130–139`):** Freely rebuildable network plane (`Pi-hole 130`, `NPM 131`, `Tailscale 132`; deferred `Redis 133`) in `pool: homelab-ephemeral`.
- **Zone 4 · Ephemeral Apps & Ops (`.40–.49` → `CT 140–149`):** Stateless dashboards, tools, monitoring, and CI runners (`Homepage 140`, `Uptime Kuma 141`; deferred `pgAdmin 142`) in `pool: homelab-ephemeral`.
- **Zone 5 · Sandbox / Lab (`.50–.59` → `CT 150–159`):** Future disposable AI/dev experiments.
- **Open Reserve (`.60–.99` → `160–199`):** Unallocated and denied in UFW until expanded.

### 2. Layer 1 — Windows PC & VMware Hard Boundary + Egress Lockdown

- `haytham-ctl` runs headless on **VMware NAT (`VMnet8`)** with Shared Folders, Drag & Drop, Copy & Paste, and USB auto-connect completely disabled.
- Windows Defender Firewall (`scripts/hardening/harden-windows-firewall.ps1`) blocks all inbound connections initiated from the `VMnet8` subnet.
- Daily operator access uses **unidirectional Windows-initiated SSH** from Windows Terminal over `VMnet8`: `haytham-ctl` UFW allows inbound `22/tcp` **only** from `VMNET_HOST_IP/32` (`192.168.x.1`), while `sshd` (`/etc/ssh/sshd_config.d/01-haytham-hardening.conf`) restricts login to `AllowUsers farhan`, enforces `PasswordAuthentication no` unconditionally, disables all forwarding (`AllowAgentForwarding no`, `AllowTcpForwarding no`, `X11Forwarding no`, `PermitTunnel no`), and sets `dev.tty.legacy_tiocsti = 0`.
- `haytham-ctl` UFW (`scripts/hardening/harden-control-node-ufw.sh`) enforces default-deny egress, allowing only `.2` (`22, 8006`), `.10` (`8080`), `.30` (`22, 53`), active/deferred Zone 2–4 IPs (`22, 443`), and public internet HTTPS/DNS/NTP — explicitly denying all RFC1918 ranges (Router `.1`, Windows PC, `VMnet8` host `.1`, Reserve `.50–.99`, DHCP `.100–.254`) before broad internet rules.
- A persistent kernel UID rule (`haytham-agent-egress.service`) unconditionally blocks `homelab-agent` from contacting `192.168.0.0/16` directly (zero conntrack exceptions).

### 3. Layer 2 — Hypervisor Guardrails & Segregated SSH Keys

- `scripts/proxmox/harden-pve-rbac.sh` strips global `PVEVMAdmin` from `/` on `terraform@pve`, scoping `PVEVMAdmin` strictly to `/pool/homelab-ephemeral`, `HomelabProtectedOps` to `/pool/homelab-protected`, and zero ACL on Zone 0 VMs and Zone 1 (`CT 110`).
- Three segregated SSH keypairs:
  1. **Windows Break-Glass + Backup-Pull key** (`%USERPROFILE%\.ssh\id_ed25519`): accesses Proxmox `.2` and Zone 1 `CT 110` (`scripts/pull-homelab-backups.bat`); **never** copied to or used against `haytham-ctl`.
  2. **Windows Control-Node Terminal key** (`%USERPROFILE%\.ssh\id_ed25519_haytham_ctl`): used exclusively from Windows Terminal to SSH/SCP into `haytham-ctl` (`farhan`) over `VMnet8`.
  3. **Revocable Control-Node key** (`/var/lib/haytham-ops/.ssh/id_ed25519_control`): generated on `haytham-ctl`, excluded from `CT 110`, and automatically rotated on every `ops-bundle unpack`.

### 4. Layer 3 — OS Privilege Split & RAM-Only Runtime Secrets

- Shared Git workspace lives at `/srv/haytham-homelab` (`homelab-ops:homelab-repo`, `2775`).
- The AI agent runs as unprivileged `homelab-agent` (no `sudo`, no `lxd`, no secret access, no direct LAN). It may invoke **only** 3 immutable root-owned read-only wrappers (`/usr/local/libexec/haytham-ops/ops-tf-plan`, `ops-ansible-check`, `ops-health-check`) via scoped `sudoers`.
- Human-only mutations (`ops-tf-apply`, `ops-ansible-apply`, `ops-bundle`) run exclusively as `homelab-ops` on an interactive TTY.
- Zero `.vault_pass` and zero static secret values live on `haytham-ctl` disk. `homelab-ops` holds only a **read-only** Infisical Machine Identity (`homelab-ops-ro`) in `/var/lib/haytham-ops/infisical-ops.env` (`0600`) and fetches secrets into RAM (`/dev/shm` shredded on `EXIT` trap or ephemeral `TF_VAR_*` env vars). Secret rotation occurs exclusively in the Infisical Web UI with MFA and audit logging.

### 5. Layer 4 — Disposable Control Node Recovery (< 10 Minutes)

- `scripts/control-node/bootstrap-control-node.sh` reprovisions a clean Ubuntu 24.04 VMware VM before capturing a VMware Golden Snapshot (`clean-base`).
- `scripts/control-node/ops-bundle.sh` packs non-key state (`terraform.tfstate`, non-secret `terraform.tfvars`, `infisical-ops.env`, `homelab-cert/`, `windows_breakglass.pub`) into an `age`-encrypted archive stored on Windows PC + offline USB, deliberately omitting `id_ed25519_control` so every rebuild rotates the control-node SSH key.

## Alternatives Considered

- **Ansible Vault on `haytham-ctl` without Infisical:** Eliminates ~600–900 MB RAM overhead on the 8 GB host, but keeps a static `.vault_pass` on disk and requires manual `!vault` YAML rotation without centralized audit logs.
- **Infisical Cloud (Free Tier):** Zero local RAM and no DR circularity, but violates the zero-cloud privacy principle (`ADR-007`).
- **Keep legacy `CTID = IP * 10` tiers:** Avoids pre-production renumbering, but leaves stateful P0 assets scattered across non-contiguous pools and breaks the formula for VMs and Zone 1.

## Consequences

- **8 GB RAM budget impact (`ADR-007`):** Lean-tuned `CT 110` Infisical adds ~600–900 MB actual RSS idle (`1536 MB` cap + `1024 MB` swap), bringing steady-state host usage to ~3.8–4.4 GB and leaving ~3.5–4.0 GB headroom (+ swap cushion) for Immich ML bursts until the 16 GB upgrade.
- **Catastrophic SSD-loss DR dependency:** `CT 110`'s Postgres dump and `/opt/infisical/.env` are captured daily by Track 1 `restic` and weekly by `vzdump`; operators must additionally store `ENCRYPTION_KEY`, `AUTH_SECRET`, and `vault_restic_password` on an offline emergency sheet.
- **Human gate friction:** Live applies, secret rotations, and Zone 2 DR unlocks (`harden-pve-rbac.sh --unlock-dr <120-129>`) require explicit human action — an intentional security property, not a bug.

## Status

Accepted (supersedes `ADR-006`).
