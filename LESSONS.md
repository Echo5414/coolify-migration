# Coolify Migration Lessons

These notes capture the real issues hit during the Contabo to Hetzner migration.
They are operational lessons, not a replacement for the normal cutover checklist.

## Source Freeze

- `KEEP_SOURCE_DOCKER_STOPPED=true` is the right cutover behavior. The old
  source should stay frozen until the new server is verified.
- Do not run `docker ps` on the frozen source if `docker.socket` is still
  active. Docker socket activation can restart the daemon and briefly bring
  containers back online.
- For a hard freeze, stop both services on the source:

```bash
systemctl stop docker.service docker.socket
systemctl is-active docker.service
systemctl is-active docker.socket
```

- If the source accidentally wakes up after the first archive, create a second
  archive from the stopped on-disk state and use that as the canonical cutover
  archive.

## Backup Shape

- A `/data/coolify` plus Docker volume archive may not be enough for local-built
  applications. Some Coolify applications depend on image tags and container
  metadata that are not reconstructable from compose files alone.
- If locally built images are present and rebuild inputs are missing, a stopped
  `/var/lib/docker` archive is the practical 1:1 fallback. It preserves images,
  containers, networks, and volumes together.
- This fallback is closer to a full Docker-root clone than the staged toolkit
  path. Treat it as a deliberate recovery route and document that it was used.

## Restore Side Effects

- Avoid broad ownership rewrites under `/data/coolify`. A recursive `chown` can
  break mounted service config files. In this run, Supabase Kong failed until
  its mounted `kong.yml` ownership and permissions were repaired.
- After replacing `/var/lib/docker`, remove stale bridge interfaces/routes left
  from the destination's previous Docker root. A stale down bridge can own the
  same subnet as the restored `coolify` network and cause host-to-container
  traffic on published ports to reset.

Useful checks:

```bash
ip route show
ip route get 10.0.1.3
curl -sS http://127.0.0.1/ping
```

If a stale bridge owns the route, delete the stale bridge interface, then retest
the proxy.

## Networking And Firewalls

- Open Hetzner UFW ports `80/tcp` and `443/tcp` only after restore and before
  domain testing.
- A container can be running and healthy while published ports fail from the
  host if Docker bridge routing is wrong.
- Public IP hairpin assumptions do not always survive a provider move. Hetzner
  commonly uses a `/32` IPv4 setup; containers should not rely on connecting to
  the host's public IP to reach another local service.
- Prefer service DNS names on a shared Docker network over host public IPs for
  app-to-app or app-to-database traffic.

## Hardcoded IPs

- Search the restored Coolify tree for the old source IP before DNS cutover:

```bash
grep -RIl 'OLD_SOURCE_IP' /data/coolify 2>/dev/null
```

- Separate active container references from stale app folders and backup files.
  A stale `.env` in an inactive app folder is not automatically a blocker.
- For active apps, fix the Coolify source of truth where possible. Manual
  compose edits can be overwritten later by Coolify regeneration.

## Coolify Localhost Server

- After restoring Coolify to a new host, the dashboard can show applications as
  "Server is unreachable or misconfigured" even when their containers are
  running and serving traffic.
- Cause: Coolify's `localhost` server record uses an SSH key copied from the old
  installation. The new Hetzner root account must trust the matching public key.
- Fix: add the public key for Coolify's `localhost` private key to
  `/root/.ssh/authorized_keys` on the destination and test from inside the
  Coolify container:

```bash
docker exec coolify ssh -i /var/www/html/storage/app/ssh/keys/ssh_key@UUID \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=no \
  root@host.docker.internal 'docker version'
```

- After successful SSH validation, Coolify's server state should become
  reachable and usable.

## Coolify Instance Metadata

- The migrated Coolify database can still contain the old public IPv4 in
  `instance_settings.public_ipv4`.
- Update it to the new Hetzner IPv4 after restore:

```sql
update instance_settings
set public_ipv4 = 'NEW_SERVER_IPV4', updated_at = now()
where id = 0;
```

## Domain Testing

- Testing `https://SERVER_IP/path` is not equivalent to testing a migrated
  Coolify app. Traefik routes by the `Host` header, and TLS certificates are
  issued for domains, not the bare IP.
- Use hosts-file overrides, `curl --resolve`, or a controlled test proxy so the
  browser still requests the real domain while the connection goes to Hetzner.
- HTTP status codes are only smoke tests. A `200`, `302`, `401`, `403`, or `404`
  can all be correct depending on the app and route. Test real paths such as:
  dashboard login, app login, API health/status endpoint, and admin pages.

## DNS Cutover

- Move only active domains. Do not blindly update every DNS record that points
  at the source IP.
- In this migration, some IONOS records were intentionally excluded because no
  active containers routed them on the source or destination.
- Router DNS caches can outlive the new 300 second TTL if the router cached the
  old answer before TTL was lowered. A local FritzBox still served the old
  Contabo IP while Cloudflare and Google already returned Hetzner.
- Verify with multiple resolvers:

```powershell
Resolve-DnsName coolify.example.com -Type A
Resolve-DnsName coolify.example.com -Type A -Server 1.1.1.1
Resolve-DnsName coolify.example.com -Type A -Server 8.8.8.8
```

- Mobile data is a useful independent DNS and reachability check.

## Rollback

- Keep Contabo Docker stopped after cutover backup to avoid split-brain writes.
- If rollback is needed:

```bash
# 1. Change DNS back to the source IP.
# 2. Stop Docker on Hetzner.
systemctl stop docker.service docker.socket

# 3. Start Docker on Contabo.
systemctl start docker
```

- Do not delete source data, destination checkpoints, or Docker-root backups
  until the rollback window has passed.

## Cleanup After Stabilization

- Raise DNS TTL back to the normal value.
- Remove temporary SSH keys that were only needed for migration.
- Rotate any server passwords or keys that were exposed during the migration.
- Delete destination checkpoints and old Docker-root backups only after the
  rollback window closes and the new server is stable.
- Plan Coolify upgrades separately. Do not combine migration and upgrade in the
  same maintenance window.
