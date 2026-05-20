#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config DEST

remote_cmd=$(
  printf 'NEW_SERVER_IPV4=%q bash -s' "${NEW_SERVER_IPV4:-}"
)

info "Repairing Coolify localhost server access on $DEST_HOST"

ssh_exec DEST "$remote_cmd" <<'REMOTE'
set -Eeuo pipefail

log() {
  printf '[DEST] %s\n' "$*"
}

die() {
  printf '[DEST][ERROR] %s\n' "$*" >&2
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  die "must run as root"
fi

command -v docker >/dev/null 2>&1 || die "docker not found"
docker ps --format '{{.Names}}' | grep -qx coolify || die "coolify container not running"
docker ps --format '{{.Names}}' | grep -qx coolify-db || die "coolify-db container not running"

localhost_uuid="$(
  docker exec coolify-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select pk.uuid from servers s join private_keys pk on pk.id=s.private_key_id where s.id=0 limit 1;"'
)"
[ -n "$localhost_uuid" ] || die "could not determine localhost private key uuid"

key_file="/data/coolify/ssh/keys/ssh_key@$localhost_uuid"
[ -f "$key_file" ] || die "localhost private key file missing: $key_file"

pub="$(ssh-keygen -y -f "$key_file")"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

if grep -qxF "$pub" /root/.ssh/authorized_keys; then
  log "Coolify localhost public key already authorized for root"
else
  printf '%s\n' "$pub" >>/root/.ssh/authorized_keys
  log "Added Coolify localhost public key to root authorized_keys"
fi

log "Testing SSH from coolify container to destination host"
docker exec coolify sh -lc "ssh -i /var/www/html/storage/app/ssh/keys/ssh_key@$localhost_uuid -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 root@host.docker.internal 'docker version --format {{.Server.Version}}'" >/dev/null

if [ -n "${NEW_SERVER_IPV4:-}" ]; then
  log "Updating Coolify instance public IPv4 to $NEW_SERVER_IPV4"
  docker exec coolify-db sh -lc "psql -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -v ON_ERROR_STOP=1 -c \"update instance_settings set public_ipv4 = '$NEW_SERVER_IPV4', updated_at = now() where id = 0;\""
fi

log "Marking localhost server reachable/usable after SSH validation"
docker exec coolify-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -c "update server_settings set is_reachable=true, is_usable=true, updated_at=now() where server_id=0; update servers set unreachable_count=0, unreachable_notification_sent=false, validation_logs=null, updated_at=now() where id=0;"'
docker exec coolify sh -lc 'php artisan optimize:clear >/dev/null 2>&1 || true'

log "Coolify localhost repair complete"
REMOTE
