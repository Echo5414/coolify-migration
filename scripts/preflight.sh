#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

load_env
require_remote_config SOURCE
require_remote_config DEST

info "Testing SSH to source"
ssh_exec SOURCE true

info "Testing SSH to destination"
ssh_exec DEST true

info "Running source preflight"
ssh_bash SOURCE <<REMOTE
set -Eeuo pipefail
COOLIFY_DATA_DIR=$(shell_quote "$COOLIFY_DATA_DIR")

failures=0
check() {
  if "\$@"; then
    printf '[OK] %s\n' "\$*"
  else
    printf '[FAIL] %s\n' "\$*" >&2
    failures=\$((failures + 1))
  fi
}

check command -v docker
check test -d "\$COOLIFY_DATA_DIR"
check docker info >/dev/null

if [ "\$(id -u)" -ne 0 ]; then
  printf '[WARN] write phases should use root SSH for consistent ownership preservation\n' >&2
fi

docker_root="\$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
printf '[INFO] docker root: %s\n' "\$docker_root"
printf '[INFO] architecture: %s\n' "\$(docker info --format '{{.Architecture}}' 2>/dev/null || true)"
printf '[INFO] coolify version: '
docker exec coolify php artisan --version 2>/dev/null || true

ids="\$(docker ps -aq 2>/dev/null || true)"
if [ -n "\$ids" ]; then
  volume_count="\$(docker inspect \$ids --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' | sort -u | grep -c . || true)"
  bind_count="\$(docker inspect \$ids --format '{{range .Mounts}}{{if eq .Type "bind"}}{{println .Source}}{{end}}{{end}}' | sort -u | grep -c . || true)"
  printf '[INFO] discovered docker volumes: %s\n' "\$volume_count"
  printf '[INFO] discovered bind mounts: %s\n' "\$bind_count"
fi

printf '[INFO] source disk estimate, broad view:\n'
du -sh "\$COOLIFY_DATA_DIR" 2>/dev/null || true
if [ -n "\$docker_root" ] && [ -d "\$docker_root/volumes" ]; then
  du -sh "\$docker_root/volumes" 2>/dev/null || true
fi

exit "\$failures"
REMOTE

info "Running destination preflight"
ssh_bash DEST <<'REMOTE'
set -Eeuo pipefail
failures=0
check() {
  if "$@"; then
    printf '[OK] %s\n' "$*"
  else
    printf '[FAIL] %s\n' "$*" >&2
    failures=$((failures + 1))
  fi
}

check command -v curl
check df -Pk /

if command -v docker >/dev/null 2>&1; then
  docker info --format '[INFO] docker root: {{.DockerRootDir}} architecture: {{.Architecture}} server: {{.ServerVersion}}' 2>/dev/null || true
  printf '[INFO] docker-managed counter-strike hints:\n'
  docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null | grep -Ei 'counter|strike|cs2|csgo|srcds|steam' || true
else
  printf '[WARN] docker not installed on destination yet\n' >&2
fi

printf '[INFO] port 80/443 listeners:\n'
ss -tulpn 2>/dev/null | grep -E ':(80|443)\b' || true

if [ -e /data/coolify ]; then
  printf '[WARN] /data/coolify already exists on destination\n' >&2
  ls -la /data/coolify 2>/dev/null || true
fi

exit "$failures"
REMOTE

info "Preflight completed"
