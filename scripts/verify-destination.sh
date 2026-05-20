#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

load_env
require_remote_config DEST

remote_cmd=$(
  printf 'SHOW_VERIFY_LOGS=%q bash -s' "$SHOW_VERIFY_LOGS"
)

ssh_exec DEST "$remote_cmd" <<'REMOTE'
set +e

section() {
  printf '\n## %s\n' "$*"
}

section "docker containers"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

section "problem containers"
{
  docker ps -a --filter status=restarting --format '{{.Names}} {{.Status}}'
  docker ps -a --filter health=unhealthy --format '{{.Names}} {{.Status}}'
  docker ps -a --filter status=exited --format '{{.Names}} {{.Status}}'
  docker ps -a --filter status=dead --format '{{.Names}} {{.Status}}'
} | sed '/^$/d' || true

section "coolify containers"
docker ps --format '{{.Names}}' | grep -E '^coolify|coolify-' | while read -r name; do
  [ -n "$name" ] || continue
  echo "### $name"
  docker inspect "$name" --format 'image={{.Config.Image}} status={{.State.Status}} started={{.State.StartedAt}}'
done

section "coolify server state"
if docker ps --format '{{.Names}}' | grep -qx coolify-db; then
  docker exec coolify-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -c "select s.name,s.ip,ss.is_reachable,ss.is_usable,s.unreachable_count from servers s left join server_settings ss on ss.server_id=s.id order by s.id;"' || true
  docker exec coolify-db sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -P pager=off -c "select id, public_ipv4, public_ipv6, fqdn from instance_settings order by id;"' || true
else
  echo "coolify-db container not running"
fi

case "${SHOW_VERIFY_LOGS:-false}" in
  true | TRUE | yes | YES | y | Y | 1)
    section "coolify logs tail"
    docker logs --tail 120 coolify 2>&1 || true

    section "proxy logs tail"
    docker logs --tail 120 coolify-proxy 2>&1 || true
    ;;
  *)
    section "logs"
    echo "Container logs suppressed. Set SHOW_VERIFY_LOGS=true for targeted debugging."
    ;;
esac

section "ports"
ss -tulpn 2>/dev/null | grep -E ':(80|443)\b' || true

section "docker bridge route duplicates"
ip route show 2>/dev/null | awk '{print $1}' | sort | uniq -d | grep -E '^10\.|^172\.' || true

section "disk"
df -h
REMOTE
