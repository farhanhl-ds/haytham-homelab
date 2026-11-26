#!/usr/bin/env bash
set -euo pipefail

# Layer 3 Hardening — OS Privilege Split (`homelab-agent` vs `homelab-ops`)
#
# Establishes a hard Linux UID/GID security boundary on `haytham-ctl`:
#   - `homelab-ops`   : Human-gated operator account owning `/var/lib/haytham-ops/` (0700)
#                       (Infisical RO Machine Identity, terraform.tfstate, non-secret tfvars,
#                        revocable control SSH key, wildcard SSL cert).
#   - `homelab-agent` : Unprivileged AI agent account (ZERO sudo, ZERO lxd, ZERO adm,
#                       ZERO docker, ZERO secret access, kernel-blocked from 192.168.0.0/16).
#   - `/srv/haytham-homelab` : Shared Git workspace (homelab-ops:homelab-repo, 2775).
#   - `/usr/local/libexec/haytham-ops/` : Immutable root-owned wrapper scripts.
#   - `/etc/sudoers.d/haytham-agent`    : Allows homelab-agent ONLY the 3 read-only wrappers.
#
# Run as root on `haytham-ctl` (Ubuntu 24.04).

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo $0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_SRC="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REPO_GROUP="${REPO_GROUP:-homelab-repo}"
OPS_USER="${OPS_USER:-homelab-ops}"
AGENT_USER="${AGENT_USER:-homelab-agent}"
HUMAN_USER="${HUMAN_USER:-${SUDO_USER:-farhan}}"

REPO_DST="${REPO_DST:-/srv/haytham-homelab}"
OPS_STATE_DIR="/var/lib/haytham-ops"
WRAPPER_DST="/usr/local/libexec/haytham-ops"
AUDIT_LOG_DIR="/var/log/haytham-ops"
SUDOERS_FILE="/etc/sudoers.d/haytham-agent"

echo "[INFO] Creating group '${REPO_GROUP}' and split users '${OPS_USER}' & '${AGENT_USER}'..."
getent group "${REPO_GROUP}" >/dev/null || groupadd "${REPO_GROUP}"

if ! id -u "${OPS_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups "${REPO_GROUP}" "${OPS_USER}"
  # Lock password login for homelab-ops; human enters via `sudo -iu homelab-ops`
  passwd -l "${OPS_USER}" >/dev/null 2>&1 || true
else
  usermod -aG "${REPO_GROUP}" "${OPS_USER}"
fi

if ! id -u "${AGENT_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --groups "${REPO_GROUP}" "${AGENT_USER}"
else
  # Enforce strict minimal group membership (strip sudo/lxd/docker/adm if ever added)
  usermod -G "${REPO_GROUP}" "${AGENT_USER}"
fi

if id -u "${HUMAN_USER}" >/dev/null 2>&1; then
  usermod -aG "${REPO_GROUP}" "${HUMAN_USER}"
fi

echo "[INFO] Initializing secret & state vault at ${OPS_STATE_DIR} (0700 ${OPS_USER}:${OPS_USER})..."
install -d -m 0700 -o "${OPS_USER}" -g "${OPS_USER}" \
  "${OPS_STATE_DIR}" \
  "${OPS_STATE_DIR}/.ssh" \
  "${OPS_STATE_DIR}/plans" \
  "${OPS_STATE_DIR}/homelab-cert"

if [[ ! -f "${OPS_STATE_DIR}/infisical-ops.env.example" ]]; then
  cat > "${OPS_STATE_DIR}/infisical-ops.env.example" <<'ENVEOF'
# Copy to /var/lib/haytham-ops/infisical-ops.env (chmod 0600, owner homelab-ops:homelab-ops)
# Credentials belong to the READ-ONLY Machine Identity `homelab-ops-ro` in Zone 1 Infisical (CT 110).
INFISICAL_API_URL=http://192.168.100.10:8080/api
INFISICAL_PROJECT_ID=<your-haytham-homelab-project-id>
INFISICAL_ENV=prod
INFISICAL_CLIENT_ID=<homelab-ops-ro-universal-auth-client-id>
INFISICAL_CLIENT_SECRET=<homelab-ops-ro-universal-auth-client-secret>
ENVEOF
  chown "${OPS_USER}:${OPS_USER}" "${OPS_STATE_DIR}/infisical-ops.env.example"
  chmod 0600 "${OPS_STATE_DIR}/infisical-ops.env.example"
fi

echo "[INFO] Setting up shared Git workspace at ${REPO_DST}..."
if [[ ! -d "${REPO_DST}" ]]; then
  cp -a "${REPO_SRC}" "${REPO_DST}"
fi
chown -R "${OPS_USER}:${REPO_GROUP}" "${REPO_DST}"
find "${REPO_DST}" -type d -exec chmod 2775 {} +
find "${REPO_DST}" -type f -exec chmod g+rw {} +
git config --system --add safe.directory "${REPO_DST}" || true
git -C "${REPO_DST}" config core.sharedRepository group || true

# Safety check: ensure no secrets live inside the agent-readable git workspace
for forbidden in \
  "${REPO_DST}/ansible/.vault_pass" \
  "${REPO_DST}/terraform/terraform.tfvars" \
  "${REPO_DST}/terraform/terraform.tfstate" \
  "${REPO_DST}/terraform/terraform.tfstate.backup"; do
  if [[ -e "${forbidden}" ]]; then
    echo "[WARN] Sensitive file detected inside agent-readable workspace: ${forbidden}"
    echo "       Move it into ${OPS_STATE_DIR}/ (0600 ${OPS_USER}) immediately!"
  fi
done

echo "[INFO] Installing immutable root-owned wrappers to ${WRAPPER_DST}..."
install -d -m 0755 -o root -g root "${WRAPPER_DST}"
for f in \
  _ops-infisical-lib.sh \
  ops-tf-plan \
  ops-tf-apply \
  ops-ansible-check \
  ops-ansible-apply \
  ops-health-check; do
  install -m 0755 -o root -g root "${SCRIPT_DIR}/wrappers/${f}" "${WRAPPER_DST}/${f}"
done
install -m 0755 -o root -g root "${SCRIPT_DIR}/ops-bundle.sh" "${WRAPPER_DST}/ops-bundle"

# Expose convenience symlinks for human `homelab-ops` PATH
ln -sf "${WRAPPER_DST}/ops-tf-plan"       /usr/local/bin/ops-tf-plan
ln -sf "${WRAPPER_DST}/ops-tf-apply"      /usr/local/bin/ops-tf-apply
ln -sf "${WRAPPER_DST}/ops-ansible-check" /usr/local/bin/ops-ansible-check
ln -sf "${WRAPPER_DST}/ops-ansible-apply" /usr/local/bin/ops-ansible-apply
ln -sf "${WRAPPER_DST}/ops-health-check"  /usr/local/bin/ops-health-check
ln -sf "${WRAPPER_DST}/ops-bundle"        /usr/local/bin/ops-bundle

echo "[INFO] Initializing audit log at ${AUDIT_LOG_DIR}/audit.log..."
install -d -m 0750 -o "${OPS_USER}" -g adm "${AUDIT_LOG_DIR}"
touch "${AUDIT_LOG_DIR}/audit.log"
chown "${OPS_USER}:adm" "${AUDIT_LOG_DIR}/audit.log"
chmod 0640 "${AUDIT_LOG_DIR}/audit.log"

echo "[INFO] Writing & validating scoped sudoers policy at ${SUDOERS_FILE}..."
TMP_SUDOERS="$(mktemp)"
cat > "${TMP_SUDOERS}" <<EOF
# Haytham Homelab — Zero-Trust AI Agent Sudoers Policy (ADR-008)
# ${AGENT_USER} may invoke ONLY the 3 read-only / dry-run wrappers as ${OPS_USER}.
# Mutating & secret operations (ops-tf-apply, ops-ansible-apply, ops-bundle) are
# deliberately EXCLUDED and require human login via 'sudo -iu ${OPS_USER}'.

Defaults:${AGENT_USER} !requiretty, env_reset, secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
${AGENT_USER} ALL=(${OPS_USER}) NOPASSWD: \\
    ${WRAPPER_DST}/ops-tf-plan, \\
    ${WRAPPER_DST}/ops-ansible-check *, \\
    ${WRAPPER_DST}/ops-health-check
EOF

visudo -cf "${TMP_SUDOERS}"
install -m 0440 -o root -g root "${TMP_SUDOERS}" "${SUDOERS_FILE}"
rm -f "${TMP_SUDOERS}"

echo ""
echo "[OK] OS Privilege Split configured successfully:"
echo "     - Agent user   : ${AGENT_USER} (groups: $(id -nG "${AGENT_USER}"))"
echo "     - Ops user     : ${OPS_USER} (vault: ${OPS_STATE_DIR}, mode 0700)"
echo "     - Shared repo  : ${REPO_DST}"
echo "     - Wrappers     : ${WRAPPER_DST} (root:root 0755)"
echo "     - Audit log    : ${AUDIT_LOG_DIR}/audit.log"
