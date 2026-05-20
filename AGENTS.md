# AGENTS

## Purpose

This repository is the control point for migrating one Coolify instance from a
Contabo server to a Hetzner server.

## Safety Rules

- Treat Contabo as production until DNS has moved and Hetzner is verified.
- Inventory and preflight must remain read-only.
- Do not stop Docker, copy backups, restore archives, or change DNS unless the
  operator explicitly starts that phase.
- Do not commit `.env`, private keys, backups, dumps, inventories, or secrets.
- Use `.env.example` only for placeholders and variable names.
- Keep `COOLIFY_VERSION` pinned during migration. Do not combine migration and
  Coolify upgrade in the same window.
- For database containers, prefer both a stopped volume archive and a logical
  dump for important data.
- Confirm whether the Hetzner Counter-Strike server is Docker-managed before
  any destination restore, because restore stops Docker.

## Workflow

1. Run `scripts/inventory.sh`.
2. Review bind mounts, Docker root, disk usage, ports, Coolify version, and
   Counter-Strike process/container state.
3. Run `scripts/preflight.sh`.
4. Fill or adjust `.env`.
5. During the maintenance window, run backup, transfer, restore, and verify.
6. Test with hosts-file overrides before IONOS DNS changes.
7. Keep Contabo intact for 48-72 hours as rollback.
