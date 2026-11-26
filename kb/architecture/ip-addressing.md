---
id: arch-ip-addressing
title: IP Addressing Scheme
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, network, ip, zones]
retrievable: true
---

# IP Addressing Scheme

## 1. Universal Scheme (`ID = 100 + last_octet`, `ADR-008`)

- Subnet `192.168.100.0/24`, gateway `192.168.100.1`.
- **Universal formula for BOTH VMs and LXCs:** `Proxmox ID = 100 + last_octet` (e.g., `.3 → VM 103`, `.10 → CT 110`, `.21 → CT 121`, `.30 → CT 130`).
- Rationale: Proxmox requires all VMIDs/CTIDs `>= 100`, and static LAN octets occupy `.3–.99`. Adding `100` gives an unbroken 1-to-1 identity across every VM and LXC while aligning each 10-IP block cleanly with a Security Zone.

## 2. Security-Zone Block Allocation (10 Slots / Zone)

Set the Proxmox host to `.2` at ISO install time, before provisioning anything else.

```text
.1          Gateway (router) — DENIED in haytham-ctl UFW
.2          Proxmox host haytham (+ Host Backups)
.3-.9       Zone 0 · Virtual Machines (VM 103 HAOS deferred; .4-.9 future VMs)
.10-.19     Zone 1 · Immutable Core (CT 110 Infisical; outside Terraform, ZERO ACL)
.20-.29     Zone 2 · Protected Data P0 (CT 120 Vaultwarden, CT 121 Immich; protection=1)
.30-.39     Zone 3 · Core Infra / Network (CT 130 Pi-hole, CT 131 NPM, CT 132 Tailscale)
.40-.49     Zone 4 · Ephemeral Apps & Ops (CT 140 Homepage, CT 141 Uptime Kuma)
.50-.59     Zone 5 · Sandbox / Lab (future disposable experiments)
.60-.99     Open Reserve (unallocated, DENIED in haytham-ctl UFW until expanded)
.100-.254   DHCP pool (general LAN devices, DENIED in haytham-ctl UFW)
```

Prerequisites before provisioning:
- Router DHCP pool starts at `.100` (`.2–.99` strictly static).
- Router DHCP reservation for deferred `VM 103` HAOS MAC `BC:24:11:D7:75:C0` → `192.168.100.3`.
- Router DNS stays at ISP default until Pi-hole (`130`) + NPM (`131`) are verified (`dns-naming.md`).

## 3. Canonical Table

See `../reference/ip-ctid-matrix.md` — do not duplicate per-service IPs here.

## 4. FAQ

**Q: Why pack each zone to 10 slots instead of 20?**
A: Keeping the active footprint compact (`.10–.49`) minimizes the UFW allowlist surface on `haytham-ctl` and leaves `.60–.99` completely unallocated for future zone expansion or other LAN devices.

**Q: Static IP or DHCP reservation for LXCs?**
A: Static in Terraform (or `bootstrap-infisical.sh` for Zone 1 `CT 110`). Only VMs use MAC-pinned DHCP reservations.
