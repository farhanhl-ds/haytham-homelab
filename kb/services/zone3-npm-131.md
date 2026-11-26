---
id: svc-zone3-npm-131
title: NPM — Zone 3 Core Infra (CT 131)
tier: "zone3"
ctid: "131"
ip: 192.168.100.31
status: planned
last_verified: unreleased
tags: [npm, reverse-proxy, ssl, zone3, docker]
retrievable: true
---

# NPM — Zone 3 Core Infra (CT 131)

## 1. Purpose

Reverse proxy + SSL termination for every HTTP service. Sole target of the Pi-hole (`130`) wildcard `*.haytham.internal`. Ephemeral container in `homelab-ephemeral` — freely rebuildable via Terraform + Ansible.

## 2. Spec

| Field | Value |
|---|---|
| CTID / IP | `131` / `192.168.100.31` (`ID = 100 + last_octet`) |
| Zone / Pool | Zone 3 Core Infra / `homelab-ephemeral` |
| Resources | 1 core / 384 MB RAM / 512 MB swap / 8 GB disk |
| Base | Ubuntu 24.04 LXC + Docker (`roles/docker`), `nesting=true`, unprivileged, `overlayfs` |
| Image | `jc21/nginx-proxy-manager:2.16.0` via compose |

## 3. Provisioning

- Terraform `module.zone3_infra["npm"]`.
- Ansible `zone3_infra.yml` → `roles/npm` (depends on `roles/docker`).

## 4. Configuration

NPM stores proxy host rules in **SQLite inside the container** (backed up daily in Track 1 `restic`, recreated cleanly on fresh builds):

1. Create admin account at `http://192.168.100.31:81`.
2. Import Custom Certificate `haytham-internal` (key+crt from `/var/lib/haytham-ops/homelab-cert/` or Windows backup).
3. Add Proxy Hosts (all: cert `haytham-internal`, Force SSL + HTTP/2):

| Domain | Forward | Extra Options |
|---|---|---|
| `haytham.internal` | `http://192.168.100.40:3000` | Zone 4 Homepage (`CT 140`, root dashboard) |
| `infisical.haytham.internal` | `http://192.168.100.10:8080` | Zone 1 Infisical (`CT 110`) + **Websockets Support ON** *(CLI still uses direct IP `:8080`)* |
| `pihole.haytham.internal` | `http://192.168.100.30:80` | Zone 3 Pi-hole (`CT 130`) + Custom location `/` → `rewrite ^/$ /admin permanent;` |
| `npm.haytham.internal` | `http://192.168.100.31:81` | Zone 3 NPM Admin UI (`CT 131`) |
| `vaultwarden.haytham.internal` | `http://192.168.100.20:80` | Zone 2 Vaultwarden (`CT 120`) + **Websockets Support ON** |
| `immich.haytham.internal` | `http://192.168.100.21:2283` | Zone 2 Immich (`CT 121`) + **Websockets Support ON** + Advanced: `client_max_body_size 50000M; proxy_read_timeout 600s; proxy_send_timeout 600s;` |
| `uptime.haytham.internal` | `http://192.168.100.41:3001` | Zone 4 Uptime Kuma (`CT 141`) + **Websockets Support ON** |
| `pve.haytham.internal` | `https://192.168.100.2:8006` | Zone 0 Proxmox (`haytham`) + **Scheme `https`** + **Websockets Support ON** (noVNC) |

*(Deferred hosts when revived: `karakeep.haytham.internal → 192.168.100.23:3000`, `pgadmin.haytham.internal → 192.168.100.42:80`.)*

## 5. Verification

```bash
sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
curl -kI https://pihole.haytham.internal
```

## 6. Known Gotchas

- Pi-hole v6 root `/` returns 403 by design — the custom location rewrite fixes it.
- Keep Infisical CLI pointing at `http://192.168.100.10:8080/api` directly so Terraform/Ansible remain operational even when NPM (`131`) is being rebuilt.

## 7. FAQ

**Q: Do I need a DNS record for a new app?**
A: No. Pi-hole wildcard `*.haytham.internal → 192.168.100.31` handles all subdomains; only add the Proxy Host in NPM.
