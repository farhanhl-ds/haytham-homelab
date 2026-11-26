---
id: arch-tier-ctid
title: Security-Zone and ID Scheme
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, zones, ctid, security]
retrievable: true
---

# Security-Zone and ID Scheme

## 1. Security-Zone Numbering (`ID = 100 + last_octet`)

`haytham-homelab` organizes all Proxmox guests into **Security Zones** based on **blast radius, data criticality, and Terraform lifecycle** (`ADR-008`), replacing the legacy functional 10–90 tier scheme. Every VM and LXC obeys `ID = 100 + last_octet` with 10 tight slots per zone:

| Zone | ID / IP Range | Lifecycle & Protection | Proxmox Pool / ACL | Phase 1 Active Services |
|---|---|---|---|---|
| **Zone 0** | Host / `VM 103–109` (`.2`, `.3–.9`) | Physical Host & VMs (out-of-band) | ZERO `terraform@pve` ACL | Proxmox `haytham` + Host Backups (`.2`); HAOS (`VM 103`, deferred) |
| **Zone 1** | `CT 110–119` (`.10–.19`) | **Immutable Core** (setup once, NEVER in Terraform) | `homelab-immutable` / `protection=1` / ZERO ACL | **Infisical (`110` / `.10`)** |
| **Zone 2** | `CT 120–129` (`.20–.29`) | **Protected Data (Stateful P0)** | `homelab-protected` / `protection=1` / `HomelabProtectedOps` (NO destroy) | **Vaultwarden (`120`)**, **Immich (`121`)** *(deferred: Postgres `122`, Karakeep `123`)* |
| **Zone 3** | `CT 130–139` (`.30–.39`) | **Core Infra / Network** (ephemeral) | `homelab-ephemeral` / `PVEVMAdmin` | **Pi-hole (`130`)**, **NPM (`131`)**, **Tailscale (`132`)** *(deferred: Redis `133`)* |
| **Zone 4** | `CT 140–149` (`.40–.49`) | **Ephemeral Apps & Ops** (ephemeral) | `homelab-ephemeral` / `PVEVMAdmin` | **Homepage (`140`)**, **Uptime Kuma (`141`)** *(deferred: pgAdmin `142`)* |
| **Zone 5** | `CT 150–159` (`.50–.59`) | **Sandbox / Lab** (100% disposable) | `homelab-ephemeral` / `PVEVMAdmin` | *(Reserved for future AI/dev experiments)* |

Canonical IP/ID table: `../reference/ip-ctid-matrix.md`.

## 2. Placement Rule (1-Question Test)

When adding a new service, ask: **"If this container is destroyed right now, is irreplaceable personal data lost?"**

- **Bootstrap dependency for provisioning all other services** → **Zone 1** (outside Terraform, `protection=1`).
- **Yes (irreplaceable user/repo/database state)** → **Zone 2** (`homelab-protected`, `protection=1`, P0 Track 1/2 backup). Examples: Vaultwarden, Immich, Postgres, Karakeep, Gitea, Neo4j, Paperless-ngx, Frigate.
- **No (stateless or fully reproducible from Git)** → **Zone 3** (network/ingress/cache), **Zone 4** (dashboards/stateless tools/monitoring/CI runners like Homepage, Uptime Kuma, Stirling-PDF, CI Runner), or **Zone 5** (sandbox/experiments).
- **Requires its own kernel/OS** → **Zone 0** (VM `103–109`).

## 3. Architectural Invariants

- **1 service = 1 LXC** remains the standard (`ADR-007`).
- **Self-contained multi-container exceptions:** `CT 110` Infisical (Infisical + PG + Redis), `CT 121` Immich (server + ML + Valkey + Postgres/VectorChord), and deferred `CT 123` Karakeep.
- **Host-managed backups (`ansible/host_backups.yml`)** run directly on Proxmox host `haytham` (`.2`) via `systemd` timers for zero container overhead.
