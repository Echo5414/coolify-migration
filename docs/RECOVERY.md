# Recovery Notes

## Rollback

The fastest rollback is DNS-level:

1. Point IONOS records back to the Contabo IP.
2. Keep Hetzner running for diagnosis.
3. Do not delete Contabo data until the Hetzner migration has been stable for
   at least 48-72 hours.

## Database fallback

The backup archive contains Docker volume data. If `RUN_DB_DUMPS=true`, it also
contains best-effort logical dumps under the migration payload directory.

Use volume data for the closest 1:1 restore. Use logical dumps if a database
container starts but the data directory has ownership, version, or corruption
issues.

## Coolify APP_KEY

This toolkit archives the full `/data/coolify` directory by default, including
`/data/coolify/source/.env`. That preserves the original `APP_KEY`.

If you ever restore only a Coolify database backup into a fresh Coolify install,
follow the official Coolify flow and set the old key as `APP_PREVIOUS_KEYS`.
