# Cutover Checklist

## Before migration day

- Lower IONOS DNS TTL for all relevant `A` and `AAAA` records to 300 seconds.
- Confirm source and destination are the same CPU architecture.
- Confirm Hetzner has enough free disk for `/data/coolify`, Docker volumes,
  selected bind mounts, and temporary backup archives.
- Confirm whether the Counter-Strike server on Hetzner is Docker-managed.
- Pin `COOLIFY_VERSION` to the version currently running on Contabo.
- Inventory outbound IP dependencies:
  - mail sending, SPF, DKIM, DMARC, PTR/reverse DNS
  - API allowlists
  - firewall rules on external systems
  - webhook providers that pin source IPs

## Dry test

- Run `scripts/inventory.sh`.
- Run `scripts/preflight.sh`.
- Review bind mounts and decide whether any path belongs in `EXTRA_BIND_PATHS`.
- Do not change DNS yet.

## Maintenance window

- Confirm users know writes may pause.
- Run `scripts/backup-source.sh --execute`.
- Run `scripts/transfer-to-destination.sh --execute`.
- Set `ALLOW_DESTINATION_DOCKER_STOP=true`.
- Run `scripts/restore-destination.sh --execute`.
- Run `scripts/verify-destination.sh`.

## Hosts-file test

Use `scripts/print-hosts-overrides.sh` to print the temporary entries.

On Windows, edit:

```text
C:\Windows\System32\drivers\etc\hosts
```

On Linux/macOS, edit:

```text
/etc/hosts
```

Test:

- Coolify dashboard login
- each app domain
- uploads and persistent files
- app databases
- background jobs
- webhooks
- outgoing mail
- OAuth callback flows

## DNS switch

- Update IONOS `A` and `AAAA` records to the Hetzner IPs.
- Keep Contabo running unchanged for 48-72 hours.
- Watch application logs and Coolify proxy logs.
- Restore DNS to Contabo if rollback is needed.

## After stabilization

- Raise DNS TTL back to the normal value.
- Revoke temporary SSH keys.
- Take a fresh Hetzner snapshot.
- Upgrade Coolify later in a separate maintenance window.
