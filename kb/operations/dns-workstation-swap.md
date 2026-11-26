---
id: ops-dns-workstation-swap
title: Note — DNS Workstation Swap (resolver order)
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, dns, windows, pihole]
retrievable: true
---

# Note — DNS Workstation Swap (resolver order)

## 1. Rule

Clients stop at the **first definitive answer** (including NXDOMAIN). Secondary is only tried if primary is **unreachable** (timeout), not on "not found".

## 2. Two Modes (Swap Manually on Windows)

```powershell
# Safe-to-build (public first; internal names will NOT resolve)
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("1.1.1.1", "192.168.100.30")
# Normal use (Zone 3 Pi-hole CT 130 first; internal names resolve; public is fallback if Pi-hole down)
Set-DnsClientServerAddress -InterfaceAlias "Wi-Fi" -ServerAddresses ("192.168.100.30", "1.1.1.1")
ipconfig /flushdns
```

Requires Administrator (CIM error = not elevated, not a network bug).

## 3. When to Swap

- Before any work touching Zone 3 Pi-hole (`CT 130` @ `192.168.100.30`) → safe mode.
- After rebuild verifies green (`dig @192.168.100.30` returns `192.168.100.31`) → normal mode.
- Manual per-device step. Router-level DNS waits until multi-device need (blast radius).

## 4. FAQ

**Q: Pi-hole is listed but internal names fail?**
A: Check order — a public resolver first authoritatively NXDOMAINs `*.haytham.internal` and the client never asks Pi-hole (`192.168.100.30`).
