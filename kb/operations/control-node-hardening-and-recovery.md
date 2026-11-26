---
id: ops-control-node-hardening-and-recovery
title: Runbook — Zero-Trust Control Node Hardening & Disposable Recovery
tier: "x"
ctid: "n/a"
ip: n/a
status: planned
last_verified: unreleased
tags: [operations, security, hardening, control-node, recovery, vmware, infisical, rbac]
retrievable: true
---

# Runbook — Zero-Trust Control Node Hardening & Disposable Recovery

## 1. Purpose

Configure the 4-layer zero-trust provisioning architecture (`ADR-008`) separating the Windows host PC, VMware Linux control node (`haytham-ctl`), unprivileged AI agent (`homelab-agent`), human-gated operator (`homelab-ops`), Zone 1 Immutable Infisical (`CT 110`), and Proxmox hypervisor guardrails — and recover `haytham-ctl` from failure or suspected compromise in **< 10 minutes**.

## 2. When to Use

- Initial hardening of a new VMware Ubuntu 24.04 control node (`haytham-ctl`).
- Locking or temporarily unlocking Zone 2 Proxmox RBAC during disaster recovery drills.
- Wiping and rebuilding `haytham-ctl` after OS corruption or suspected AI agent / prompt-injection compromise.

## 3. Prerequisites

- Proxmox host `haytham` (`192.168.100.2`) online with Ubuntu 24.04 LXC template downloaded (`ADR-002`).
- Separate **Windows-only Break-Glass & Backup-Pull SSH key** (`%USERPROFILE%\.ssh\id_ed25519`) authorized on `root@192.168.100.2` (NEVER copied to `haytham-ctl`).
- Fresh Ubuntu 24.04 LTS VMware Workstation/Player VM (`haytham-ctl`) with repo cloned.

## 4. Steps

### Step 1 — Isolate VMware, Harden Windows Firewall & Prepare Dedicated haytham-ctl SSH Key (Layer 1)

1. In **VMware Workstation/Player** VM Settings for `haytham-ctl` (Ubuntu Server 24.04 LTS, 2–4 vCPU, 4 GB RAM, 30 GB thin disk):
   - **Network Adapter:** set to **NAT (`VMnet8`)** (not Bridged).
   - **Options → Shared Folders:** **Disabled**.
   - **Options → Guest Isolation:** uncheck **Enable drag and drop** and **Enable copy and paste**.
   - **USB Controller:** remove USB controller (or disable **Automatically connect new USB devices**).
2. On **Windows PC** (PowerShell as Administrator), block all inbound connections from `VMnet8`:
   ```powershell
   .\scripts\hardening\harden-windows-firewall.ps1
   ```
3. On **Windows PC** (PowerShell), create a **dedicated** SSH keypair for Windows Terminal access to `haytham-ctl` (NEVER reuse your Windows Break-Glass key `id_ed25519`!) and add 3 ergonomic aliases to `%USERPROFILE%\.ssh\config`:
   ```powershell
   ssh-keygen -t ed25519 -a 64 -C "windows-to-haytham-ctl" -f "$env:USERPROFILE\.ssh\id_ed25519_haytham_ctl"
   ```
   ```sshconfig
   Host haytham-ctl
       HostName <HAYTHAM_CTL_VMNET8_IP>
       User farhan
       IdentityFile ~/.ssh/id_ed25519_haytham_ctl
       IdentitiesOnly yes
       ForwardAgent no
       ForwardX11 no

   Host haytham-ctl-agent
       HostName <HAYTHAM_CTL_VMNET8_IP>
       User farhan
       IdentityFile ~/.ssh/id_ed25519_haytham_ctl
       IdentitiesOnly yes
       ForwardAgent no
       ForwardX11 no
       RequestTTY force
       RemoteCommand sudo -iu homelab-agent bash -lc 'cd /srv/haytham-homelab && exec bash -l'

   Host haytham-ctl-ops
       HostName <HAYTHAM_CTL_VMNET8_IP>
       User farhan
       IdentityFile ~/.ssh/id_ed25519_haytham_ctl
       IdentitiesOnly yes
       ForwardAgent no
       ForwardX11 no
       RequestTTY force
       RemoteCommand sudo -iu homelab-ops
   ```
   *(Daily workflow: open Windows Terminal Tab 1 with `ssh haytham-ctl-agent` for `agy`, Tab 2 with `ssh haytham-ctl-ops` for human-gated `ops-*` commands, and use `scp haytham-ctl:...` to copy encrypted `ops-bundle` archives off-host without Shared Folders.)*

### Step 2 — Bootstrap Zone 1 Immutable Infisical (`CT 110` @ `.10`, Layer 2a)

From **Windows Break-Glass SSH** on `haytham` (`root@192.168.100.2`):

```bash
# Copy Windows-only Break-Glass .pub key to haytham once, then bootstrap CT 110
chmod +x bootstrap-infisical.sh
./bootstrap-infisical.sh /root/windows_breakglass.pub
```

Then from your **Windows browser**:
1. Open `http://192.168.100.10:8080`, create your Admin account + MFA.
2. Create Project `haytham-homelab` (`prod` env) with folders `/terraform`, `/proxmox`, `/zone2`, `/zone3`, `/zone4` (`services/zone1-infisical-110.md §4`).
3. Create **read-only** Machine Identity `homelab-ops-ro` (Universal Auth) with Viewer permissions on `haytham-homelab` (`prod`).
4. Record `ENCRYPTION_KEY` and `AUTH_SECRET` from `/opt/infisical/.env` inside `CT 110` onto your offline emergency sheet / Windows KeePassXC.

### Step 3 — Bootstrap Disposable Control Node & Capture Golden Snapshot (Layers 3 & 4)

On **`haytham-ctl`** (Ubuntu Server 24.04) as human admin (`farhan`, via VMware Console):

```bash
# 1. Install your Windows dedicated haytham-ctl PUBLIC key BEFORE bootstrap
#    (PasswordAuthentication is disabled unconditionally by bootstrap-control-node.sh;
#     NEVER put your Windows Break-Glass key here!)
install -d -m 0700 ~/.ssh
# Paste contents of %USERPROFILE%\.ssh\id_ed25519_haytham_ctl.pub into ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys

# 2. Run control-node bootstrap (installs Terraform, Ansible, Infisical CLI,
#    privilege split, hardened sshd, TIOCSTI sysctl, UFW + kernel UID LAN-block)
sudo ./scripts/control-node/bootstrap-control-node.sh
```

> **CRITICAL:** Verify `ssh haytham-ctl` works from Windows Terminal, install the `agy` CLI binary globally (`/usr/local/bin/agy`, **without** logging in or placing any secrets in `/var/lib/haytham-ops/`), then shut down `haytham-ctl` and take a VMware Snapshot named **`clean-base`**.

### Step 4 — Populate `/var/lib/haytham-ops/` & Pack Encrypted Recovery Bundle

Switch to human operator `homelab-ops` on `haytham-ctl`:

```bash
sudo -iu homelab-ops

# 1. Generate revocable control-node SSH keypair
ssh-keygen -t ed25519 -a 64 -N "" -C "homelab-ops@haytham-ctl" -f /var/lib/haytham-ops/.ssh/id_ed25519_control
chmod 0600 /var/lib/haytham-ops/.ssh/id_ed25519_control

# 2. Place Windows Break-Glass .pub key (public key only!) for Terraform LXC injection
#    -> /var/lib/haytham-ops/.ssh/windows_breakglass.pub (chmod 0644)

# 3. Configure non-secret terraform.tfvars (NO pve_api_token or ct_root_password!)
cp /srv/haytham-homelab/terraform/terraform.tfvars.example /var/lib/haytham-ops/terraform.tfvars
chmod 0600 /var/lib/haytham-ops/terraform.tfvars

# 4. Configure read-only Infisical Machine Identity credentials
cp /var/lib/haytham-ops/infisical-ops.env.example /var/lib/haytham-ops/infisical-ops.env
# Edit /var/lib/haytham-ops/infisical-ops.env with INFISICAL_PROJECT_ID, CLIENT_ID, CLIENT_SECRET
chmod 0600 /var/lib/haytham-ops/infisical-ops.env

# 5. Authorize /var/lib/haytham-ops/.ssh/id_ed25519_control.pub on haytham (192.168.100.2)
#    (NEVER authorize it on Zone 1 CT 110 Infisical!)

# 6. Initialize Terraform working directory once
terraform -chdir=/srv/haytham-homelab/terraform init

# 7. Create encrypted recovery bundle and archive copy on Windows PC + offline USB
ops-bundle pack
```

### Step 5 — Provision Zones 2–4 & Lock Proxmox RBAC (Layer 2b)

1. From Windows Break-Glass SSH on `haytham`, run `harden-pve-rbac.sh --init` to create pools (`homelab-immutable`, `homelab-protected`, `homelab-ephemeral`) and custom role `HomelabProtectedOps`.
2. From `homelab-ops` on `haytham-ctl`, provision Zones 2–4:
   ```bash
   ops-tf-apply
   ops-ansible-apply host_devices.yml
   ops-ansible-apply zone3_infra.yml
   ops-ansible-apply zone2_protected.yml
   ops-ansible-apply zone4_apps.yml
   ops-ansible-apply host_backups.yml
   ops-bundle pack   # Refresh bundle with new terraform.tfstate
   ```
3. Immediately **lock** Proxmox RBAC from Windows Break-Glass SSH on `haytham`:
   ```bash
   ./harden-pve-rbac.sh --lock
   ./harden-pve-rbac.sh --status
   ```

### Daily Operating Workflow (Agent vs Human Gate)

| Task | Executed As | Command |
|---|---|---|
| Edit IaC / KB / scripts | `homelab-agent` (`/srv/haytham-homelab`) | Normal Git / editor workflow |
| Terraform validate & plan | `homelab-agent` | `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan` |
| Ansible dry-run (`--check --diff`) | `homelab-agent` | `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check <playbook>` |
| Read-only homelab health check | `homelab-agent` | `sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check` |
| Live Terraform apply | **Human** (`sudo -iu homelab-ops`) | `ops-tf-apply` (type `APPLY`) |
| Live Ansible apply | **Human** (`sudo -iu homelab-ops`) | `ops-ansible-apply <playbook>` (type `YES`) |
| Rotate any secret | **Human** (Windows browser) | Infisical Web UI (`http://192.168.100.10:8080`) → re-run `ops-ansible-apply` |
| Unlock Zone 2 CT for DR rebuild | **Human** (Windows Break-Glass SSH) | `./harden-pve-rbac.sh --unlock-dr <120-129>` → rebuild → `--lock` |

### Disposable Control Node Compromise / Rebuild Playbook (< 10 Minutes)

If `haytham-ctl` breaks or you suspect prompt-injection / compromise:

1. **Power off `haytham-ctl` and revert VMware snapshot to `clean-base`** (or spin up a fresh Ubuntu 24.04 VM and run `bootstrap-control-node.sh`).
2. **Revoke compromised credentials from Windows PC:**
   - Remove the old `haytham-ctl` public key line from `/root/.ssh/authorized_keys` on `haytham` (`.2`) and active LXCs (`.20, .21, .30, .31, .32, .40, .41`).
   - In Infisical UI (`http://192.168.100.10:8080`), revoke/rotate `homelab-ops-ro` Universal Auth Client Secret (and rotate any secrets that `homelab-ops` could have read if compromise crossed into `homelab-ops`).
3. **Restore encrypted bundle inside clean `haytham-ctl`:**
   ```bash
   sudo -iu homelab-ops
   ops-bundle unpack /path/to/haytham-control-bundle-*.tar.age
   ```
   `ops-bundle unpack` automatically generates a **brand-new** `id_ed25519_control` keypair and prints its `.pub` key.
4. Update `/var/lib/haytham-ops/infisical-ops.env` with the rotated `homelab-ops-ro` secret, authorize the new `.pub` key from Windows Break-Glass SSH, and verify `ops-health-check`.

## 5. Verification

### Negative Security Tests (Must ALL Fail)

```bash
# As homelab-agent — secret & privilege boundary checks
sudo -u homelab-agent cat /var/lib/haytham-ops/infisical-ops.env
sudo -u homelab-agent cat /var/lib/haytham-ops/.ssh/id_ed25519_control
sudo -u homelab-agent sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-apply
sudo -u homelab-agent sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check "zone3_infra.yml; id"

# As homelab-agent — kernel UID LAN-block (must reject immediately)
sudo -u homelab-agent curl -m 2 http://192.168.100.10:8080/api/status
sudo -u homelab-agent nc -zw2 192.168.100.2 8006

# As homelab-ops — UFW egress block on Router, Windows PC, VMnet8 host .1, and Open Reserve (.60-.99)
nc -zw2 192.168.100.1 80
nc -zw2 <VMNET8_HOST_IP> 445
nc -zw2 <WINDOWS_PC_LAN_IP> 445
nc -zw2 192.168.100.65 22
```

From **Windows Terminal** — hardened `sshd` checks (must ALL fail):
```powershell
ssh root@<HAYTHAM_CTL_VMNET8_IP>                                    # PermitRootLogin no
ssh homelab-ops@<HAYTHAM_CTL_VMNET8_IP>                             # Not in AllowUsers
ssh homelab-agent@<HAYTHAM_CTL_VMNET8_IP>                           # Not in AllowUsers
ssh -o PubkeyAuthentication=no farhan@<HAYTHAM_CTL_VMNET8_IP>       # PasswordAuthentication no
ssh -A haytham-ctl "ssh-add -l"                                     # AllowAgentForwarding no
ssh -L 9999:192.168.100.10:8080 haytham-ctl                         # AllowTcpForwarding no
```

### Positive Functional Tests (Must ALL Succeed)

```bash
sudo -u homelab-agent sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-health-check
sudo -u homelab-agent sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-tf-plan
sudo -u homelab-agent sudo -u homelab-ops /usr/local/libexec/haytham-ops/ops-ansible-check zone3_infra.yml
```

On Proxmox host `haytham`:
```bash
./harden-pve-rbac.sh --status
```

## 6. Rollback

- **Windows Firewall:** `.\scripts\hardening\harden-windows-firewall.ps1 -Remove`
- **Proxmox Zone 2 Lock (DR only):** `./harden-pve-rbac.sh --unlock-dr <120-129>` (re-run `--lock` immediately afterward)
- **Control Node:** Revert VMware snapshot `clean-base`.

## 7. Manual Gaps

- VMware isolation toggles (NAT, Shared Folders, Drag & Drop, Clipboard, USB) and Golden Snapshot creation must be performed in the VMware GUI.
- Initial Infisical Admin account + MFA + `homelab-ops-ro` Machine Identity setup is performed once in the Infisical Web UI.
- Offline archival of `haytham-control-bundle-*.tar.age` and `CT 110`'s `ENCRYPTION_KEY`/`AUTH_SECRET` must be kept on Windows PC + offline USB drive.
