#!/usr/bin/env bash
set -euo pipefail

# Zone 1 Immutable Core Bootstrap — Self-Hosted Infisical (CT 110 / 192.168.100.10)
#
# Run ONCE directly on Proxmox host `haytham` (192.168.100.2) as `root`
# (from your Windows Break-Glass SSH session or Proxmox Web Console).
#
# Architectural invariants (ADR-008):
#   - CT 110 is COMPLETELY OUTSIDE Terraform state and ACLs (pool: homelab-immutable).
#   - `protection=1` is enabled permanently on Proxmox hypervisor.
#   - Only the Windows Break-Glass SSH public key is baked into CT 110
#     (control node `homelab-ops` has ZERO SSH access to CT 110).
#   - Uses public DNS (1.1.1.1) to prevent circular dependency on Zone 3 Pi-hole (.30).
#   - Tuned lean for 8 GB host (~600-900 MB RSS idle; 1536 MB cap + 1024 MB swap).
#
# Usage:
#   ./bootstrap-infisical.sh /root/windows_breakglass.pub

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root directly on Proxmox host haytham (192.168.100.2)." >&2
  exit 1
fi

if ! command -v pct >/dev/null 2>&1 || ! command -v pveum >/dev/null 2>&1; then
  echo "[ERROR] Proxmox CLI tools (pct, pveum) not found. Run this on haytham, not haytham-ctl." >&2
  exit 1
fi

BREAKGLASS_PUBKEY="${1:-${BREAKGLASS_PUBKEY_FILE:-}}"
if [[ -z "$BREAKGLASS_PUBKEY" || ! -f "$BREAKGLASS_PUBKEY" ]]; then
  echo "Usage: $0 <path-to-windows-breakglass-id_ed25519.pub>" >&2
  echo "  NOTE: Pass ONLY your Windows-only Break-Glass SSH public key (NOT haytham-ctl's key)." >&2
  exit 1
fi

CTID="110"
HOSTNAME="infisical"
IP_CIDR="192.168.100.10/24"
IP_ONLY="192.168.100.10"
GATEWAY="192.168.100.1"
DNS_SERVER="1.1.1.1"
POOL="homelab-immutable"
STORAGE="local-lvm"
TEMPLATE="${PVE_UBUNTU_TEMPLATE:-local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
INFISICAL_IMAGE="${INFISICAL_IMAGE:-infisical/infisical:v0.104.0-postgres}"

if pct status "$CTID" >/dev/null 2>&1; then
  echo "[INFO] CT ${CTID} (${HOSTNAME}) already exists. Refusing to overwrite immutable Zone 1 container."
  pct config "$CTID" | grep -E '^(hostname|net0|memory|swap|protection|tags):' || true
  exit 0
fi

# Verify Ubuntu 24.04 template exists on Proxmox storage
if ! pveam list local 2>/dev/null | grep -q "$(basename "${TEMPLATE#local:vztmpl/}")"; then
  echo "[ERROR] Template '${TEMPLATE}' not found in Proxmox 'local' storage." >&2
  echo "        Download it via Proxmox GUI: Datacenter -> haytham -> local -> CT Templates." >&2
  exit 1
fi

# Ensure immutable pool exists
if ! pvesh get "/pools/${POOL}" >/dev/null 2>&1; then
  echo "[INFO] Creating Proxmox resource pool '${POOL}'..."
  pvesh create /pools --poolid "${POOL}" --comment "Zone 1 Immutable Core (outside Terraform, ZERO terraform@pve ACL)"
fi

echo "[INFO] Creating Zone 1 Immutable LXC CT ${CTID} (${HOSTNAME} @ ${IP_ONLY})..."
pct create "${CTID}" "${TEMPLATE}" \
  --hostname "${HOSTNAME}" \
  --description "Zone 1 Immutable Core - Self-Hosted Infisical (Out-of-Band, NEVER in Terraform)" \
  --pool "${POOL}" \
  --cores 2 \
  --memory 1536 \
  --swap 1024 \
  --rootfs "${STORAGE}:8" \
  --net0 "name=eth0,bridge=vmbr0,ip=${IP_CIDR},gw=${GATEWAY}" \
  --nameserver "${DNS_SERVER}" \
  --unprivileged 1 \
  --features "nesting=1" \
  --onboot 1 \
  --ssh-public-keys "${BREAKGLASS_PUBKEY}" \
  --tags "zone1-immutable;secrets"

echo "[INFO] Starting CT ${CTID}..."
pct start "${CTID}"

# Wait for network inside container
for _ in $(seq 1 30); do
  if pct exec "${CTID}" -- bash -c "ip -4 addr show eth0 | grep -q '${IP_ONLY}'" 2>/dev/null; then
    break
  fi
  sleep 2
done

echo "[INFO] Installing Docker Engine + Compose plugin inside CT ${CTID}..."
pct exec "${CTID}" -- bash -euo pipefail -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y ca-certificates curl gnupg openssl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
'

echo "[INFO] Generating Infisical secrets & deploying lean Docker Compose stack..."
pct exec "${CTID}" -- env INFISICAL_IMAGE="${INFISICAL_IMAGE}" IP_ONLY="${IP_ONLY}" bash -euo pipefail -c '
  mkdir -p /opt/infisical
  chmod 0700 /opt/infisical

  if [[ ! -f /opt/infisical/.env ]]; then
    ENC_KEY="$(openssl rand -hex 16)"
    AUTH_SEC="$(openssl rand -base64 32)"
    PG_PASS="$(openssl rand -base64 24 | tr -dc "a-zA-Z0-9" | head -c 24)"
    REDIS_PASS="$(openssl rand -base64 24 | tr -dc "a-zA-Z0-9" | head -c 24)"

    cat > /opt/infisical/.env <<ENVEOF
# Zone 1 Immutable Infisical (CT 110) — BACK UP ENCRYPTION_KEY & AUTH_SECRET OFFLINE!
ENCRYPTION_KEY=${ENC_KEY}
AUTH_SECRET=${AUTH_SEC}
POSTGRES_USER=infisical
POSTGRES_PASSWORD=${PG_PASS}
POSTGRES_DB=infisical
DB_CONNECTION_URI=postgres://infisical:${PG_PASS}@db:5432/infisical
REDIS_PASSWORD=${REDIS_PASS}
REDIS_URL=redis://:${REDIS_PASS}@redis:6379
SITE_URL=http://${IP_ONLY}:8080
TELEMETRY_ENABLED=false
NODE_OPTIONS=--max-old-space-size=512
ENVEOF
    chmod 0600 /opt/infisical/.env
  fi

  cat > /opt/infisical/docker-compose.yml <<COMPOSEEOF
services:
  db:
    image: postgres:16-alpine
    container_name: infisical_postgres
    restart: unless-stopped
    command:
      - postgres
      - -c
      - shared_buffers=64MB
      - -c
      - max_connections=50
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 10

  redis:
    image: redis:7-alpine
    container_name: infisical_redis
    restart: unless-stopped
    command:
      - redis-server
      - --requirepass
      - \${REDIS_PASSWORD}
      - --maxmemory
      - 64mb
      - --maxmemory-policy
      - allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD-SHELL", "redis-cli -a \${REDIS_PASSWORD} ping | grep -q PONG"]
      interval: 10s
      timeout: 5s
      retries: 10

  backend:
    image: ${INFISICAL_IMAGE}
    container_name: infisical_backend
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    env_file:
      - /opt/infisical/.env
    ports:
      - "8080:8080"

volumes:
  pg_data:
  redis_data:
COMPOSEEOF

  cd /opt/infisical
  docker compose up -d
'

echo "[INFO] Enabling permanent Proxmox hypervisor protection on CT ${CTID}..."
pct set "${CTID}" --protection 1

echo "[INFO] Waiting for Infisical API health endpoint (http://${IP_ONLY}:8080/api/status)..."
HEALTHY=0
for _ in $(seq 1 45); do
  if curl -fsS --max-time 3 "http://${IP_ONLY}:8080/api/status" >/dev/null 2>&1; then
    HEALTHY=1
    break
  fi
  sleep 2
done

if [[ "$HEALTHY" -eq 1 ]]; then
  echo "[OK] Zone 1 Infisical (CT ${CTID}) is UP and protected (protection=1)."
else
  echo "[WARN] Infisical is still starting; check logs with: pct exec ${CTID} -- docker logs infisical_backend"
fi

cat <<NEXTEOF

====================================================================
NEXT STEPS (HUMAN OPERATOR — FROM WINDOWS PC)
====================================================================
1. Open http://${IP_ONLY}:8080 in your Windows browser and create
   your Admin account (enable MFA/2FA if desired).
2. Create Project: "haytham-homelab" (Environment: "prod").
3. Create folders inside "prod" and populate secrets:
     /terraform -> TF_VAR_pve_api_token, TF_VAR_ct_root_password
     /proxmox   -> vault_restic_password
     /zone2     -> vault_vaultwarden_admin_token, vault_immich_db_password
     /zone3     -> vault_pihole_webpassword, vault_tailscale_authkey
4. Create a READ-ONLY Machine Identity named "homelab-ops-ro"
   (Universal Auth) granted Viewer/Read-Only access ONLY to project
   "haytham-homelab" (prod). Copy Client ID & Client Secret into
   /var/lib/haytham-ops/infisical-ops.env on haytham-ctl (0600 homelab-ops).
5. CRITICAL DR STEP: Record ENCRYPTION_KEY and AUTH_SECRET from
   \`pct exec ${CTID} -- grep -E '^(ENCRYPTION_KEY|AUTH_SECRET)=' /opt/infisical/.env\`
   into your offline emergency sheet / Windows KeePassXC (NEVER paste in chat!).
6. Run scripts/proxmox/harden-pve-rbac.sh --init && --lock on haytham.
====================================================================
NEXTEOF
