---
id: svc-homepage-440
title: Homepage — Tier 40 Dashboard (CTID 440)
tier: "40"
ctid: "440"
ip: 192.168.100.44
status: planned
last_verified: unreleased
tags: [homepage, dashboard, tier40, docker]
retrievable: true
---

# Homepage — Tier 40 Dashboard (CTID 440)

## 1. Purpose

Lightweight application dashboard served at the root domain `https://haytham.internal`. Single landing page linking all active homelab services.

## 2. Spec

| Field | Value |
|---|---|
| CTID / IP | 440 / `192.168.100.44` (see `../reference/ip-ctid-matrix.md`) |
| Resources | 1 core / 384 MB RAM / 512 MB swap / 4 GB disk |
| Base | Ubuntu 24.04 LXC + Docker (`roles/docker`), `ghcr.io/gethomepage/homepage:v2.8.0` |
| Port | `3000` |

## 3. Provisioning

- Terraform: `module.tier40["homepage"]`.
- Ansible: `tier40.yml` → `roles/homepage` (depends on `roles/docker`), deploys compose + seeds initial `settings.yaml`, `services.yaml`, `bookmarks.yaml`, and `widgets.yaml` (`force: false` so subsequent UI/file customizations are preserved).

## 4. Configuration

- **`HOMEPAGE_ALLOWED_HOSTS` (mandatory since v1.0):** Set to `haytham.internal,192.168.100.44:3000` in compose. Missing this triggers `Host validation failed` when accessed through NPM.
- **No secrets required:** Pure YAML config in `/opt/homepage/config` (backed up daily in Track 1 `restic`).
- **NPM Proxy Host:** `haytham.internal → 192.168.100.44:3000`, wildcard cert `haytham-internal`, Force SSL + HTTP/2.
- **Pi-hole DNS note:** `/etc/dnsmasq.d/99-wildcard-haytham.conf` uses `address=/.haytham.internal/192.168.100.12`, which covers both `*.haytham.internal` and the apex `haytham.internal`.

## 5. Verification

```bash
ssh root@192.168.100.44 "docker ps"
# Expect: homepage Up

dig haytham.internal @192.168.100.11 +short
# Expect: 192.168.100.12

curl -kI https://haytham.internal
# Expect: HTTP/2 200
```

## 6. Known gotchas

- **`Host validation failed` in container logs:** Add the exact `Host` header (domain or `ip:port`) to `homepage_allowed_hosts` in `roles/homepage/defaults/main.yml` and re-run `tier40.yml`.

## 7. FAQ

**Q: Will re-running `tier40.yml` overwrite my custom `services.yaml`?**
A: No. Seed templates use `force: false`, so Ansible only creates missing config files.
