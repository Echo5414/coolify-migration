#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config SOURCE
require_remote_config DEST

if [[ -n "${BACKUP_FILE:-}" ]]; then
  source_backup="$BACKUP_FILE"
else
  source_backup="$(
    ssh_exec SOURCE "ls -1t $(shell_quote "$MIGRATION_WORKDIR")/backups/*/coolify-migration-*.tar.gz 2>/dev/null | head -n 1"
  )"
fi

[[ -n "$source_backup" ]] || die "No source backup found. Set BACKUP_FILE or run backup-source.sh first."

dest_dir="$MIGRATION_WORKDIR/incoming"
dest_backup="$dest_dir/$(basename "$source_backup")"

info "Source backup: $source_backup"
info "Destination backup: $dest_backup"

source_sha="$(
  ssh_exec SOURCE "sha256sum $(shell_quote "$source_backup") | awk '{print \$1}'"
)"

ssh_exec DEST "mkdir -p $(shell_quote "$dest_dir")"

info "Streaming backup to destination"
set +e
ssh_exec SOURCE "cat $(shell_quote "$source_backup")" | ssh_exec DEST "cat > $(shell_quote "$dest_backup")"
pipe_status=("${PIPESTATUS[@]}")
set -e

if [[ "${pipe_status[0]}" -ne 0 || "${pipe_status[1]}" -ne 0 ]]; then
  die "Transfer failed"
fi

dest_sha="$(
  ssh_exec DEST "sha256sum $(shell_quote "$dest_backup") | awk '{print \$1}'"
)"

if [[ "$source_sha" != "$dest_sha" ]]; then
  die "Checksum mismatch: source=$source_sha destination=$dest_sha"
fi

info "Transfer verified: $dest_sha"
