#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

load_env
require_remote_config DEST

ssh_bash DEST <<'REMOTE'
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

section "coolify logs tail"
docker logs --tail 120 coolify 2>&1 || true

section "proxy logs tail"
docker logs --tail 120 coolify-proxy 2>&1 || true

section "ports"
ss -tulpn 2>/dev/null | grep -E ':(80|443)\b' || true

section "disk"
df -h
REMOTE
