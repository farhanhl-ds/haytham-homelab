---
id: eval-qa-golden
title: Eval — Golden Q/A for RAG
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [eval, rag, testing]
retrievable: false
---

# Eval — Golden Q/A for RAG

> Not ingested (`retrievable: false`). Use to score embedding/chunking changes. Expected answers point at canonical pages.

1. Q: What IP is Pi-hole? → `192.168.100.30` (`reference/ip-ctid-matrix.md`).
2. Q: What IP is NPM? → `192.168.100.31`.
3. Q: Why divide CTID by 10 for IPs? → CTIDs 100–990 exceed one octet (`architecture/ip-addressing.md`).
4. Q: Where is the Proxmox host and why? → `192.168.100.2`, set at install (`architecture/ip-addressing.md`).
5. Q: Where is HAOS and why a reservation? → `192.168.100.3`, first VM slot, MAC-pinned reservation-safe (`services/vm-haos-103.md`). Next VMs take `.4` upward.
6. Q: What domain base and why not .local? → `haytham.internal`; `.local` intercepted by mDNS RFC 6762 (`architecture/dns-naming.md`).
7. Q: Do new services need DNS records? → No, wildcard to NPM; add Proxy Host only.
8. Q: Do new services need new certs? → No, reuse wildcard.
9. Q: Which provider and why not telmate? → `bpg/proxmox`; telmate unmaintained.
10. Q: Which role fixes the 403 on template download? → add `PVEAuditor` for `Sys.Audit`.
11. Q: Why is `nesting=true` set? → systemd on Ubuntu 24.04 (`troubleshooting/docker-in-lxc.md`).
12. Q: Is `keyctl/privileged/vfs` needed for Docker? → No; nesting-only + overlayfs.
13. Q: Overlay/space error on Docker LXC? → wipe `/var/lib/docker` first (corrupt state, not perms).
14. Q: Pi-hole password command on v6? → `pihole setpassword`, not `-a -p`.
15. Q: Wildcard via Pi-hole UI? → Impossible; dnsmasq file + `misc.etc_dnsmasq_d true`.
16. Q: Gravity Error -2? → run `pihole -g`.
17. Q: How to query Pi-hole directly? → `dig <name> @192.168.100.30`.
18. Q: Why do internal names fail with Pi-hole listed second? → clients stop at first NXDOMAIN; order matters (`operations/dns-workstation-swap.md`).
19. Q: Postgres encoding required? → UTF8 + `template0` + `C.UTF-8` (avoid SQL_ASCII inheritance).
20. Q: `permission denied for schema public` on new DB? → PG15 revoked CREATE; grant in `roles/postgres`.
21. Q: Does Karakeep use shared Postgres? → No, SQLite-only.
22. Q: pgAdmin crash-loop sessions permission? → `chown 5050:5050` data dir.
23. Q: pgAdmin password rotation via re-run? → No (first-run only); use UI or wipe data.
24. Q: Vaultwarden DB and signups? → SQLite; `SIGNUPS_ALLOWED=false` after first account + websockets ON.
25. Q: Karakeep RAM/disk and why? → 2 cores / 4 GB / 24 GB; headless Chrome.
26. Q: HAOS Terraform or manual? → Manual `qm` (ADR-005); requires ovmf/q35/virtio-scsi-pci/efidisk0.
27. Q: HAOS boot hang signature? → "Booting from Hard Disk", 50% CPU, 0 IO.
28. Q: Reboot order for update-all (Phase 1)? → 320 → 610 → 440/910 → 110/120/130 (`operations/update-and-reboot.md`).
29. Q: How are Immich photos and Vaultwarden backed up without cloud or Samba? → Track 1 daily encrypted `restic` on Proxmox pulled over SSH; Track 2 incremental SSH pull directly from CT `610` (`library/upload/profile`) to PC/USB via `scripts/pull-homelab-backups.bat` (native Windows `cmd` inbox `ssh.exe` + `tar.exe`) or `scripts/pull-homelab-backups.sh` (Linux/WSL `rsync`) (`operations/backup-and-restore.md`).
30. Q: What is SSO status? → Reserved (ADR-004); Authelia default-if-needed.
31. Q: How to read one vault value? → `ansible localhost -m debug -a "var=<name>" -e @group_vars/<tier>.yml`.
32. Q: How to share project zip safely? → exclude `.vault_pass` (`zip -r … -x`).
33. Q: What are `haytham`'s current hardware specs? → ThinkCentre M910q Tiny, Intel i5 7th gen (HD 630 Quick Sync), 8 GB RAM (16 GB planned), 1 TB SSD (`architecture/overview.md`).
34. Q: Why are Tier 20, Karakeep, and HAOS deferred? → 8 GB RAM constraint & zero Tier 20 consumers; preserved for 16 GB revival (`decisions/ADR-007-lean-8gb-phase1.md`).
35. Q: Why are `/dev/net/tun` (CT 132) and `/dev/dri` (CT 121) configured via `host_devices.yml` instead of Terraform? → Proxmox returns HTTP 403 for `device_passthrough` on non-root API tokens (`services/zone3-tailscale-132.md`).
36. Q: What IP and CTID are Tailscale, Homepage, Immich, and Uptime Kuma? → `130` (`.13`), `440` (`.44`, root `haytham.internal`), `610` (`.61`, 500 GB), `910` (`.91`) (`reference/ip-ctid-matrix.md`).
