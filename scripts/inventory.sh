#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

load_env
require_remote_config SOURCE
require_remote_config DEST

RUN_ID="$(timestamp)"
OUT_DIR="$LOCAL_ARTIFACT_DIR/inventory/$RUN_ID"
mkdir -p "$OUT_DIR/source" "$OUT_DIR/destination"

capture() {
  local prefix="$1"
  local rel_path="$2"
  local target="$OUT_DIR/$rel_path"
  mkdir -p "$(dirname "$target")"

  info "Capturing $prefix -> $target"
  if ssh_bash "$prefix" >"$target" 2>&1; then
    return 0
  fi

  warn "Capture failed for $prefix ($rel_path); see $target"
  return 0
}

capture SOURCE source/summary.txt <<'REMOTE'
set +e

section() {
  printf '\n## %s\n' "$*"
}

sudo_run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    "$@"
  fi
}

section "identity"
hostnamectl 2>/dev/null || hostname
date -Is
id
uname -a

section "disk and memory"
df -h
free -h 2>/dev/null || true

section "listening ports"
sudo_run ss -tulpn 2>/dev/null || ss -tulpn 2>/dev/null || true

section "docker"
if command -v docker >/dev/null 2>&1; then
  docker version 2>/dev/null || true
  docker info 2>/dev/null || true
  docker info --format 'DockerRootDir={{.DockerRootDir}} ServerVersion={{.ServerVersion}} Architecture={{.Architecture}}' 2>/dev/null || true

  section "docker containers"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

  section "docker containers all"
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

  section "docker volumes"
  docker volume ls 2>/dev/null || true

  section "docker networks"
  docker network ls 2>/dev/null || true

  section "docker mounts"
  ids="$(docker ps -aq 2>/dev/null)"
  if [ -n "$ids" ]; then
    docker inspect $ids --format 'container={{.Name}} image={{.Config.Image}} status={{.State.Status}}{{range .Mounts}}{{println}}{{printf "  type=%s name=%s source=%s destination=%s rw=%v" .Type .Name .Source .Destination .RW}}{{end}}{{println}}' 2>/dev/null || true
  fi
else
  echo "docker not found"
fi

section "coolify"
if [ -d /data/coolify ]; then
  sudo_run du -sh /data/coolify 2>/dev/null || true
  sudo_run find /data/coolify -maxdepth 3 -mindepth 1 -printf '%M %u:%g %p\n' 2>/dev/null | sort | head -n 500 || true
else
  echo "/data/coolify not found"
fi

section "coolify version"
docker exec coolify php artisan --version 2>/dev/null || true
docker inspect coolify --format 'image={{.Config.Image}} status={{.State.Status}}' 2>/dev/null || true
REMOTE

capture DEST destination/summary.txt <<'REMOTE'
set +e

section() {
  printf '\n## %s\n' "$*"
}

sudo_run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo "$@"
  else
    "$@"
  fi
}

section "identity"
hostnamectl 2>/dev/null || hostname
date -Is
id
uname -a

section "disk and memory"
df -h
free -h 2>/dev/null || true

section "listening ports"
sudo_run ss -tulpn 2>/dev/null || ss -tulpn 2>/dev/null || true

section "docker"
if command -v docker >/dev/null 2>&1; then
  docker version 2>/dev/null || true
  docker info 2>/dev/null || true
  docker info --format 'DockerRootDir={{.DockerRootDir}} ServerVersion={{.ServerVersion}} Architecture={{.Architecture}}' 2>/dev/null || true
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true
else
  echo "docker not found"
fi

section "counter-strike hints"
if command -v docker >/dev/null 2>&1; then
  docker ps -a --format '{{.Names}} {{.Image}} {{.Status}}' 2>/dev/null | grep -Ei 'counter|strike|cs2|csgo|srcds|steam' || true
fi
ps -eo user,pid,comm 2>/dev/null | grep -Ei 'counter|strike|cs2|csgo|srcds|steam' || true

section "coolify destination path"
if [ -e /data/coolify ]; then
  sudo_run du -sh /data/coolify 2>/dev/null || true
  sudo_run ls -la /data/coolify 2>/dev/null || true
else
  echo "/data/coolify not present"
fi
REMOTE

info "Inventory written to $OUT_DIR"
