#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config SOURCE

RUN_ID="${RUN_ID:-docker-root-$(timestamp)}"
remote_cmd=$(
  printf 'MIGRATION_WORKDIR=%q RUN_ID=%q KEEP_SOURCE_DOCKER_STOPPED=%q SOURCE_DOCKER_ROOT=%q bash -s' \
    "$MIGRATION_WORKDIR" \
    "$RUN_ID" \
    "$KEEP_SOURCE_DOCKER_STOPPED" \
    "$SOURCE_DOCKER_ROOT"
)

info "Creating stopped Docker-root backup on $SOURCE_HOST with run id $RUN_ID"

ssh_exec SOURCE "$remote_cmd" <<'REMOTE'
set -Eeuo pipefail

log() {
  printf '[SOURCE] %s\n' "$*"
}

die() {
  printf '[SOURCE][ERROR] %s\n' "$*" >&2
  exit 1
}

bool_true() {
  case "${1:-}" in
    true | TRUE | yes | YES | y | Y | 1) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$(id -u)" -ne 0 ]; then
  die "Docker-root backup must run as root"
fi

docker_root="${SOURCE_DOCKER_ROOT:-/var/lib/docker}"
[ -d "$docker_root" ] || die "Docker root not found: $docker_root"

run_dir="$MIGRATION_WORKDIR/backups/$RUN_ID"
archive="$run_dir/docker-root-$RUN_ID.tar.gz"
mkdir -p "$run_dir"

docker_stopped=0
start_docker() {
  if [ "$docker_stopped" -eq 1 ]; then
    log "Starting Docker service/socket after Docker-root backup"
    systemctl start docker.socket docker.service 2>/dev/null || \
      systemctl start docker 2>/dev/null || \
      service docker start 2>/dev/null || \
      true
  fi
}

if bool_true "${KEEP_SOURCE_DOCKER_STOPPED:-false}"; then
  log "KEEP_SOURCE_DOCKER_STOPPED=true; source Docker will remain stopped"
else
  trap start_docker EXIT
fi

log "Stopping Docker service/socket before archiving Docker root"
systemctl stop docker.service docker.socket 2>/dev/null || \
  systemctl stop docker 2>/dev/null || \
  service docker stop 2>/dev/null || \
  true
docker_stopped=1

{
  echo "run_id=$RUN_ID"
  echo "created_at=$(date -Is)"
  echo "hostname=$(hostname)"
  echo "docker_root=$docker_root"
  echo "docker_service=$(systemctl is-active docker.service 2>/dev/null || true)"
  echo "docker_socket=$(systemctl is-active docker.socket 2>/dev/null || true)"
} >"$run_dir/manifest.txt"

log "Creating Docker-root archive: $archive"
du -sh "$docker_root" 2>/dev/null || true

tar --exclude='*.sock' \
  --warning=no-file-changed \
  --ignore-failed-read \
  --numeric-owner \
  --xattrs \
  --acls \
  -Pczpf "$archive" "$docker_root" "$run_dir/manifest.txt"

sha256sum "$archive" >"$archive.sha256"
log "Docker-root backup complete"
cat "$archive.sha256"
REMOTE
