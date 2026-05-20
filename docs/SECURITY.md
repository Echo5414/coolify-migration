# Security Notes

- Never commit `.env`, private SSH keys, backups, database dumps, or inventory
  artifacts.
- Use a temporary SSH key for migration access.
- Prefer root SSH only for the short migration window, then revoke it.
- Do not give DNS provider credentials to automation unless a temporary,
  limited-permission account is available.
- Treat backup archives as secret material. They contain Coolify configuration,
  app data, database files, SSH keys used by Coolify, and possibly logical DB
  dumps.
- Delete local and remote backup archives only after Hetzner has been stable
  and an independent backup exists.
