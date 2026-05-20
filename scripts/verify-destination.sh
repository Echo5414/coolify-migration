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

section "coolify containers"
docker ps --format '{{.Names}}' | grep -E '^coolify|coolify-' | while read -r name; do
  [ -n "$name" ] || continue
  echo "### $name"
  docker inspect "$name" --format 'image={{.Config.Image}} status={{.State.Status}} started={{.State.StartedAt}}'
done

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

section "disk"
df -h
REMOTE
