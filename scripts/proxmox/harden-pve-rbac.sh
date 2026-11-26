#!/usr/bin/env bash
set -euo pipefail

# Layer 2 Hardening — Proxmox Hypervisor RBAC, Resource Pools & protection=1
#
# Run as `root` directly on Proxmox host `haytham` (192.168.100.2) via
# Windows Break-Glass SSH or Proxmox Web Console.
#
# Security-Zone Pool Model (ID = 100 + last_octet, ADR-008):
#   - Zone 0 (VM 103 HAOS, VMs 104-109) : Unassigned / Out-of-Band -> ZERO terraform@pve ACL
#   - Zone 1 (CT 110 Infisical)         : Pool `homelab-immutable`  -> ZERO terraform@pve ACL + protection=1
#   - Zone 2 (CT 120 Vaultwarden, 121 Immich, 122-129)
#                                       : Pool `homelab-protected`  -> `HomelabProtectedOps` (NO destroy, NO unprotect) + protection=1
#   - Zones 3-5 (CT 130-159)            : Pool `homelab-ephemeral`  -> `PVEVMAdmin` (freely rebuildable)
#
# Usage:
#   ./harden-pve-rbac.sh --init
#   ./harden-pve-rbac.sh --lock
#   ./harden-pve-rbac.sh --unlock-dr <zone2-ctid>   # ONLY accepts 120..129
#   ./harden-pve-rbac.sh --status

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root directly on Proxmox host haytham (192.168.100.2)." >&2
  exit 1
fi

for bin in pveum pvesh pct; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] Missing Proxmox binary '$bin'. Run this on haytham, not haytham-ctl." >&2
    exit 1
  fi
done

TF_USER="terraform@pve"
ROLE_PROTECTED="HomelabProtectedOps"
# Read + power + non-destructive resource tuning ONLY.
# Deliberately OMITS VM.Allocate (destroy/create) and VM.Config.Options (toggle protection=0).
ROLE_PRIVS="VM.Audit,VM.PowerMgmt,VM.Config.CPU,VM.Config.Memory,VM.Config.Disk,VM.Config.Network,VM.Console"

POOL_IMMUTABLE="homelab-immutable"
POOL_PROTECTED="homelab-protected"
POOL_EPHEMERAL="homelab-ephemeral"

ZONE1_CTIDS=(110)
ZONE2_CTIDS=(120 121 122 123)
EPHEMERAL_CTIDS=(130 131 132 133 140 141 142)

ensure_pool() {
  local pool="$1"
  local comment="$2"
  if ! pvesh get "/pools/${pool}" >/dev/null 2>&1; then
    echo "[INFO] Creating pool '${pool}'..."
    pvesh create /pools --poolid "${pool}" --comment "${comment}"
  fi
}

assign_ct_to_pool() {
  local pool="$1"
  local ctid="$2"
  if pct status "$ctid" >/dev/null 2>&1; then
    echo "[INFO] Assigning CT ${ctid} -> pool '${pool}'..."
    pvesh set "/pools/${pool}" --vms "${ctid}" --allow-move 1 2>/dev/null || true
  fi
}

cmd_init() {
  echo "[INFO] Initializing Security-Zone resource pools & custom role..."
  ensure_pool "$POOL_IMMUTABLE" "Zone 1 Immutable Core (Infisical CT 110; outside Terraform, ZERO ACL)"
  ensure_pool "$POOL_PROTECTED" "Zone 2 Protected Data (Vaultwarden 120, Immich 121; protection=1, NO destroy)"
  ensure_pool "$POOL_EPHEMERAL" "Zones 3-5 Ephemeral Infra/Apps/Ops (130-159; freely rebuildable)"

  if pveum role list 2>/dev/null | grep -q "${ROLE_PROTECTED}"; then
    pveum role modify "${ROLE_PROTECTED}" -privs "${ROLE_PRIVS}"
  else
    pveum role add "${ROLE_PROTECTED}" -privs "${ROLE_PRIVS}"
  fi
  echo "[OK] Role '${ROLE_PROTECTED}' configured with non-destructive privileges."

  for ctid in "${ZONE1_CTIDS[@]}"; do assign_ct_to_pool "$POOL_IMMUTABLE" "$ctid"; done
  for ctid in "${ZONE2_CTIDS[@]}"; do assign_ct_to_pool "$POOL_PROTECTED" "$ctid"; done
  for ctid in "${EPHEMERAL_CTIDS[@]}"; do assign_ct_to_pool "$POOL_EPHEMERAL" "$ctid"; done

  echo "[OK] --init complete. Next: run '$0 --lock' after initial Zone 2 creation."
}

cmd_lock() {
  echo "[INFO] Locking Proxmox RBAC & hypervisor protection flags (steady-state)..."

  # Verify pools and custom role exist
  cmd_init >/dev/null

  # 1. Strip broad PVEVMAdmin from root '/' and from protected/immutable pools
  pveum acl delete / -user "${TF_USER}" -role PVEVMAdmin 2>/dev/null || true
  pveum acl delete "/pool/${POOL_PROTECTED}" -user "${TF_USER}" -role PVEVMAdmin 2>/dev/null || true
  pveum acl delete "/pool/${POOL_IMMUTABLE}" -user "${TF_USER}" -role PVEVMAdmin 2>/dev/null || true
  pveum acl delete "/pool/${POOL_IMMUTABLE}" -user "${TF_USER}" -role "${ROLE_PROTECTED}" 2>/dev/null || true

  # 2. Retain minimal baseline privileges required by bpg/proxmox
  pveum aclmod / -user "${TF_USER}" -role PVEAuditor
  pveum aclmod /sdn/zones/localnetwork -user "${TF_USER}" -role PVESDNUser
  pveum aclmod /storage/local -user "${TF_USER}" -role PVEDatastoreUser
  pveum aclmod /storage/local-lvm -user "${TF_USER}" -role PVEDatastoreUser

  # 3. Grant scoped pool ACLs (Zone 1 & Zone 0 VM 103 deliberately get ZERO ACL!)
  pveum aclmod "/pool/${POOL_EPHEMERAL}" -user "${TF_USER}" -role PVEVMAdmin
  pveum aclmod "/pool/${POOL_PROTECTED}" -user "${TF_USER}" -role "${ROLE_PROTECTED}"

  # 4. Enforce hypervisor protection=1 on Zone 1 (110) and all existing Zone 2 CTs (120-129)
  for ctid in "${ZONE1_CTIDS[@]}" "${ZONE2_CTIDS[@]}"; do
    if pct status "$ctid" >/dev/null 2>&1; then
      echo "[INFO] Setting protection=1 on CT ${ctid}..."
      pct set "$ctid" --protection 1
    fi
  done

  echo "[OK] Proxmox RBAC LOCKED:"
  echo "     - Zone 0 (VM 103 HAOS)      : ZERO ACL (HTTP 403)"
  echo "     - Zone 1 (CT 110 Infisical) : ZERO ACL + protection=1 (HTTP 403)"
  echo "     - Zone 2 (CT 120, 121)      : ${ROLE_PROTECTED} + protection=1 (NO destroy/unprotect)"
  echo "     - Zones 3-5 (CT 130-159)    : PVEVMAdmin on /pool/${POOL_EPHEMERAL}"
}

cmd_unlock_dr() {
  local ctid="${1:-}"
  if [[ ! "$ctid" =~ ^12[0-9]$ ]]; then
    echo "[ERROR] --unlock-dr accepts ONLY Zone 2 CTIDs (120-129). Refusing '${ctid}'." >&2
    echo "        Zone 1 (CT 110 Infisical) and Zone 0 (VM 103 HAOS) are NEVER unlocked for Terraform." >&2
    exit 1
  fi

  if [[ ! -t 0 ]]; then
    echo "[ERROR] --unlock-dr requires an interactive human terminal (TTY)." >&2
    exit 1
  fi

  echo "===================================================================="
  echo "  BREAK-GLASS DR UNLOCK — Zone 2 Protected Container CT ${ctid}"
  echo "===================================================================="
  echo "  Before proceeding, verify Track 1 (restic) & Track 2 (Windows pull)"
  echo "  backups are up to date!"
  echo ""
  read -r -p "Type 'UNLOCK-${ctid}' to confirm temporary DR unlock: " confirm
  if [[ "$confirm" != "UNLOCK-${ctid}" ]]; then
    echo "[ABORTED] Confirmation did not match."
    exit 1
  fi

  if pct status "$ctid" >/dev/null 2>&1; then
    pct set "$ctid" --protection 0
  fi
  pveum aclmod "/pool/${POOL_PROTECTED}" -user "${TF_USER}" -role PVEVMAdmin

  echo ""
  echo "[WARN] CT ${ctid} is UNLOCKED and '${TF_USER}' temporarily has PVEVMAdmin on /pool/${POOL_PROTECTED}."
  echo "[MANDATORY] Immediately after DR apply/restore finishes, run:"
  echo "            $0 --lock"
}

cmd_status() {
  echo "=== Proxmox ACLs for ${TF_USER} ==="
  pveum acl list | grep -E "path|${TF_USER}" || true
  echo ""
  echo "=== Resource Pools ==="
  for pool in "$POOL_IMMUTABLE" "$POOL_PROTECTED" "$POOL_EPHEMERAL"; do
    echo "--- Pool: ${pool} ---"
    pvesh get "/pools/${pool}" 2>/dev/null | grep -E 'vmid|type|status' || echo "  (not created yet)"
  done
  echo ""
  echo "=== Hypervisor Protection Flags ==="
  for ctid in 110 120 121 122 123; do
    if pct status "$ctid" >/dev/null 2>&1; then
      prot="$(pct config "$ctid" | awk '/^protection:/ {print $2}')"
      echo "  CT ${ctid}: protection=${prot:-0}"
    fi
  done
  if qm status 103 >/dev/null 2>&1; then
    prot="$(qm config 103 | awk '/^protection:/ {print $2}')"
    echo "  VM 103 (HAOS): protection=${prot:-0}"
  fi
}

case "${1:-}" in
  --init)      cmd_init ;;
  --lock)      cmd_lock ;;
  --unlock-dr) cmd_unlock_dr "${2:-}" ;;
  --status)    cmd_status ;;
  *)
    echo "Usage: $0 {--init | --lock | --unlock-dr <120-129> | --status}" >&2
    exit 1
    ;;
esac
