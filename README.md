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

## Backup Path Decision

Choose the backup path before the maintenance window:

1. Run inventory and check whether active Coolify apps use local-built images,
   for example compose services with `build:` or image names that are not pulled
   from a registry.
2. If local-built images or unrebuildable container metadata are present, use
   the Docker-root fallback from the start: `backup-docker-root.sh`,
   `transfer-to-destination.sh`, then `restore-docker-root.sh`.
3. If every active app can be recreated from registry images plus volumes, the
   staged path is fine: `backup-source.sh`, `transfer-to-destination.sh`, then
   `restore-destination.sh`.

## Setup

```bash
cp .env.example .env
$EDITOR .env
```

For local development, `.env.develop` is also supported. If `.env` does not
exist, scripts will load `.env.develop`; you can also force a file with
`ENV_FILE=.env.develop`.

Use a temporary SSH key for both servers. Do not put passwords, API tokens, or
Coolify secrets in this repository.

If the source server currently only accepts password login, put the password in
local `.env.develop` and run this one-time bootstrap from your trusted machine:

```bash
python scripts/bootstrap-source-key.py --execute
```

That appends the public key matching `SOURCE_SSH_KEY` to the source user's
`~/.ssh/authorized_keys`. After that, remove `SOURCE_PASSWORD` from local env
files and use key-based scripts.

Minimum `.env` values:

```dotenv
SOURCE_HOST=contabo.example
SOURCE_USER=root
SOURCE_SSH_KEY=~/.ssh/coolify_migration

DEST_HOST=hetzner.example
DEST_USER=root
DEST_SSH_KEY=~/.ssh/coolify_migration

COOLIFY_VERSION=4.x.x
SOURCE_DOCKER_ROOT=/var/lib/docker
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
The inventory scripts intentionally avoid full `docker inspect`, container
environment variables, raw process command lines, and logs because those can
contain secrets.

## Phase 2: backup source

Run this only in the migration window. The safe default stops Docker on the
source while the byte-level archive is created, then starts Docker again.

```bash
bash scripts/backup-source.sh --execute
```

For a final cutover where Contabo must stay frozen after the backup snapshot,
set:

```dotenv
KEEP_SOURCE_DOCKER_STOPPED=true
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

If locally built images or container metadata cannot be recreated from the
standard archive, use the stopped Docker-root fallback instead of improvising:

```bash
# Source: create a stopped /var/lib/docker archive.
bash scripts/backup-docker-root.sh --execute

# Transfer the generated docker-root archive.
BACKUP_FILE=/root/coolify-migration/backups/<run-id>/docker-root-<run-id>.tar.gz \
  bash scripts/transfer-to-destination.sh --execute

# Destination: replace /var/lib/docker with the transferred archive.
RESTORE_DOCKER_ROOT=true MOVE_EXISTING_DEST_DOCKER_ROOT=true \
  bash scripts/restore-docker-root.sh --execute
```

After restore, repair Coolify's local server SSH trust and public instance IP:

```bash
bash scripts/fix-coolify-localhost.sh --execute
```

## Phase 5: hosts-file test and DNS cutover

Print local hosts-file lines:

```bash
bash scripts/print-hosts-overrides.sh
```

Test every domain against the Hetzner IP before changing IONOS DNS. See
[docs/CUTOVER.md](docs/CUTOVER.md).

Operational pitfalls and fixes from the real Contabo to Hetzner migration are
captured in [LESSONS.md](LESSONS.md).

## Safety model

- The source server stays unchanged during inventory and preflight.
- The final source backup is consistent only if Docker or the relevant database
  containers are stopped.
- A stopped DB volume tar is acceptable for a 1:1 Docker move.
- Logical DB dumps are still useful as a portable recovery fallback.
- The restore script refuses to pull latest Coolify unless explicitly allowed.
- The restore script refuses to overwrite an existing destination Coolify data
  directory unless explicitly allowed.
- Verification does not print logs unless `SHOW_VERIFY_LOGS=true`.

## References

- Coolify backup and restore:
  <https://coolify.io/docs/knowledge-base/how-to/backup-restore-coolify>
- Coolify application migration:
  <https://coolify.io/docs/knowledge-base/how-to/migrate-apps-different-host>
- Coolify specific-version upgrade/install command:
  <https://coolify.io/docs/get-started/upgrade>
