#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

load_env

[[ -n "$DOMAINS" ]] || die "DOMAINS is empty in .env"
[[ -n "$NEW_SERVER_IPV4" || -n "$NEW_SERVER_IPV6" ]] || die "Set NEW_SERVER_IPV4 and/or NEW_SERVER_IPV6 in .env"

printf '# Temporary hosts-file entries for Hetzner migration testing\n'
printf '# Remove these after DNS cutover validation.\n'

for domain in $DOMAINS; do
  if [[ -n "$NEW_SERVER_IPV4" ]]; then
    printf '%s %s\n' "$NEW_SERVER_IPV4" "$domain"
  fi
  if [[ -n "$NEW_SERVER_IPV6" ]]; then
    printf '%s %s\n' "$NEW_SERVER_IPV6" "$domain"
  fi
done
