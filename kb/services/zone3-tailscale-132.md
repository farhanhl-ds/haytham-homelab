---
id: svc-tailscale-130
title: Tailscale — Tier 10 Remote Access (CTID 132)
tier: "10"
ctid: "132"
ip: 192.168.100.32
status: planned
last_verified: unreleased
tags: [tailscale, vpn, subnet-router, tier10, network]
retrievable: true
---

# Tailscale — Tier 10 Remote Access (CTID 132)

## 1. Purpose

WireGuard-based mesh VPN subnet router advertising `192.168.100.0/24`. Enables secure remote access from phones/laptops to Vaultwarden, Immich, Pi-hole DNS, and all `*.haytham.internal` services without opening router ports.

## 2. Spec

| Field | Value |
|---|---|
| CTID / IP | 130 / `192.168.100.32` (see `../reference/ip-ctid-matrix.md`) |
| Resources | 1 core / 256 MB RAM / 256 MB swap / 2 GB disk |
| Base | Ubuntu 24.04 LXC, native `tailscale` package (no Docker) |
| Device passthrough | `/dev/net/tun` (`mode=0666`) configured on host via `ansible/host_devices.yml` |

## 3. Provisioning

- Terraform: `module.tier10["tailscale"]` (`nesting=true`).
- Host device passthrough: `ansible-playbook host_devices.yml` (`roles/pve_devices` runs `pct set 132 -dev0 /dev/net/tun,mode=0666`).
- Ansible: `tier10.yml` → `roles/tailscale` (enables `net.ipv4.ip_forward=1`, installs official Tailscale apt package, starts `tailscaled`).

## 4. Configuration

- **Auth:** Optional encrypted `vault_tailscale_authkey` in `group_vars/tier10.yml` for unattended join, or leave as `CHANGEME` and run once via SSH:
  ```bash
  tailscale up --advertise-routes=192.168.100.0/24 --accept-dns=false
  ```
- **Manual steps in Tailscale Admin Console (`login.tailscale.com/admin`):**
  1. **Machines → `tailscale` → Edit route settings:** approve `192.168.100.0/24` and disable key expiry (recommended for an always-on subnet router).
  2. **DNS → Nameservers → Add nameserver → Custom (Split DNS):** add `192.168.100.30` restricted to domain `haytham.internal` so remote devices resolve `*.haytham.internal` through Pi-hole over the tunnel.
- `--accept-dns=false` is intentional on CT `130` so the container keeps its Terraform public resolvers and avoids DNS loops.

## 5. Verification

```bash
pct exec 132 -- ls -la /dev/net/tun
# Expect: crw-rw-rw- 1 root root 10, 200 /dev/net/tun

pct exec 132 -- cat /proc/sys/net/ipv4/ip_forward
# Expect: 1

pct exec 132 -- tailscale status
# Expect: connected, advertising 192.168.100.0/24
```

From a phone on cellular data with Tailscale enabled: open `https://haytham.internal`, `https://vaultwarden.haytham.internal`, and `https://immich.haytham.internal`.

## 6. Known gotchas

- **HTTP 403 in Terraform on `device_passthrough`:** Proxmox blocks non-root API tokens (`terraform@pve!terraform`) from attaching `dev0`. Always manage `/dev/net/tun` via `ansible/host_devices.yml` (`root@192.168.100.2`).
- **`tailscaled` fails to create `tun` interface:** `/dev/net/tun` passthrough missing or container not rebooted after `pct set`. Re-run `ansible-playbook host_devices.yml`.

## 7. FAQ

**Q: Do I need Tailscale installed on every LXC?**
A: No. One subnet router (`CT 132`) exposes the entire `192.168.100.0/24` subnet cleanly to your Tailnet.

**Q: Do I need to open ports on my home router?**
A: No. Tailscale establishes outbound encrypted WireGuard tunnels through NAT.
