---
name: homelab-rebuild
description: >-
  Use this skill when the user asks to rebuild, wipe, reprovision, or reconcile
  the Haytham Homelab LXCs from scratch using Terraform and Ansible.
---

# Homelab Rebuild (Terraform + Ansible)

Canonical runbook: `kb/operations/build-from-scratch.md` (read only if details beyond this checklist are needed).

## 1. Clarify Before Acting (Mandatory)

Confirm with the user before any destructive step:
1. **Rebuild mode:** Clean LXC wipe (`terraform destroy` + `apply`) vs. in-place reconcile vs. bare-metal Proxmox reinstall.
2. **Data safety:** Confirm whether live data (Vaultwarden CT `320`, Immich CT `610`, NPM CT `120`) needs backup first or is safe to wipe.
3. **DNS safe mode:** If the user's workstation uses `192.168.100.11` (Pi-hole) as primary DNS, remind them to switch to safe mode (`1.1.1.1` first — see `kb/operations/dns-workstation-swap.md`) before touching CT `110`.

## 2. Pre-Flight Readiness Checks (Read-Only)

Run in one command before making changes:
- Verify tools: `terraform`, `ansible-playbook`, `restic`, `dig`, `rsync`, plus `ansible-galaxy collection install -r ansible/requirements.yml`.
- Verify SSH key auth to `root@192.168.100.2`, existing `pct list`, Ubuntu 24.04 CT template (`/var/lib/vz/template/cache/ubuntu-24.04-standard_24.04-2_amd64.tar.zst`), `/dev/net/tun`, `/dev/dri/*`, and `pvesm status`.
- Verify `terraform/terraform.tfvars` has a valid Linux absolute `ssh_public_key_path` (do NOT print secret lines!).
- Verify no required `CHANGEME` remains in `ansible/group_vars/{proxmox,tier60}.yml` (`vault_tailscale_authkey` in `tier10.yml` may remain `CHANGEME` for interactive login) and `ansible-inventory --list >/dev/null` succeeds.

## 3. Terraform Provisioning

Always wrap Terraform commands with `ssh-agent` and `-parallelism=1` (prevents `local-lvm` lock timeout):

```bash
eval "$(ssh-agent -s)"
trap 'ssh-agent -k >/dev/null 2>&1 || true' EXIT
ssh-add ~/.ssh/id_ed25519

cd /home/farhan/haytham-homelab/terraform
terraform init -input=false
terraform validate

# Only on confirmed clean wipe:
terraform destroy -auto-approve -parallelism=1 -input=false

terraform plan
terraform apply -auto-approve -parallelism=1 -input=false
```

## 4. Host Passthrough & Ansible Tier Rollout

Clear stale SSH host keys, apply passthrough, wait for rebooted CTs (`130`, `610`), then run tiers in strict dependency order:

```bash
for ip in 192.168.100.11 192.168.100.12 192.168.100.13 192.168.100.32 192.168.100.44 192.168.100.61 192.168.100.91; do
  ssh-keygen -f ~/.ssh/known_hosts -R "$ip" 2>/dev/null || true
done

cd /home/farhan/haytham-homelab/ansible
export ANSIBLE_HOST_KEY_CHECKING=False

ansible-playbook host_devices.yml
# Wait until 192.168.100.13 and 192.168.100.61 accept SSH after pct reboot

ansible-playbook tier10.yml
ansible-playbook tier30.yml -e vaultwarden_signups_allowed=true   # lock after master account creation
ansible-playbook tier40.yml
ansible-playbook tier60.yml
ansible-playbook tier90.yml
ansible-playbook tier80.yml
```

## 5. Verification

Run in one batched check:
- `dig haytham.internal @192.168.100.11 +short` & `dig immich.haytham.internal @192.168.100.11 +short` → `192.168.100.12`.
- `ssh root@192.168.100.2 "pct list && free -h && systemctl list-timers 'homelab-*'"`.
- Verify `docker ps` healthy on `.12` (NPM, `overlayfs`), `.32` (Vaultwarden), `.44` (Homepage), `.61` (4 Immich containers + `/dev/dri`), `.91` (Uptime Kuma), and `/dev/net/tun` on `.13` (Tailscale).
- Trigger `systemctl start homelab-backup.service` on `.2`, check `restic snapshots`, and run `scripts/pull-homelab-backups.sh --state-only`.

## 6. Post-Build Manual Gaps (Remind User)

Point the user to the non-IaC UI steps (details in `kb/services/network-npm-120.md §4` & `kb/services/network-tailscale-130.md §4`):
1. **NPM (`http://192.168.100.12:81`):** Admin account, import wildcard cert, add 7 Proxy Hosts.
2. **Tailscale (`CT 130`):** `tailscale up --advertise-routes=192.168.100.0/24 --accept-dns=false` → approve route & disable key expiry in `login.tailscale.com/admin` → Split DNS `haytham.internal → 192.168.100.11`.
3. **Vaultwarden:** Create master account → immediately re-run `ansible-playbook tier30.yml` to lock `SIGNUPS_ALLOWED="false"`.
4. **Immich:** Create admin account → enable Intel Quick Sync in Video Transcoding settings.
5. **Uptime Kuma:** Create admin account → add internal monitors (ignore self-signed TLS).
6. **Workstation DNS:** Restore Pi-hole primary (`192.168.100.11`, fallback `1.1.1.1`).
