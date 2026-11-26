#!/usr/bin/env bash
set -euo pipefail

# Layer 1 Firewall Hardening for Disposable Control Node (`haytham-ctl`)
#
# Enforces two complementary boundaries:
#   1. UFW default-deny incoming & outgoing:
#        - Inbound: ALLOWS ONLY TCP/22 from the Windows host VMnet8 IP (/32) so
#          Windows Terminal can initiate unidirectional SSH/SCP into `haytham-ctl`.
#        - Outbound: ALLOWS ONLY active/deferred Security-Zone homelab endpoints
#          (.2 Proxmox, .10 Zone 1 Infisical, .20-.23 Zone 2, .30-.33 Zone 3,
#           .40-.42 Zone 4) on minimal required ports.
#        - Explicitly DENIES ALL RFC1918 / link-local ranges BEFORE broad
#          public internet rules (53/80/443/123), blocking Router .1, Windows PC,
#          VMnet8 host .1, Zone 5 (.50-.59), Open Reserve (.60-.99), and DHCP (.100-.254).
#   2. Kernel UID-based LAN lockdown (`haytham-agent-egress.service`):
#        - Unconditionally blocks UID `homelab-agent` from contacting ANY
#          RFC1918/link-local IP (zero conntrack exceptions). The AI agent can
#          interact with the homelab ONLY through the 3 audited `sudo -u homelab-ops`
#          read-only wrappers.
#
# Run as root on `haytham-ctl` (Ubuntu 24.04).

if [[ "${EUID}" -ne 0 ]]; then
  echo "[ERROR] Run as root: sudo $0" >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  echo "[ERROR] ufw is not installed. Run bootstrap-control-node.sh or apt install ufw." >&2
  exit 1
fi

AGENT_USER="${AGENT_USER:-homelab-agent}"
LOCK_SCRIPT="/usr/local/sbin/haytham-agent-egress-lock.sh"
LOCK_SERVICE="/etc/systemd/system/haytham-agent-egress.service"

# Detect VMware NAT resolver (e.g., 192.168.x.2) if present in resolv.conf/resolvectl
detect_vmnet_dns() {
  local dns_ip=""
  if command -v resolvectl >/dev/null 2>&1; then
    dns_ip="$(resolvectl status 2>/dev/null | awk '/DNS Servers:/ {print $3; exit}' || true)"
  fi
  if [[ -z "$dns_ip" ]]; then
    dns_ip="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
  fi
  # Only allow VMware NAT resolver if it is a private IP outside 192.168.100.0/24 and not loopback
  if [[ "$dns_ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]] \
     && [[ "$dns_ip" != 192.168.100.* ]] \
     && [[ "$dns_ip" != 127.* ]]; then
    echo "$dns_ip"
  fi
}

VMNET_DNS_IP="${VMNET_DNS_IP:-$(detect_vmnet_dns)}"

# Detect Windows host VMnet8 adapter IP (.1 of VMware NAT default gateway /24, e.g. 192.168.x.2 -> 192.168.x.1)
detect_vmnet_host() {
  local gw_ip=""
  if command -v ip >/dev/null 2>&1; then
    gw_ip="$(ip -4 route show default 2>/dev/null | awk '/^default via / {print $3; exit}' || true)"
  fi
  # Only allow VMware NAT subnets outside the homelab LAN (192.168.100.0/24) and loopback
  if [[ "$gw_ip" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]] \
     && [[ "$gw_ip" != 192.168.100.* ]] \
     && [[ "$gw_ip" != 127.* ]]; then
    echo "${gw_ip%.*}.1"
  fi
}

ALLOW_VMNET_SSH="${ALLOW_VMNET_SSH:-1}"
VMNET_HOST_IP="${VMNET_HOST_IP:-$(detect_vmnet_host)}"

echo "[INFO] Resetting UFW to strict default-deny incoming & outgoing..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default deny outgoing

# ------------------------------------------------------------------
# 0. Explicit INBOUND ALLOW — Windows Terminal SSH via VMnet8 ONLY
#    Unidirectional: Windows initiates TCP/22 -> haytham-ctl; haytham-ctl -> Windows
#    NEW connections remain 100% blocked by UFW egress & Windows Firewall.
# ------------------------------------------------------------------
if [[ "${ALLOW_VMNET_SSH}" == "1" && -n "$VMNET_HOST_IP" ]]; then
  echo "[INFO] Allowing inbound SSH (22/tcp) ONLY from Windows VMnet8 host ${VMNET_HOST_IP}/32"
  ufw allow in proto tcp from "${VMNET_HOST_IP}/32" to any port 22 comment "Windows Terminal SSH via VMnet8"
else
  echo "[WARN] VMnet8 host IP not detected (bridged mode or ALLOW_VMNET_SSH=0); inbound SSH remains blocked."
fi

# ------------------------------------------------------------------
# 1. Explicit ALLOW rules — Homelab Management Plane ONLY
#    (Evaluated top-down BEFORE the RFC1918 DENY block below)
# ------------------------------------------------------------------

# Zone 0: Proxmox host `haytham` (.2) — SSH & Web/REST API
ufw allow out to 192.168.100.2 port 22 proto tcp comment "Proxmox haytham SSH"
ufw allow out to 192.168.100.2 port 8006 proto tcp comment "Proxmox haytham API"

# Zone 1: Immutable Infisical (.10) — Direct API port only (no SSH from control node!)
ufw allow out to 192.168.100.10 port 8080 proto tcp comment "Zone 1 Infisical API"

# Zone 2: Protected Data (.20-.23) — SSH & HTTPS health checks
for ip in 192.168.100.20 192.168.100.21 192.168.100.22 192.168.100.23; do
  ufw allow out to "$ip" port 22 proto tcp comment "Zone 2 Protected SSH"
  ufw allow out to "$ip" port 443 proto tcp comment "Zone 2 Protected HTTPS"
done

# Zone 3: Core Infra (.30-.33) — Pi-hole DNS + SSH & HTTPS health checks
ufw allow out to 192.168.100.30 port 53 comment "Zone 3 Pi-hole DNS"
for ip in 192.168.100.30 192.168.100.31 192.168.100.32 192.168.100.33; do
  ufw allow out to "$ip" port 22 proto tcp comment "Zone 3 Infra SSH"
  ufw allow out to "$ip" port 443 proto tcp comment "Zone 3 Infra HTTPS"
done

# Zone 4: Ephemeral Apps & Ops (.40-.42) — SSH & HTTPS health checks
for ip in 192.168.100.40 192.168.100.41 192.168.100.42; do
  ufw allow out to "$ip" port 22 proto tcp comment "Zone 4 Apps/Ops SSH"
  ufw allow out to "$ip" port 443 proto tcp comment "Zone 4 Apps/Ops HTTPS"
done

# Optional VMware NAT local DNS forwarder (port 53 ONLY, never SMB/RDP/HTTP)
if [[ -n "$VMNET_DNS_IP" ]]; then
  echo "[INFO] Allowing VMware NAT DNS forwarder ${VMNET_DNS_IP}:53"
  ufw allow out to "$VMNET_DNS_IP" port 53 comment "VMware NAT DNS forwarder"
fi

# ------------------------------------------------------------------
# 2. Explicit DENY ALL remaining private / LAN / link-local ranges
#    CRITICAL: Must precede broad public internet rules (53/80/443)
#    Blocks: Router .1, Windows PC, VMnet8 host .1, Zone 5 (.50-.59),
#            Open Reserve (.60-.99), DHCP pool (.100-.254), and all RFC1918.
# ------------------------------------------------------------------
ufw deny out to 10.0.0.0/8 comment "Block private RFC1918 10/8"
ufw deny out to 172.16.0.0/12 comment "Block private RFC1918 172.16/12"
ufw deny out to 192.168.0.0/16 comment "Block Router, Windows PC, Reserve, DHCP & LAN"
ufw deny out to 169.254.0.0/16 comment "Block link-local IPv4"
ufw deny out to fc00::/7 comment "Block ULA IPv6"
ufw deny out to fe80::/10 comment "Block link-local IPv6"

# ------------------------------------------------------------------
# 3. Public Internet Egress (apt, GitHub, Terraform registry, LLM APIs)
# ------------------------------------------------------------------
ufw allow out 53 comment "Public DNS"
ufw allow out 123/udp comment "Public NTP"
ufw allow out 80/tcp comment "Public HTTP (apt mirrors)"
ufw allow out 443/tcp comment "Public HTTPS (Git, Terraform, LLM APIs)"

ufw --force enable

# ------------------------------------------------------------------
# 4. Kernel UID-level LAN Lockdown for `homelab-agent`
#    Prevents `homelab-agent` from contacting ANY RFC1918 IP directly
#    (including Proxmox .2, Infisical .10, and LXCs). Only `homelab-ops`
#    (via the 3 audited read-only wrappers) can touch 192.168.100.x.
# ------------------------------------------------------------------
cat > "$LOCK_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

AGENT_USER="${AGENT_USER}"

if ! id -u "\$AGENT_USER" >/dev/null 2>&1; then
  echo "[WARN] User '\$AGENT_USER' does not exist yet; skipping UID LAN lockdown."
  exit 0
fi

AGENT_UID="\$(id -u "\$AGENT_USER")"
CHAIN="HAYTHAM_AGENT_OUT"

apply_v4() {
  iptables -N "\$CHAIN" 2>/dev/null || iptables -F "\$CHAIN"
  iptables -C OUTPUT -m owner --uid-owner "\$AGENT_UID" -j "\$CHAIN" 2>/dev/null \
    || iptables -I OUTPUT 1 -m owner --uid-owner "\$AGENT_UID" -j "\$CHAIN"

  # Allow loopback (local IPC / systemd-resolved 127.0.0.53)
  iptables -A "\$CHAIN" -o lo -j RETURN

  # Block ALL direct private/LAN/link-local access from homelab-agent
  iptables -A "\$CHAIN" -d 10.0.0.0/8 -j REJECT --reject-with icmp-admin-prohibited
  iptables -A "\$CHAIN" -d 172.16.0.0/12 -j REJECT --reject-with icmp-admin-prohibited
  iptables -A "\$CHAIN" -d 192.168.0.0/16 -j REJECT --reject-with icmp-admin-prohibited
  iptables -A "\$CHAIN" -d 169.254.0.0/16 -j REJECT --reject-with icmp-admin-prohibited
  iptables -A "\$CHAIN" -j RETURN
}

apply_v6() {
  if ! command -v ip6tables >/dev/null 2>&1; then
    return 0
  fi
  ip6tables -N "\$CHAIN" 2>/dev/null || ip6tables -F "\$CHAIN"
  ip6tables -C OUTPUT -m owner --uid-owner "\$AGENT_UID" -j "\$CHAIN" 2>/dev/null \
    || ip6tables -I OUTPUT 1 -m owner --uid-owner "\$AGENT_UID" -j "\$CHAIN"

  ip6tables -A "\$CHAIN" -o lo -j RETURN
  ip6tables -A "\$CHAIN" -d fc00::/7 -j REJECT --reject-with icmp6-adm-prohibited
  ip6tables -A "\$CHAIN" -d fe80::/10 -j REJECT --reject-with icmp6-adm-prohibited
  ip6tables -A "\$CHAIN" -j RETURN
}

apply_v4
apply_v6
echo "[OK] Applied kernel UID LAN-block for '\$AGENT_USER' (uid=\$AGENT_UID)."
EOF

chmod 0755 "$LOCK_SCRIPT"
chown root:root "$LOCK_SCRIPT"

cat > "$LOCK_SERVICE" <<EOF
[Unit]
Description=Haytham Control Node — Kernel UID LAN Lockdown for homelab-agent
After=network-online.target ufw.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${LOCK_SCRIPT}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

chmod 0644 "$LOCK_SERVICE"
systemctl daemon-reload
systemctl enable haytham-agent-egress.service >/dev/null
systemctl start haytham-agent-egress.service

echo ""
echo "[OK] Control Node UFW & UID lockdown complete."
ufw status numbered
