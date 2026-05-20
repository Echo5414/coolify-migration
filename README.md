# Coolify Migration Toolkit

This repo is a guarded toolkit for moving a single-server Coolify installation
from Contabo to Hetzner with minimal reconfiguration.

The intended migration shape is:

1. Read-only inventory of Contabo and Hetzner.
2. Preflight checks for SSH, Docker, Coolify paths, disk, ports, and version.
3. Source backup during a maintenance window.
4. Transfer the backup to Hetzner.
5. Restore on Hetzner.
6. Test through a local hosts-file override.
7. Change DNS at IONOS.
8. Keep Contabo intact for 48-72 hours as rollback.

The scripts are deliberately split into phases. The inventory/preflight scripts
are read-only. The backup, transfer, and restore scripts require explicit
`--execute` flags and `.env` guardrails.

## Setup

```bash
cp .env.example .env
$EDITOR .env
```

Use a temporary SSH key for both servers. Do not put passwords, API tokens, or
Coolify secrets in this repository.

Minimum `.env` values:

```dotenv
SOURCE_HOST=contabo.example
SOURCE_USER=root
SOURCE_SSH_KEY=~/.ssh/coolify_migration

DEST_HOST=hetzner.example
DEST_USER=root
DEST_SSH_KEY=~/.ssh/coolify_migration

COOLIFY_VERSION=4.x.x
NEW_SERVER_IPV4=1.2.3.4
DOMAINS=app.example.com coolify.example.com
```

## Phase 1: read-only inventory

```bash
bash scripts/inventory.sh
bash scripts/preflight.sh
```

Inventory output is written under `artifacts/inventory/`. Commit neither
inventory artifacts nor backups; they may reveal infrastructure details.

## Phase 2: backup source

Run this only in the migration window. The safe default stops Docker on the
source while the byte-level archive is created, then starts Docker again.

```bash
bash scripts/backup-source.sh --execute
```

For important databases, keep `RUN_DB_DUMPS=true`. The script attempts
best-effort logical dumps before stopping Docker, then archives the stopped
Docker volumes for a 1:1 copy.

## Phase 3: transfer to destination

```bash
bash scripts/transfer-to-destination.sh --execute
```

The script streams the newest source backup to the destination and verifies
matching SHA256 checksums.

## Phase 4: restore destination

Restore requires stopping Docker on Hetzner. If the Counter-Strike server is
Docker-managed, it will be interrupted. Confirm this before setting the guard.

```dotenv
ALLOW_DESTINATION_DOCKER_STOP=true
```

Then:

```bash
bash scripts/restore-destination.sh --execute
bash scripts/verify-destination.sh
```

## Phase 5: hosts-file test and DNS cutover

Print local hosts-file lines:

```bash
bash scripts/print-hosts-overrides.sh
```

Test every domain against the Hetzner IP before changing IONOS DNS. See
[docs/CUTOVER.md](docs/CUTOVER.md).

## Safety model

- The source server stays unchanged during inventory and preflight.
- The final source backup is consistent only if Docker or the relevant database
  containers are stopped.
- A stopped DB volume tar is acceptable for a 1:1 Docker move.
- Logical DB dumps are still useful as a portable recovery fallback.
- The restore script refuses to pull latest Coolify unless explicitly allowed.
- The restore script refuses to overwrite an existing destination Coolify data
  directory unless explicitly allowed.

## References

- Coolify backup and restore:
  <https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify>
- Coolify application migration:
  <https://coolify.io/docs/knowledge-base/how-to/migrate-apps-different-host>
- Coolify specific-version upgrade/install command:
  <https://coolify.io/docs/get-started/upgrade>
