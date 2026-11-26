#!/usr/bin/env bash
set -euo pipefail

# Layer 4 — Encrypted Control Node Recovery Bundle (`age -p`)
#
# Human-only utility run as `homelab-ops` (`sudo -iu homelab-ops`) to pack or
# unpack disposable control-node state/config:
#   Included : terraform.tfstate, terraform.tfvars (non-secret), infisical-ops.env,
#              homelab-cert/, .ssh/windows_breakglass.pub
#   EXCLUDED : .ssh/id_ed25519_control (private key is NEVER backed up so every
#              control node rebuild generates a fresh revocable SSH keypair!)
#
# Usage:
#   ops-bundle pack   [output-file.tar.age]
#   ops-bundle unpack <input-file.tar.age>

if [[ "$(id -un)" != "homelab-ops" && "${OPS_ALLOW_NON_OPS:-0}" != "1" ]]; then
  echo "[ERROR] ops-bundle must be executed as 'homelab-ops' (sudo -iu homelab-ops)." >&2
  exit 1
fi

if [[ "${SUDO_USER:-}" == "homelab-agent" ]]; then
  echo "[ERROR] homelab-agent is strictly forbidden from invoking ops-bundle." >&2
  exit 1
fi

if ! command -v age >/dev/null 2>&1; then
  echo "[ERROR] 'age' is not installed. Run: sudo apt install age" >&2
  exit 1
fi

STATE_DIR="${OPS_STATE_DIR:-/var/lib/haytham-ops}"

cmd_pack() {
  local ts out_file tmp_tar
  ts="$(date -u +%Y%m%d-%H%M)"
  out_file="${1:-${STATE_DIR}/haytham-control-bundle-${ts}.tar.age}"

  if [[ ! -d "${STATE_DIR}" ]]; then
    echo "[ERROR] State directory ${STATE_DIR} does not exist." >&2
    exit 1
  fi

  local items=()
  for rel in terraform.tfstate terraform.tfvars infisical-ops.env homelab-cert .ssh/windows_breakglass.pub; do
    if [[ -e "${STATE_DIR}/${rel}" ]]; then
      items+=("${rel}")
    fi
  done

  if [[ "${#items[@]}" -eq 0 ]]; then
    echo "[ERROR] No state files found in ${STATE_DIR} to bundle." >&2
    exit 1
  fi

  umask 077
  tmp_tar="$(mktemp /dev/shm/haytham-bundle.XXXXXX.tar.gz)"
  trap 'shred -u -z "${tmp_tar}" 2>/dev/null || rm -f "${tmp_tar}"' EXIT INT TERM

  echo "[INFO] Packing control-node recovery items (EXCLUDING id_ed25519_control private key):"
  printf '       - %s\n' "${items[@]}"

  tar -C "${STATE_DIR}" -czf "${tmp_tar}" "${items[@]}"
  echo "[INFO] Encrypting with age passphrase (-p) -> ${out_file}"
  age -p -o "${out_file}" "${tmp_tar}"
  chmod 0600 "${out_file}"

  echo ""
  echo "[OK] Encrypted recovery bundle created: ${out_file}"
  echo "     SHA-256: $(sha256sum "${out_file}" | awk '{print $1}')"
  echo "[NEXT] Copy this encrypted .tar.age file to your Windows PC + offline USB drive,"
  echo "       then delete the copy from ${STATE_DIR} if you do not want bundles on devbox."
}

cmd_unpack() {
  local in_file="${1:-}"
  if [[ -z "${in_file}" || ! -f "${in_file}" ]]; then
    echo "Usage: ops-bundle unpack <haytham-control-bundle-*.tar.age>" >&2
    exit 1
  fi

  umask 077
  mkdir -p "${STATE_DIR}" "${STATE_DIR}/.ssh" "${STATE_DIR}/plans" "${STATE_DIR}/homelab-cert"
  chmod 0700 "${STATE_DIR}" "${STATE_DIR}/.ssh" "${STATE_DIR}/plans" "${STATE_DIR}/homelab-cert"

  echo "[INFO] Decrypting ${in_file} directly into ${STATE_DIR}..."
  age -d "${in_file}" | tar -C "${STATE_DIR}" -xzf -

  # Enforce strict permissions on restored files
  for f in terraform.tfstate terraform.tfvars infisical-ops.env; do
    [[ -f "${STATE_DIR}/${f}" ]] && chmod 0600 "${STATE_DIR}/${f}"
  done
  [[ -f "${STATE_DIR}/.ssh/windows_breakglass.pub" ]] && chmod 0644 "${STATE_DIR}/.ssh/windows_breakglass.pub"

  # Generate a fresh revocable control-node SSH keypair if absent
  local ctrl_key="${STATE_DIR}/.ssh/id_ed25519_control"
  if [[ ! -f "${ctrl_key}" ]]; then
    echo "[INFO] Generating fresh revocable Control Node SSH keypair (${ctrl_key})..."
    ssh-keygen -t ed25519 -a 64 -N "" -C "homelab-ops@devbox-$(date -u +%Y%m%d)" -f "${ctrl_key}" >/dev/null
    chmod 0600 "${ctrl_key}"
    chmod 0644 "${ctrl_key}.pub"
  fi

  echo ""
  echo "[OK] Control node state restored into ${STATE_DIR}."
  echo "=== NEW CONTROL NODE PUBLIC KEY ==="
  cat "${ctrl_key}.pub"
  echo "==================================="
  echo "[NEXT STEPS — FROM WINDOWS BREAK-GLASS SSH]"
  echo "  1. Authorize the new public key above on haytham (192.168.100.2) and active LXCs"
  echo "     (192.168.100.20, .21, .30, .31, .32, .40, .41) — NEVER on Zone 1 CT 110 Infisical!"
  echo "  2. If rebuilding after a suspected compromise:"
  echo "     a) Remove the old devbox key line from /root/.ssh/authorized_keys on haytham & LXCs."
  echo "     b) Rotate the 'homelab-ops-ro' Machine Identity secret in Infisical UI (http://192.168.100.10:8080)"
  echo "        and update ${STATE_DIR}/infisical-ops.env."
}

case "${1:-}" in
  pack)   cmd_pack "${2:-}" ;;
  unpack) cmd_unpack "${2:-}" ;;
  *)
    echo "Usage: $0 {pack [out.tar.age] | unpack <in.tar.age>}" >&2
    exit 1
    ;;
esac
