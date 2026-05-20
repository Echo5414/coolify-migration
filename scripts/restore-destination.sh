#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config DEST

bool_true "$ALLOW_DESTINATION_DOCKER_STOP" || die "Set ALLOW_DESTINATION_DOCKER_STOP=true after confirming Docker interruption is acceptable"

if [[ -z "${COOLIFY_VERSION:-}" ]] && ! bool_true "$ALLOW_LATEST_COOLIFY"; then
  die "Set COOLIFY_VERSION to the source Coolify version, or explicitly set ALLOW_LATEST_COOLIFY=true"
fi

if [[ -n "${BACKUP_FILE:-}" ]]; then
  dest_backup="$BACKUP_FILE"
else
  dest_backup="$(
    ssh_exec DEST "ls -1t $(shell_quote "$MIGRATION_WORKDIR")/incoming/coolify-migration-*.tar.gz 2>/dev/null | head -n 1"
  )"
fi

[[ -n "$dest_backup" ]] || die "No destination backup found. Run transfer-to-destination.sh first or set BACKUP_FILE."

RUN_ID="${RUN_ID:-$(timestamp)}"
remote_cmd=$(
  printf 'BACKUP_FILE=%q COOLIFY_DATA_DIR=%q COOLIFY_VERSION=%q MOVE_EXISTING_DEST_COOLIFY=%q ALLOW_LATEST_COOLIFY=%q RUN_ID=%q bash -s' \
    "$dest_backup" \
    "$COOLIFY_DATA_DIR" \
    "${COOLIFY_VERSION:-}" \
    "$MOVE_EXISTING_DEST_COOLIFY" \
    "$ALLOW_LATEST_COOLIFY" \
    "$RUN_ID"
)

info "Restoring destination from $dest_backup"

ssh_exec DEST "$remote_cmd" <<'REMOTE'
set -Eeuo pipefail

log() {
  printf '[DEST] %s\n' "$*"
}

die() {
  printf '[DEST][ERROR] %s\n' "$*" >&2
  exit 1
}

bool_true() {
  case "${1:-}" in
    true | TRUE | yes | YES | y | Y | 1) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$(id -u)" -ne 0 ]; then
  die "restore must run as root to preserve Docker volume ownership"
fi

[ -f "$BACKUP_FILE" ] || die "backup not found: $BACKUP_FILE"
command -v tar >/dev/null 2>&1 || die "tar not found"
command -v curl >/dev/null 2>&1 || die "curl not found"

if [ -e "$COOLIFY_DATA_DIR" ]; then
  if bool_true "$MOVE_EXISTING_DEST_COOLIFY"; then
    moved_path="${COOLIFY_DATA_DIR}.pre-migration-${RUN_ID}"
    log "Moving existing $COOLIFY_DATA_DIR to $moved_path"
    mv "$COOLIFY_DATA_DIR" "$moved_path"
  else
    die "$COOLIFY_DATA_DIR already exists. Set MOVE_EXISTING_DEST_COOLIFY=true only after reviewing destination state."
  fi
fi

log "Stopping Docker on destination"
systemctl stop docker 2>/dev/null || service docker stop 2>/dev/null || true

log "Extracting backup archive with absolute paths"
tar -Pxzpf "$BACKUP_FILE" -C /

if [ -d "$COOLIFY_DATA_DIR" ]; then
  log "Preserving restored ownership under $COOLIFY_DATA_DIR"
fi

log "Installing or reconciling Coolify"
if [ -n "${COOLIFY_VERSION:-}" ]; then
  curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash -s "$COOLIFY_VERSION"
elif bool_true "$ALLOW_LATEST_COOLIFY"; then
  curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
else
  die "COOLIFY_VERSION missing and latest install not allowed"
fi

log "Restore complete"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
REMOTE
