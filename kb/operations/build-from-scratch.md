---
id: ops-build-from-scratch
title: Runbook — Build Homelab from Scratch
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, build, terraform, ansible, zones]
retrievable: true
---

# Runbook — Build Homelab from Scratch

> Procedural only. For zero-trust control node hardening and Zone 1 Infisical bootstrap, complete `control-node-hardening-and-recovery.md` first. Canonical per-service specs live in `services/`.
>
> **Read §8 Destroy = data loss before touching any loaded host (especially once iPhone photos live in Zone 2 Immich CT 121 or passwords in Vaultwarden CT 120).**

## 1. When to Use / Not Use

- Use: initial Phase 1 build, ephemeral Zone 3–4 rebuild, or full disaster recovery drill.
- Do not use `-target` for full builds. Use audited wrappers (`ops-tf-plan` / `ops-tf-apply`).
- Active Phase 1 scope (`ADR-007` + `ADR-008`, Lean 8 GB):
  - **Zone 1 (Immutable, outside Terraform):** `CT 110` Infisical (`.10`) — already bootstrapped once via `scripts/zone1/bootstrap-infisical.sh` and **never** destroyed by Terraform.
  - **Zone 2 (Protected Data, `protection=1`):** `CT 120` Vaultwarden (`.20`), `CT 121` Immich (`.21`).
  - **Zone 3 (Core Infra):** `CT 130` Pi-hole (`.30`), `CT 131` NPM (`.31`), `CT 132` Tailscale (`.32`).
  - **Zone 4 (Ephemeral Apps & Ops):** `CT 140` Homepage (`.40`), `CT 141` Uptime Kuma (`.41`).
  - **Zone 0 Host Backups:** `ansible/host_backups.yml` on `haytham` (`.2`).

## 2. Prerequisites

- Proxmox host `haytham` (`192.168.100.2`), `vmbr0`, `local` + `local-lvm`, Ubuntu 24.04 template downloaded via GUI (`ADR-002`).
- **Zone 1 `CT 110` Infisical (`192.168.100.10:8080`)** running with secrets populated under `/terraform`, `/proxmox`, `/zone2`, `/zone3` (`services/zone1-infisical-110.md`).
- Hardened `devbox` control node (`bootstrap-control-node.sh`), `/var/lib/haytham-ops/` populated (`infisical-ops.env`, non-secret `terraform.tfvars`, `id_ed25519_control`, `windows_breakglass.pub`), and `harden-pve-rbac.sh --init` completed on `haytham`.
- Wildcard SSL cert archived in `/var/lib/haytham-ops/homelab-cert/` + Windows backup (`architecture/ssl-strategy.md`).
- Router DHCP pool `.100–.254`.

## 3. Step 0 — Workstation DNS Safe Mode (Before Touching Pi-hole CT 130)

```powershell
# Safe-to-build (public first; internal names will NOT resolve yet)
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("1.1.1.1", "192.168.100.30")
# Normal use (Pi-hole first) — restore after §6 verifies green
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.100.30", "1.1.1.1")
ipconfig /flushdns
```

Detail: `dns-workstation-swap.md`.

## 4. Step 1 — Provision Zones 2–4 LXCs with Terraform

1. Review plan (callable by `homelab-agent` or `homelab-ops`):
   ```bash
   sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan
   # Expect: 7 LXCs (120, 121, 130, 131, 132, 140, 141), 0 errors
   ```
2. Apply as human operator (`sudo -iu homelab-ops`):
   ```bash
   ops-tf-apply   # Enforces -parallelism=1, pulls /terraform secrets from Zone 1 Infisical into RAM
   ```

## 5. Step 2 — SSH Known-Hosts, Device Passthrough & Ansible Zone Rollout

As human operator (`sudo -iu homelab-ops`):

```bash
for ip in 192.168.100.20 192.168.100.21 192.168.100.30 192.168.100.31 192.168.100.32 192.168.100.40 192.168.100.41; do
  ssh-keygen -f ~/.ssh/known_hosts -R "$ip" 2>/dev/null || true
done

ops-ansible-apply host_devices.yml    # attaches /dev/net/tun (CT 132) & /dev/dri/* (CT 121)
ops-ansible-apply zone3_infra.yml     # Pi-hole (.30), NPM (.31), Tailscale (.32)
ops-ansible-apply zone2_protected.yml # Vaultwarden (.20), Immich (.21)
ops-ansible-apply zone4_apps.yml      # Homepage (.40), Uptime Kuma (.41)
ops-ansible-apply host_backups.yml    # Proxmox host daily restic (incl. CT 110) + weekly vzdump
ops-bundle pack                       # Refresh encrypted off-host control bundle
```

Immediately lock Proxmox RBAC from Windows Break-Glass SSH on `haytham` (`192.168.100.2`):
```bash
./harden-pve-rbac.sh --lock
./harden-pve-rbac.sh --status
```

## 6. Step 3 — Verify End-to-End

```bash
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
```

Expect: Zone 1 Infisical `.10` healthy, `dig @192.168.100.30` returns `192.168.100.31`, Docker healthy on `.20`, `.21` (+ `/dev/dri`), `.31`, `.40`, `.41`, Tailscale active on `.32`, and `homelab-*` timers active on `.2`.

Browser (DNS → Pi-hole `.30`): `https://haytham.internal`, `https://{infisical,pihole,npm,vaultwarden,immich,uptime,pve}.haytham.internal`.

## 7. Step 4 — Manual Gaps (Redo Per Rebuild, Cannot Be IaC'd)

- **NPM (`CT 131` @ `.31`):** Create admin account → import `haytham-internal` wildcard cert → add 8 Proxy Hosts (`services/zone3-npm-131.md §4`, including `infisical.haytham.internal → 192.168.100.10:8080`) → Pi-hole `/` rewrite → Websockets ON for Infisical, Vaultwarden, Immich, Uptime Kuma, Proxmox → Immich upload buffer.
- **Tailscale (`CT 132` @ `.32`):** If `vault_tailscale_authkey` is `CHANGEME`, run `tailscale up --advertise-routes=192.168.100.0/24 --accept-dns=false`; approve route in Tailscale Admin Console + configure Split DNS `haytham.internal → 192.168.100.30`.
- **Vaultwarden (`CT 120` @ `.20`):** Temporarily enable signups → create master account → disable signups + re-run `ops-ansible-apply zone2_protected.yml`.
- **Immich (`CT 121` @ `.21`):** Create admin account → **Administration → Settings → Video Transcoding → Quick Sync** → pair iOS app.
- **Uptime Kuma (`CT 141` @ `.41`):** Create admin account → add internal HTTPS/DNS/TCP monitors.
- **Off-Host Backup Pull:** Run `scripts\pull-homelab-backups.bat` from Windows `cmd`.
- **Workstation:** Restore Normal DNS order (§3).

## 8. Destroy = Data Loss

All container disks (including up to 500 GB of Immich photos in `CT 121`) live on `local-lvm`. Under `harden-pve-rbac.sh --lock`, Proxmox hypervisor refuses destroy calls against Zone 1 (`CT 110`) and Zone 2 (`CT 120`, `CT 121`). Before any intentional Zone 2 unlock (`--unlock-dr <ctid>`), verify Track 1 (`restic check`) and Track 2 (`pull-homelab-backups.bat`) are up to date on Windows/external USB (`backup-and-restore.md`).
