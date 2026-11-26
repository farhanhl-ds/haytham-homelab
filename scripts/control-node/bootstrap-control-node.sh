#!/usr/bin/env bash
set -euo pipefail

# Layer 4 — Disposable Control Node Bootstrap (`devbox`, Ubuntu 24.04)
#
# Rebuilds a fresh Ubuntu 24.04 VMware VM into a hardened Haytham control node
# in < 10 minutes:
#   1. Installs OS prerequisites (ansible, openssh-server, openssh-client, dnsutils, rsync, restic, ufw, age, jq).
#   2. Installs pinned Terraform binary to /usr/local/bin/terraform with SHA-256 verification.
#   3. Installs Infisical CLI to /usr/local/bin/infisical via official repository.
#   4. Installs Ansible Galaxy collections system-wide (/usr/share/ansible/collections).
#   5. Runs setup-privilege-split.sh (homelab-ops / homelab-agent / /srv/haytham-homelab).
#   6. Hardens sshd (AllowUsers human-only, pubkey-only, no forwarding) & TTY TIOCSTI sysctl.
#   7. Runs harden-control-node-ufw.sh (VMnet8-only inbound SSH, strict egress, kernel UID LAN-block).
#
# Run as root on a fresh Ubuntu 24.04 VMware VM:
#   sudo ./scripts/control-node/bootstrap-control-node.sh

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

HUMAN_USER="${HUMAN_USER:-${SUDO_USER:-farhan}}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.11.4}"
TERRAFORM_ARCH="${TERRAFORM_ARCH:-amd64}"

echo "[INFO] 1/7 Installing Ubuntu OS prerequisites..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  ansible \
  age \
  bind9-dnsutils \
  ca-certificates \
  curl \
  git \
  gnupg \
  iptables \
  jq \
  openssh-client \
  openssh-server \
  restic \
  rsync \
  ufw \
  unzip

echo "[INFO] 2/7 Installing Terraform v${TERRAFORM_VERSION} to /usr/local/bin/terraform..."
install_terraform() {
  if command -v /usr/local/bin/terraform >/dev/null 2>&1 \
     && /usr/local/bin/terraform version | grep -q "v${TERRAFORM_VERSION}"; then
    echo "[INFO] Terraform v${TERRAFORM_VERSION} already installed at /usr/local/bin/terraform."
    return 0
  fi

  local tmpdir zip_name sums_name expected_sha actual_sha
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  zip_name="terraform_${TERRAFORM_VERSION}_linux_${TERRAFORM_ARCH}.zip"
  sums_name="terraform_${TERRAFORM_VERSION}_SHA256SUMS"

  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${zip_name}" -o "${tmpdir}/${zip_name}"
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${sums_name}" -o "${tmpdir}/${sums_name}"

  expected_sha="$(awk -v f="${zip_name}" '$2 == f {print $1}' "${tmpdir}/${sums_name}")"
  actual_sha="$(sha256sum "${tmpdir}/${zip_name}" | awk '{print $1}')"

  if [[ -z "${expected_sha}" || "${expected_sha}" != "${actual_sha}" ]]; then
    echo "[ERROR] Terraform SHA-256 checksum mismatch! Expected=${expected_sha} Actual=${actual_sha}" >&2
    exit 1
  fi

  unzip -q "${tmpdir}/${zip_name}" -d "${tmpdir}"
  install -m 0755 -o root -g root "${tmpdir}/terraform" /usr/local/bin/terraform
  echo "[OK] Installed $(/usr/local/bin/terraform version | head -n 1)"
}
install_terraform

echo "[INFO] 3/7 Installing Infisical CLI..."
if ! command -v infisical >/dev/null 2>&1; then
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash
  apt-get update
  apt-get install -y infisical
fi
echo "[OK] Infisical CLI: $(infisical --version 2>&1 | head -n 1)"

echo "[INFO] 4/7 Installing Ansible Galaxy collections to /usr/share/ansible/collections..."
install -d -m 0755 /usr/share/ansible/collections
ansible-galaxy collection install \
  -r "${REPO_ROOT}/ansible/requirements.yml" \
  -p /usr/share/ansible/collections \
  --force

echo "[INFO] 5/7 Applying OS Privilege Split (/srv/haytham-homelab, homelab-ops, homelab-agent)..."
bash "${SCRIPT_DIR}/setup-privilege-split.sh"

echo "[INFO] 6/7 Hardening OpenSSH daemon (VMnet8 pubkey-only, AllowUsers ${HUMAN_USER}) & TTY TIOCSTI..."
# Use 01- prefix because sshd_config is first-match-wins (overrides 50-cloud-init.conf)
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/01-haytham-hardening.conf <<SSHEOF
# Haytham Control Node — Hardened VMnet8-only SSH (ADR-008)
# First-match-wins drop-in (01-) overriding cloud-init defaults.
PermitRootLogin no
AllowUsers ${HUMAN_USER}
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
GatewayPorts no
MaxAuthTries 3
LoginGraceTime 30
SSHEOF
chmod 0644 /etc/ssh/sshd_config.d/01-haytham-hardening.conf
sshd -t
systemctl enable ssh >/dev/null 2>&1 || true
systemctl restart ssh 2>/dev/null || systemctl reload ssh 2>/dev/null || true

# Defense-in-depth: prevent TIOCSTI keystroke injection across sudo PTY boundaries
cat > /etc/sysctl.d/99-haytham-hardening.conf <<SYSEOF
# Prevent TIOCSTI terminal injection across sudo boundaries (ADR-008)
dev.tty.legacy_tiocsti = 0
SYSEOF
chmod 0644 /etc/sysctl.d/99-haytham-hardening.conf
sysctl -w dev.tty.legacy_tiocsti=0 >/dev/null 2>&1 || true

HUMAN_HOME="$(getent passwd "${HUMAN_USER}" | cut -d: -f6 || echo "/home/${HUMAN_USER}")"
if [[ ! -s "${HUMAN_HOME}/.ssh/authorized_keys" ]]; then
  echo "[WARN] PasswordAuthentication is disabled, and ${HUMAN_HOME}/.ssh/authorized_keys is missing/empty!"
  echo "       Add your Windows dedicated devbox pubkey (id_ed25519_devbox.pub — NOT Break-Glass!)"
  echo "       via VMware Console BEFORE taking the 'clean-base' snapshot or SSHing from Windows Terminal."
fi

echo "[INFO] 7/7 Applying strict UFW (VMnet8 SSH in, zero-trust egress) & kernel UID LAN-block..."
bash "${REPO_ROOT}/scripts/hardening/harden-control-node-ufw.sh"

cat <<'DONE_EOF'

====================================================================
CONTROL NODE BOOTSTRAP COMPLETE — TAKE GOLDEN SNAPSHOT NOW!
====================================================================
1. Ensure your Windows dedicated devbox SSH PUBLIC key
   (id_ed25519_devbox.pub — NEVER your Windows Break-Glass key!)
   is in ~/.ssh/authorized_keys (chmod 0600) so Windows Terminal
   SSH (`ssh devbox-agent` / `ssh devbox-ops`) works immediately
   after any snapshot revert.
2. Shut down or pause devbox and take a VMware Snapshot named:
     clean-base
   (BEFORE restoring any secrets into /var/lib/haytham-ops/!)
3. Verify VMware settings:
     - Network Adapter  : NAT (VMnet8)
     - Shared Folders   : Disabled
     - Drag & Drop      : Disabled
     - Copy & Paste     : Disabled
     - USB Auto-Connect : Disabled
4. After taking `clean-base`, restore your encrypted state bundle
   via Windows Terminal (`ssh devbox-ops` -> `ops-bundle unpack ...`).
5. Launch Antigravity (`agy`) ONLY as user `homelab-agent` inside
   `/srv/haytham-homelab` (via `ssh devbox-agent` from Windows Terminal).
====================================================================
DONE_EOF
