---
id: svc-uptime-kuma-910
title: Uptime Kuma — Tier 90 Observability (CTID 910)
tier: "90"
ctid: "910"
ip: 192.168.100.91
status: planned
last_verified: unreleased
tags: [uptime-kuma, monitoring, observability, tier90, docker]
retrievable: true
---

# Uptime Kuma — Tier 90 Observability (CTID 910)

## 1. Purpose

Self-hosted uptime monitoring and alerting for all homelab services, DNS resolution, HTTPS endpoints, and host reachability.

## 2. Spec

| Field | Value |
|---|---|
| CTID / IP | 910 / `192.168.100.91` (see `../reference/ip-ctid-matrix.md`) |
| Resources | 1 core / 384 MB RAM / 512 MB swap / 8 GB disk |
| Base | Ubuntu 24.04 LXC + Docker (`roles/docker`), `louislam/uptime-kuma:2.5.6` |
| Port | `3001` |
| DB | Embedded SQLite (`/opt/uptime-kuma/data/kuma.db`) |

## 3. Provisioning

- Terraform: `module.tier90["uptime_kuma"]`.
- Ansible: `tier90.yml` → `roles/uptime_kuma` (depends on `roles/docker`).

## 4. Configuration

- **First run:** Open `https://uptime.haytham.internal`, choose **SQLite** on `/setup-database`, and create the admin account (stored in SQLite, not Vault).
- **Container DNS:** Compose sets `dns: [192.168.100.11, 1.1.1.1]` so Uptime Kuma resolves `*.haytham.internal` via Pi-hole while CT `910` itself keeps Terraform's public resolvers for `apt`/Docker bootstrap.
- **NPM Proxy Host:** `uptime.haytham.internal → 192.168.100.91:3001`, wildcard cert, Force SSL + HTTP/2, **Websockets Support ON** (required by Uptime Kuma's Socket.IO UI).
- **Recommended monitors to add:**
  - HTTP(s): `https://haytham.internal`, `https://pihole.haytham.internal/admin/`, `https://npm.haytham.internal`, `https://vaultwarden.haytham.internal`, `https://immich.haytham.internal`, `https://pve.haytham.internal` (enable "Ignore TLS/SSL error" for self-signed wildcard cert).
  - DNS: `haytham.internal` against `192.168.100.11`.
  - Ping/TCP: Proxmox host `192.168.100.2:8006`, Tailscale `192.168.100.13`.
- **Backup:** Online SQLite hot backup of `kuma.db` + data dir runs daily in Track 1 (`roles/backup`).

## 5. Verification

```bash
ssh root@192.168.100.91 "docker ps"
# Expect: uptime_kuma Up
```

Browser: `https://uptime.haytham.internal` loads without Socket.IO reconnect errors.

## 6. Known gotchas

- **Infinite loading / WebSocket disconnect:** Websockets Support was left OFF in the NPM Proxy Host.
- **False SSL alerts on internal monitors:** Enable "Ignore TLS/SSL error for HTTPS websites" per monitor because internal services use the self-signed `*.haytham.internal` certificate.

## 7. FAQ

**Q: Does Uptime Kuma need shared Postgres?**
A: No — embedded SQLite is fast, self-contained, and backed up daily via Track 1 `restic`.
