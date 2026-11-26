#!/usr/bin/env bash
set -euo pipefail

# Off-host local-network backup pull script (run from WSL Ubuntu 24.04 on Windows).
# Zero cloud, zero Samba — uses your existing key-based SSH access over LAN/Tailscale.
#
# Usage:
#   ./scripts/pull-homelab-backups.sh                    # Pull both Track 1 + Track 2
#   ./scripts/pull-homelab-backups.sh --state-only       # Track 1 only (encrypted restic repo)
#   ./scripts/pull-homelab-backups.sh --photos-only      # Track 2 only (Immich originals)
#
# Customize destinations via environment variables (or edit defaults below):
#   STATE_BACKUP_DIR="/mnt/c/Users/<you>/Backups/haytham/state"
#   PHOTOS_BACKUP_DIR="/mnt/d/Backups/haytham/immich-originals"

PVE_HOST="${PVE_HOST:-root@192.168.100.2}"
IMMICH_HOST="${IMMICH_HOST:-root@192.168.100.21}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

STATE_BACKUP_DIR="${STATE_BACKUP_DIR:-$HOME/homelab-backups/state}"
PHOTOS_BACKUP_DIR="${PHOTOS_BACKUP_DIR:-$HOME/homelab-backups/immich-originals}"

RUN_STATE=true
RUN_PHOTOS=true

for arg in "$@"; do
  case "$arg" in
    --state-only)  RUN_PHOTOS=false ;;
    --photos-only) RUN_STATE=false ;;
    -h|--help)
      sed -n '3,16p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

SSH_OPTS=(-i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=10)

if "$RUN_STATE"; then
  echo "=== Track 1: Pulling encrypted restic repo from $PVE_HOST ==="
  mkdir -p "$STATE_BACKUP_DIR/restic"
  rsync -avh --delete -e "ssh ${SSH_OPTS[*]}" \
    "$PVE_HOST:/var/backups/homelab/restic/" \
    "$STATE_BACKUP_DIR/restic/"
  echo "Track 1 synced -> $STATE_BACKUP_DIR/restic"
fi

if "$RUN_PHOTOS"; then
  echo "=== Track 2: Pulling Immich original media from $IMMICH_HOST ==="
  echo "(Excludes regeneratable thumbs/ and encoded-video/; no --delete for safety)"
  for sub in library upload profile; do
    if ssh "${SSH_OPTS[@]}" "$IMMICH_HOST" "test -d /opt/immich/library/$sub"; then
      mkdir -p "$PHOTOS_BACKUP_DIR/$sub"
      rsync -avh --progress -e "ssh ${SSH_OPTS[*]}" \
        "$IMMICH_HOST:/opt/immich/library/$sub/" \
        "$PHOTOS_BACKUP_DIR/$sub/"
    fi
  done
  echo "Track 2 synced -> $PHOTOS_BACKUP_DIR"
fi

echo "=== Off-host backup pull complete ==="
