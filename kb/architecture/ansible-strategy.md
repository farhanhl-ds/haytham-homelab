---
id: arch-ansible-strategy
title: Ansible Strategy
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [architecture, ansible, infisical, security, zones]
retrievable: true
---

# Ansible Strategy

## 1. Zero-Trust Control Node Execution (`ADR-008`)

- Ansible runs on the disposable VMware NAT Ubuntu 24.04 control node (`haytham-ctl`) from the shared Git workspace `/srv/haytham-homelab`.
- **OS Privilege Split:**
  - `homelab-agent` (AI agent, unprivileged, zero `sudo`, kernel-blocked from `192.168.0.0/16`) may run **only** read-only dry-runs via `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check <playbook>`.
  - Human operator (`sudo -iu homelab-ops`) executes live changes via `ops-ansible-apply <playbook>` on an interactive TTY.
- SSH authentication uses the ephemeral `ssh-agent` started by `ops-ansible-*` with `/var/lib/haytham-ops/.ssh/id_ed25519_control` (revocable key, never stored in `/srv/haytham-homelab`).
- Collections (`community.postgresql`, `community.docker`) are installed system-wide to `/usr/share/ansible/collections` by `bootstrap-control-node.sh`.

## 2. Layout (Security-Zone Playbooks)

```text
ansible/
  ansible.cfg (remote_user=root, collections_path incl. /usr/share/ansible/collections, NO .vault_pass!)
  inventory/hosts.yml (proxmox, zone2, zone3, zone4 groups)
  group_vars/{all.yml, proxmox.yml, zone2.yml, zone3.yml, zone4.yml}  # non-secret defaults ONLY
  host_devices.yml      # /dev/net/tun (CT 132) & /dev/dri/* (CT 121)
  zone3_infra.yml       # Pi-hole (130), NPM (131), Tailscale (132); deferred Redis (133)
  zone2_protected.yml   # Vaultwarden (120), Immich (121); deferred Postgres (122), Karakeep (123)
  zone4_apps.yml        # Homepage (140), Uptime Kuma (141); deferred pgAdmin (142)
  host_backups.yml      # Proxmox host daily restic (incl. Zone 1 CT 110) + weekly vzdump
  roles/{docker, pve_devices, backup, pihole, npm, tailscale, vaultwarden, immich, homepage, uptime_kuma, postgres, redis, pgadmin, karakeep}/
  requirements.yml
```

Run order: `host_devices.yml → zone3_infra.yml → zone2_protected.yml → zone4_apps.yml → host_backups.yml`.

## 3. Runtime Secret Pattern (Zone 1 Infisical — Zero `.vault_pass`)

- No `.vault_pass` file and no `!vault` blocks live on `haytham-ctl` or in Git.
- `group_vars/*.yml` declare `vault_*` placeholders as `CHANGEME` (triggering fail-safe guards if someone attempts to run `ansible-playbook` outside the wrappers).
- When `ops-ansible-check` or `ops-ansible-apply` runs, `_ops-infisical-lib.sh` authenticates the **read-only** Machine Identity `homelab-ops-ro` against Zone 1 Infisical (`http://192.168.100.10:8080/api`), writes the target path's secrets (`/proxmox`, `/zone2`, `/zone3`, or `/zone4`) into an ephemeral RAM-only `/dev/shm/haytham-sec.XXXXXX.json` (`0600`), passes `-e @<file>` to `ansible-playbook`, and runs `shred -u -z` on `EXIT` trap.
- All secret creation and rotation happens inside the Infisical Web UI (`operations/secret-rotation.md`).

## 4. Reusable Roles & Reproducibility

- `roles/docker` (official apt repo install) is shared via `meta/main.yml` dependencies across containerized services.
- Every manual SSH fix must be ported back into `kb/` + `ansible/` in the same session.
