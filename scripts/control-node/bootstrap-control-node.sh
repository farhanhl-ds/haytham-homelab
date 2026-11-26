#!/usr/bin/env bash
set -euo pipefail

# Layer 4 — Disposable Control Node Bootstrap (`devbox`, Ubuntu 24.04)
#
# Rebuilds a fresh Ubuntu 24.04 VMware VM into a hardened Haytham control node
# in < 10 minutes:
#   1. Installs OS prerequisites (ansible, openssh-client, dnsutils, rsync, restic, ufw, age, jq).
#   2. Installs pinned Terraform binary to /usr/local/bin/terraform with SHA-256 verification.
#   3. Installs Infisical CLI to /usr/local/bin/infisical via official repository.
#   4. Installs Ansible Galaxy collections system-wide (/usr/share/ansible/collections).
#   5. Runs setup-privilege-split.sh (homelab-ops / homelab-agent / /srv/haytham-homelab).
#   6. Runs harden-control-node-ufw.sh (strict egress + kernel UID LAN-block).
#
# Run as root on a fresh Ubuntu 24.04 VMware VM:
#   sudo ./scripts/control-node/bootstrap-control-node.sh

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.11.4}"
TERRAFORM_ARCH="${TERRAFORM_ARCH:-amd64}"

echo "[INFO] 1/6 Installing Ubuntu OS prerequisites..."
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
  restic \
  rsync \
  ufw \
  unzip

echo "[INFO] 2/6 Installing Terraform v${TERRAFORM_VERSION} to /usr/local/bin/terraform..."
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

echo "[INFO] 3/6 Installing Infisical CLI..."
if ! command -v infisical >/dev/null 2>&1; then
  curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash
  apt-get update
  apt-get install -y infisical
fi
echo "[OK] Infisical CLI: $(infisical --version 2>&1 | head -n 1)"

echo "[INFO] 4/6 Installing Ansible Galaxy collections to /usr/share/ansible/collections..."
install -d -m 0755 /usr/share/ansible/collections
ansible-galaxy collection install \
  -r "${REPO_ROOT}/ansible/requirements.yml" \
  -p /usr/share/ansible/collections \
  --force

echo "[INFO] 5/6 Applying OS Privilege Split (/srv/haytham-homelab, homelab-ops, homelab-agent)..."
bash "${SCRIPT_DIR}/setup-privilege-split.sh"

echo "[INFO] 6/6 Applying strict UFW egress & kernel UID LAN-block..."
bash "${REPO_ROOT}/scripts/hardening/harden-control-node-ufw.sh"

cat <<'DONE_EOF'

====================================================================
CONTROL NODE BOOTSTRAP COMPLETE — TAKE GOLDEN SNAPSHOT NOW!
====================================================================
1. Shut down or pause devbox and take a VMware Snapshot named:
     clean-base
   (BEFORE restoring any secrets into /var/lib/haytham-ops/!)
2. Verify VMware settings:
     - Network Adapter  : NAT (VMnet8)
     - Shared Folders   : Disabled
     - Drag & Drop      : Disabled
     - Copy & Paste     : Disabled (or Host->Guest only)
     - USB Auto-Connect : Disabled
3. After taking `clean-base`, restore your encrypted state bundle
   as human operator:
     sudo -iu homelab-ops
     ops-bundle unpack /path/to/haytham-control-bundle-*.tar.age
4. Launch Antigravity (`agy`) ONLY as user `homelab-agent` inside
   `/srv/haytham-homelab`.
====================================================================
DONE_EOF
