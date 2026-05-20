# Migration Manifest

Last updated: 2026-05-20

## Servers

- Source: Contabo `167.86.89.139`
- Destination: Hetzner `46.225.165.11`
- SSH user: `root`
- SSH key path used locally: `~/.ssh/rcon-dev`

## Source Snapshot

- Hostname: `vmd162276`
- Architecture: `x86_64`
- Docker root: `/var/lib/docker`
- Docker version: `28.0.0`
- Coolify image: `ghcr.io/coollabsio/coolify:4.0.0`
- Coolify framework output: `Laravel Framework 12.55.1`
- `/data/coolify`: about `973M`
- `/var/lib/docker/volumes`: about `2.2G`
- Docker images: about `14.73G`
- Docker build cache: about `2.06G`
- Extra bind mount outside `/data/coolify`: `/data/strapi-public`
- Public database proxy on `5444`: disabled and verified

## Destination Snapshot

- Hostname: `ubuntu-8gb-nbg1-1`
- Architecture: `x86_64`
- Docker root: `/var/lib/docker`
- Docker version: `29.3.0`
- Free root disk after game-server cleanup: about `68G`
- Docker containers: none
- `/data/coolify`: not present
- Ports `80` and `443`: no listener during preflight

## Domains

Active or configured Coolify domains found on source:

- `api.ec4csokoo08os00ocsgsokw8.studio-virtuos.com`
- `console-uwsccoo8o84oswk4w0ss844g.studio-virtuos.com`
- `coolify.studio-virtuos.com`
- `ec4csokoo08os00ocsgsokw8.studio-virtuos.com`
- `minio-uwsccoo8o84oswk4w0ss844g.studio-virtuos.com`
- `n8n-m0gcwwokg80w400ogo8s0soo.studio-virtuos.com`
- `nades.studio-virtuos.com`
- `spacebot-wg8g8wossskwc4csco0ok000.studio-virtuos.com`
- `strapi-nades.studio-virtuos.com`
- `strapi-ori-offline.studio-virtuos.com`
- `strapi-ori-strapi.studio-virtuos.com`
- `strapi-ori.studio-virtuos.com`
- `studio-virtuos.com`
- `supabasekong-ookg0ocs00o00scgsoccc8og.studio-virtuos.com`

`www.studio-virtuos.com` was not found in active Coolify proxy labels and is
not part of the intended cutover.

## DNS Cutover Rule

At cutover, replace each used `A` record that points to `167.86.89.139` with
`46.225.165.11`.

Do not leave duplicate `A` records for the same hostname on both old and new
IPs. That would split traffic unpredictably. Rollback is done by changing those
records back to `167.86.89.139`.

## Next Required Operator Confirmation

- Confirm the maintenance window.
- Confirm Docker may be stopped on Contabo for the backup snapshot.
- Confirm the destination can be overwritten with the migrated Coolify data.
- Confirm whether all domains above should be tested/cut over, or whether any
  stale/offline entries should be excluded.
