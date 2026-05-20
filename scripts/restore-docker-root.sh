#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config DEST

bool_true "$ALLOW_DESTINATION_DOCKER_STOP" || die "Set ALLOW_DESTINATION_DOCKER_STOP=true after confirming Docker interruption is acceptable"
bool_true "$RESTORE_DOCKER_ROOT" || die "Set RESTORE_DOCKER_ROOT=true to confirm full Docker-root restore"
bool_true "$MOVE_EXISTING_DEST_DOCKER_ROOT" || die "Set MOVE_EXISTING_DEST_DOCKER_ROOT=true to preserve and replace destination Docker root"

if [[ -n "${DOCKER_ROOT_BACKUP_FILE:-}" ]]; then
  dest_backup="$DOCKER_ROOT_BACKUP_FILE"
elif [[ -n "${BACKUP_FILE:-}" ]]; then
  dest_backup="$BACKUP_FILE"
else
  dest_backup="$(
    ssh_exec DEST "ls -1t $(shell_quote "$MIGRATION_WORKDIR")/incoming/docker-root-*.tar.gz 2>/dev/null | head -n 1"
  )"
fi

[[ -n "$dest_backup" ]] || die "No destination Docker-root backup found. Run transfer-to-destination.sh or set DOCKER_ROOT_BACKUP_FILE."

RUN_ID="${RUN_ID:-$(timestamp)}"
remote_cmd=$(
  printf 'BACKUP_FILE=%q RUN_ID=%q bash -s' \
    "$dest_backup" \
    "$RUN_ID"
)

info "Restoring destination Docker root from $dest_backup"

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
  die "Docker-root restore must run as root"
fi

[ -f "$BACKUP_FILE" ] || die "backup not found: $BACKUP_FILE"
command -v tar >/dev/null 2>&1 || die "tar not found"

docker_root="/var/lib/docker"
if command -v docker >/dev/null 2>&1; then
  detected="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [ -n "$detected" ]; then
    docker_root="$detected"
  fi
fi

[ "$docker_root" = "/var/lib/docker" ] || die "Refusing non-standard Docker root restore target: $docker_root"

log "Stopping Docker service/socket"
systemctl stop docker.service docker.socket 2>/dev/null || \
  systemctl stop docker 2>/dev/null || \
  service docker stop 2>/dev/null || \
  true

if [ -e "$docker_root" ]; then
  moved_path="${docker_root}.pre-docker-root-${RUN_ID}"
  log "Moving existing $docker_root to $moved_path"
  mv "$docker_root" "$moved_path"
fi

log "Extracting Docker-root archive with absolute paths"
tar -Pxzpf "$BACKUP_FILE" -C /

log "Starting Docker"
systemctl start docker.service 2>/dev/null || \
  systemctl start docker 2>/dev/null || \
  service docker start 2>/dev/null || \
  die "failed to start Docker"

sleep 10

log "Docker-root restore complete"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | sed -n '1,120p'
REMOTE
