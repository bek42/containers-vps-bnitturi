# portainer

Docker management UI. Reachable at `https://portainer.bnitturi.com` via Cloudflare tunnel.

## Service

| Service | Container | Image | Purpose |
|---|---|---|---|
| `portainer` | `portainer` | `portainer/portainer-ce:latest` | Web UI for managing Docker |

## Ports

- **127.0.0.1:9000 -> 9000** -- localhost-only; the Cloudflare tunnel proxies `portainer.bnitturi.com` to it.

## Secrets

None in this repo. Portainer's admin credentials are set on first run via the web UI and stored in its internal DB at `~/container-data/portainer/data/portainer.db`. Migrate via the data dir, not via git.

## Operations

```
make up
make down
make restart
make ps
make logs
```

## Permissions

Portainer has full Docker control via the mounted `/var/run/docker.sock` -- anyone who can log into the Portainer UI can effectively root the host through Docker. Protect the admin password accordingly. `no-new-privileges:true` is set to prevent the container itself from escalating, but that's defense-in-depth, not a substitute for a strong admin password.

## Recovery on a new host

1. Install `make`, `docker`, `docker compose`.
2. Clone repo, `cd portainer`.
3. Restore `~/container-data/portainer/data/` from backup (preserves users, stack defs, registry creds, etc.).
4. `make up`.

If you skip the restore, portainer initializes empty and prompts you to create a new admin user on first visit.

## Image pinning

Currently uses `portainer-ce:latest`. For more reproducible deploys, pin to a specific version (e.g. `portainer-ce:2.21.5`) and update intentionally.