#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_execute_flag "${1:-}"
load_env
require_remote_config SOURCE

RUN_ID="${RUN_ID:-$(timestamp)}"
remote_cmd=$(
  printf 'COOLIFY_DATA_DIR=%q MIGRATION_WORKDIR=%q RUN_ID=%q STOP_DOCKER_FOR_BACKUP=%q RUN_DB_DUMPS=%q EXTRA_BIND_PATHS=%q MERGE_ROOT_AUTHORIZED_KEYS=%q bash -s' \
    "$COOLIFY_DATA_DIR" \
    "$MIGRATION_WORKDIR" \
    "$RUN_ID" \
    "$STOP_DOCKER_FOR_BACKUP" \
    "$RUN_DB_DUMPS" \
    "$EXTRA_BIND_PATHS" \
    "$MERGE_ROOT_AUTHORIZED_KEYS"
)

info "Creating source backup on $SOURCE_HOST with run id $RUN_ID"

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
  die "write phases must run as root to preserve Docker volume ownership"
fi

command -v docker >/dev/null 2>&1 || die "docker not found"
[ -d "$COOLIFY_DATA_DIR" ] || die "Coolify data directory not found: $COOLIFY_DATA_DIR"

run_dir="$MIGRATION_WORKDIR/backups/$RUN_ID"
payload_dir="$run_dir/payload"
db_dir="$payload_dir/db-dumps"
backup_file="$run_dir/coolify-migration-$RUN_ID.tar.gz"

mkdir -p "$db_dir"

docker_root="$(docker info --format '{{.DockerRootDir}}')"
[ -n "$docker_root" ] || die "could not determine Docker root"

log "Docker root: $docker_root"
log "Backup file: $backup_file"

container_ids="$(docker ps -aq || true)"
volume_names=""
if [ -n "$container_ids" ]; then
  volume_names="$(docker inspect $container_ids --format '{{range .Mounts}}{{if eq .Type "volume"}}{{println .Name}}{{end}}{{end}}' | sort -u || true)"
fi

volume_paths=()
while IFS= read -r volume_name; do
  [ -n "$volume_name" ] || continue
  volume_path="$docker_root/volumes/$volume_name"
  if [ -d "$volume_path" ]; then
    volume_paths+=("$volume_path")
  else
    log "Skipping missing volume path: $volume_path"
  fi
done <<<"$volume_names"

bind_paths=()
if [ -n "${EXTRA_BIND_PATHS:-}" ]; then
  IFS=':' read -r -a bind_paths <<<"$EXTRA_BIND_PATHS"
fi

tar_paths=("$COOLIFY_DATA_DIR" "$payload_dir")
for volume_path in "${volume_paths[@]}"; do
  tar_paths+=("$volume_path")
done
for bind_path in "${bind_paths[@]}"; do
  [ -n "$bind_path" ] || continue
  if [ -e "$bind_path" ]; then
    tar_paths+=("$bind_path")
  else
    log "Configured bind path does not exist, skipping: $bind_path"
  fi
done

if bool_true "$MERGE_ROOT_AUTHORIZED_KEYS" && [ -f /root/.ssh/authorized_keys ]; then
  tar_paths+=("/root/.ssh/authorized_keys")
fi

{
  echo "run_id=$RUN_ID"
  echo "created_at=$(date -Is)"
  echo "hostname=$(hostname)"
  echo "docker_root=$docker_root"
  echo "coolify_data_dir=$COOLIFY_DATA_DIR"
  echo "stop_docker_for_backup=$STOP_DOCKER_FOR_BACKUP"
  echo "run_db_dumps=$RUN_DB_DUMPS"
  echo
  echo "[containers]"
  docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}'
  echo
  echo "[volumes]"
  printf '%s\n' "$volume_names"
  echo
  echo "[tar_paths]"
  printf '%s\n' "${tar_paths[@]}"
} >"$payload_dir/manifest.txt"

if bool_true "$RUN_DB_DUMPS" && [ -n "$container_ids" ]; then
  log "Running best-effort logical database dumps"
  for cid in $container_ids; do
    name="$(docker inspect --format '{{.Name}}' "$cid" | sed 's#^/##' | tr '/:' '__')"

    if docker exec "$cid" sh -lc 'command -v pg_dump >/dev/null 2>&1 && [ -n "${POSTGRES_USER:-}" ]' >/dev/null 2>&1; then
      log "PostgreSQL dump: $name"
      if ! docker exec "$cid" sh -lc 'db="${POSTGRES_DB:-$POSTGRES_USER}"; PGPASSWORD="${POSTGRES_PASSWORD:-}" pg_dump -U "$POSTGRES_USER" -d "$db" -Fc' >"$db_dir/$name.postgres.dump"; then
        log "PostgreSQL dump failed for $name"
        rm -f "$db_dir/$name.postgres.dump"
      fi
      continue
    fi

    if docker exec "$cid" sh -lc 'command -v mysqldump >/dev/null 2>&1 && { [ -n "${MYSQL_DATABASE:-}" ] || [ -n "${MARIADB_DATABASE:-}" ]; }' >/dev/null 2>&1; then
      log "MySQL/MariaDB dump: $name"
      if ! docker exec "$cid" sh -lc 'db="${MYSQL_DATABASE:-${MARIADB_DATABASE:-}}"; user="${MYSQL_USER:-${MARIADB_USER:-root}}"; pass="${MYSQL_PASSWORD:-${MARIADB_PASSWORD:-${MYSQL_ROOT_PASSWORD:-${MARIADB_ROOT_PASSWORD:-}}}}"; mysqldump -u "$user" ${pass:+-p"$pass"} "$db"' >"$db_dir/$name.mysql.sql"; then
        log "MySQL/MariaDB dump failed for $name"
        rm -f "$db_dir/$name.mysql.sql"
      fi
    fi
  done
else
  log "Logical database dumps disabled or no containers found"
fi

docker_stopped=0
start_docker() {
  if [ "$docker_stopped" -eq 1 ]; then
    log "Starting Docker after backup"
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
  fi
}
trap start_docker EXIT

if bool_true "$STOP_DOCKER_FOR_BACKUP"; then
  log "Stopping Docker for a consistent volume snapshot"
  systemctl stop docker 2>/dev/null || service docker stop 2>/dev/null || die "failed to stop Docker"
  docker_stopped=1
else
  log "Docker stop disabled. Live DB volumes may be inconsistent."
fi

log "Creating archive"
tar --exclude='*.sock' \
  --warning=no-file-changed \
  --ignore-failed-read \
  --numeric-owner \
  --xattrs \
  --acls \
  -Pczpf "$backup_file" "${tar_paths[@]}"

sha256sum "$backup_file" >"$backup_file.sha256"
log "Backup complete"
cat "$backup_file.sha256"
REMOTE
