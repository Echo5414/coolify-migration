#!/usr/bin/env bash

set -Eeuo pipefail

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$COMMON_DIR/../.." && pwd)"

info() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

timestamp() {
  date -u +%Y%m%dT%H%M%SZ
}

expand_path() {
  local value="$1"
  if [[ "$value" == "~/"* ]]; then
    printf '%s/%s' "$HOME" "${value#~/}"
  elif [[ "$value" =~ ^/([A-Za-z])/(.*)$ && -d /mnt/${BASH_REMATCH[1],,} ]]; then
    printf '/mnt/%s/%s' "${BASH_REMATCH[1],,}" "${BASH_REMATCH[2]}"
  elif [[ "$value" =~ ^([A-Za-z]):\\(.*)$ && -d /mnt/${BASH_REMATCH[1],,} ]]; then
    local drive="${BASH_REMATCH[1],,}"
    local rest="${BASH_REMATCH[2]//\\//}"
    printf '/mnt/%s/%s' "$drive" "$rest"
  else
    printf '%s' "$value"
  fi
}

shell_quote() {
  printf '%q' "$1"
}

bool_true() {
  case "${1:-}" in
    true | TRUE | yes | YES | y | Y | 1) return 0 ;;
    *) return 1 ;;
  esac
}

load_env() {
  if [[ -z "${ENV_FILE:-}" ]]; then
    if [[ -f "$REPO_ROOT/.env" ]]; then
      ENV_FILE="$REPO_ROOT/.env"
    elif [[ -f "$REPO_ROOT/.env.develop" ]]; then
      ENV_FILE="$REPO_ROOT/.env.develop"
    else
      ENV_FILE="$REPO_ROOT/.env"
    fi
  fi

  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  else
    warn "No .env found at $ENV_FILE. Using environment variables only."
  fi

  SOURCE_PORT="${SOURCE_PORT:-22}"
  DEST_PORT="${DEST_PORT:-22}"
  SOURCE_USER="${SOURCE_USER:-root}"
  DEST_USER="${DEST_USER:-root}"
  COOLIFY_DATA_DIR="${COOLIFY_DATA_DIR:-/data/coolify}"
  MIGRATION_WORKDIR="${MIGRATION_WORKDIR:-/root/coolify-migration}"
  LOCAL_ARTIFACT_DIR="${LOCAL_ARTIFACT_DIR:-$REPO_ROOT/artifacts}"
  STOP_DOCKER_FOR_BACKUP="${STOP_DOCKER_FOR_BACKUP:-true}"
  KEEP_SOURCE_DOCKER_STOPPED="${KEEP_SOURCE_DOCKER_STOPPED:-false}"
  RUN_DB_DUMPS="${RUN_DB_DUMPS:-true}"
  EXTRA_BIND_PATHS="${EXTRA_BIND_PATHS:-}"
  MERGE_ROOT_AUTHORIZED_KEYS="${MERGE_ROOT_AUTHORIZED_KEYS:-false}"
  ALLOW_DESTINATION_DOCKER_STOP="${ALLOW_DESTINATION_DOCKER_STOP:-false}"
  MOVE_EXISTING_DEST_COOLIFY="${MOVE_EXISTING_DEST_COOLIFY:-false}"
  ALLOW_LATEST_COOLIFY="${ALLOW_LATEST_COOLIFY:-false}"
  SHOW_VERIFY_LOGS="${SHOW_VERIFY_LOGS:-false}"
  DOMAINS="${DOMAINS:-}"
  NEW_SERVER_IPV4="${NEW_SERVER_IPV4:-}"
  NEW_SERVER_IPV6="${NEW_SERVER_IPV6:-}"
}

require_remote_config() {
  local prefix="$1"
  local host_var="${prefix}_HOST"
  local user_var="${prefix}_USER"
  local host="${!host_var:-}"
  local user="${!user_var:-}"

  [[ -n "$host" ]] || die "$host_var is required"
  [[ -n "$user" ]] || die "$user_var is required"
}

build_ssh_args() {
  local prefix="$1"
  local -n out_args="$2"
  local host_var="${prefix}_HOST"
  local user_var="${prefix}_USER"
  local port_var="${prefix}_PORT"
  local key_var="${prefix}_SSH_KEY"
  local host="${!host_var:-}"
  local user="${!user_var:-root}"
  local port="${!port_var:-22}"
  local key="${!key_var:-}"

  [[ -n "$host" ]] || die "$host_var is required"

  out_args=(
    -p "$port"
    -o BatchMode=yes
    -o ConnectTimeout=10
    -o StrictHostKeyChecking=accept-new
  )

  if [[ -n "$key" ]]; then
    out_args+=(-i "$(expand_path "$key")")
  fi

  out_args+=("${user}@${host}")
}

ssh_exec() {
  local prefix="$1"
  shift
  local -a ssh_args
  build_ssh_args "$prefix" ssh_args
  ssh "${ssh_args[@]}" "$@"
}

ssh_bash() {
  local prefix="$1"
  shift || true
  local -a ssh_args
  build_ssh_args "$prefix" ssh_args
  ssh "${ssh_args[@]}" 'bash -s' "$@"
}

require_execute_flag() {
  local arg="${1:-}"
  [[ "$arg" == "--execute" ]] || die "Refusing write phase without --execute"
}
