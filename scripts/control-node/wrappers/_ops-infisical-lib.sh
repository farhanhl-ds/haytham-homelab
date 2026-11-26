#!/usr/bin/env bash
# Shared internal library sourced by /usr/local/libexec/haytham-ops/ops-* wrappers.
# Owned root:root 0755 (immutable to both homelab-agent and homelab-ops).

set -euo pipefail

OPS_STATE_DIR="${OPS_STATE_DIR:-/var/lib/haytham-ops}"
OPS_REPO_DIR="${OPS_REPO_DIR:-/srv/haytham-homelab}"
OPS_AUDIT_LOG="${OPS_AUDIT_LOG:-/var/log/haytham-ops/audit.log}"
OPS_INFISICAL_ENV="${OPS_STATE_DIR}/infisical-ops.env"
OPS_SSH_KEY="${OPS_STATE_DIR}/.ssh/id_ed25519_control"

OPS_SHM_SECRETS_FILE=""
OPS_EPHEMERAL_AGENT_PID=""

audit_log() {
  local action="$1"
  local detail="${2:-}"
  local ts caller
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  caller="${SUDO_USER:-$(id -un)}"
  if [[ -w "${OPS_AUDIT_LOG}" ]]; then
    printf '%s caller=%s euid=%s action=%s detail=%s\n' \
      "${ts}" "${caller}" "$(id -un)" "${action}" "${detail}" >> "${OPS_AUDIT_LOG}"
  fi
}

require_ops_user() {
  if [[ "$(id -un)" != "homelab-ops" ]]; then
    echo "[ERROR] Must run as 'homelab-ops' (use sudo -u homelab-ops or sudo -iu homelab-ops)." >&2
    exit 1
  fi
}

require_human_tty() {
  require_ops_user
  if [[ "${SUDO_USER:-}" == "homelab-agent" ]]; then
    echo "[ERROR] homelab-agent is strictly forbidden from running mutating operations." >&2
    exit 1
  fi
  if [[ ! -t 0 ]]; then
    echo "[ERROR] Mutating operation requires an interactive human terminal (TTY)." >&2
    exit 1
  fi
}

cleanup_ephemeral_resources() {
  if [[ -n "${OPS_SHM_SECRETS_FILE}" && -f "${OPS_SHM_SECRETS_FILE}" ]]; then
    shred -u -z "${OPS_SHM_SECRETS_FILE}" 2>/dev/null || rm -f "${OPS_SHM_SECRETS_FILE}"
  fi
  if [[ -n "${OPS_EPHEMERAL_AGENT_PID}" ]]; then
    kill "${OPS_EPHEMERAL_AGENT_PID}" 2>/dev/null || true
  fi
}

start_ephemeral_ssh_agent() {
  if [[ ! -f "${OPS_SSH_KEY}" ]]; then
    echo "[ERROR] Control-node SSH private key not found: ${OPS_SSH_KEY}" >&2
    exit 1
  fi
  eval "$(ssh-agent -s)" >/dev/null
  OPS_EPHEMERAL_AGENT_PID="${SSH_AGENT_PID}"
  ssh-add "${OPS_SSH_KEY}" 2>/dev/null
}

load_infisical_config() {
  if [[ ! -f "${OPS_INFISICAL_ENV}" ]]; then
    echo "[ERROR] Missing ${OPS_INFISICAL_ENV}. Configure read-only Machine Identity homelab-ops-ro first." >&2
    exit 1
  fi
  # Parse strictly allowlisted keys without sourcing arbitrary shell code
  INFISICAL_API_URL="$(awk -F= '/^INFISICAL_API_URL=/ {sub(/^[^=]*=/,""); print; exit}' "${OPS_INFISICAL_ENV}")"
  INFISICAL_PROJECT_ID="$(awk -F= '/^INFISICAL_PROJECT_ID=/ {sub(/^[^=]*=/,""); print; exit}' "${OPS_INFISICAL_ENV}")"
  INFISICAL_ENV="$(awk -F= '/^INFISICAL_ENV=/ {sub(/^[^=]*=/,""); print; exit}' "${OPS_INFISICAL_ENV}")"
  INFISICAL_CLIENT_ID="$(awk -F= '/^INFISICAL_CLIENT_ID=/ {sub(/^[^=]*=/,""); print; exit}' "${OPS_INFISICAL_ENV}")"
  INFISICAL_CLIENT_SECRET="$(awk -F= '/^INFISICAL_CLIENT_SECRET=/ {sub(/^[^=]*=/,""); print; exit}' "${OPS_INFISICAL_ENV}")"

  for v in INFISICAL_API_URL INFISICAL_PROJECT_ID INFISICAL_ENV INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET; do
    if [[ -z "${!v}" ]]; then
      echo "[ERROR] Missing required key '${v}' in ${OPS_INFISICAL_ENV}." >&2
      exit 1
    fi
  done
}

infisical_get_token() {
  load_infisical_config
  infisical login \
    --method=universal-auth \
    --domain="${INFISICAL_API_URL}" \
    --client-id="${INFISICAL_CLIENT_ID}" \
    --client-secret="${INFISICAL_CLIENT_SECRET}" \
    --plain \
    --silent
}

# Exports ONLY allowlisted Terraform secrets (/terraform) into memory env vars
infisical_export_terraform_env() {
  local token raw_json
  token="$(infisical_get_token)"
  raw_json="$(infisical export \
    --domain="${INFISICAL_API_URL}" \
    --token="${token}" \
    --projectId="${INFISICAL_PROJECT_ID}" \
    --env="${INFISICAL_ENV}" \
    --path="/terraform" \
    --format=json)"

  TF_VAR_pve_api_token="$(printf '%s' "${raw_json}" | jq -r '.[] | select(.key == "TF_VAR_pve_api_token") | .value' | head -n 1)"
  TF_VAR_ct_root_password="$(printf '%s' "${raw_json}" | jq -r '.[] | select(.key == "TF_VAR_ct_root_password") | .value' | head -n 1)"

  if [[ -z "${TF_VAR_pve_api_token}" || -z "${TF_VAR_ct_root_password}" ]]; then
    echo "[ERROR] Required Terraform secrets (TF_VAR_pve_api_token, TF_VAR_ct_root_password) missing in Infisical path '/terraform'." >&2
    exit 1
  fi
  export TF_VAR_pve_api_token TF_VAR_ct_root_password
}

# Fetches one or more Infisical folder paths into a RAM-only /dev/shm JSON file
# (mode 0600, shredded on trap EXIT) for Ansible `-e @file`.
infisical_export_ansible_shm() {
  local paths=("$@")
  local token merged_json path_json p
  token="$(infisical_get_token)"
  merged_json="{}"

  for p in "${paths[@]}"; do
    path_json="$(infisical export \
      --domain="${INFISICAL_API_URL}" \
      --token="${token}" \
      --projectId="${INFISICAL_PROJECT_ID}" \
      --env="${INFISICAL_ENV}" \
      --path="${p}" \
      --format=json)"
    merged_json="$(printf '%s\n%s\n' "${merged_json}" "${path_json}" \
      | jq -s '.[0] + ((.[1] // []) | map({(.key): .value}) | add // {})')"
  done

  umask 077
  OPS_SHM_SECRETS_FILE="$(mktemp /dev/shm/haytham-sec.XXXXXX.json)"
  chmod 0600 "${OPS_SHM_SECRETS_FILE}"
  printf '%s\n' "${merged_json}" > "${OPS_SHM_SECRETS_FILE}"
}
