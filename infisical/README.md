# infisical

Self-hosted secrets manager. Exposed at `https://v0u1t.bnitturi.com` via Cloudflare tunnel.

## Services

| Service (compose) | Image | Purpose |
|---|---|---|
| `infisical` | `infisical/infisical` | Web UI + API on port 8080 |
| `redis`     | `redis:7-alpine` | Queue and cache backend |

PostgreSQL is hosted externally on **Neon** (free tier, no maintenance).

## Secrets

Single sops-encrypted file: `infisical.env`. Contents:

| Key | Encrypted | Notes |
|---|---|---|
| `DB_CONNECTION_URI` | yes | Neon Postgres connection string |
| `REDIS_URL`         | yes | `redis://infisical-redis:6379` |
| `ENCRYPTION_KEY`    | yes | 32-char hex — encrypts stored secrets |
| `AUTH_SECRET`       | yes | 32-char hex — signs session JWTs |
| `SITE_URL`          | no  | Plain via `.sops.yaml` (`unencrypted_regex`) |

Variable names stay readable in git; values are AES-encrypted. Safe to commit.

Edit with `make edit`.

## Operations

```bash
make up        # sops exec-env infisical.env 'docker compose up -d'
make down      # docker compose down
make restart   # down + up
make edit      # sops edit infisical.env
```

**Always go through `make up`.** A direct `docker compose up -d` starts the containers with empty env vars and infisical aborts at startup with `AUTH_SECRET: undefined`.

## Upgrade

```bash
docker compose pull
make restart
```

## Status

```bash
docker compose ps
docker compose logs infisical
docker compose logs redis
```

## Data

- `~/container-data/infisical/redis` — Redis persistence (AOF/RDB)

Application data lives in Neon, not on this host. Local backups aren't needed for Postgres state — Neon handles that.

## Recovery on a new host

1. Install `age`, `sops`, `make`, `docker`, `docker compose`.
2. Place age private key at `~/.config/age/keys.txt` (chmod 600).
3. Symlink: `mkdir -p ~/.config/sops/age && ln -s ~/.config/age/keys.txt ~/.config/sops/age/keys.txt`.
4. Clone repo, `cd infisical`.
5. `make up`.

Because Postgres is on Neon, infisical re-connects to the same DB and picks up where it left off. No local restore step.

## Rotating keys

```bash
openssl rand -hex 16   # generate; run twice if rotating both
make edit              # paste new value(s)
make restart
```

**Warning**: rotating `ENCRYPTION_KEY` after secrets exist in the DB makes them unreadable. Only rotate it on a fresh install, or with a planned re-encryption migration. `AUTH_SECRET` is safe to rotate at any time — only effect is invalidating existing sessions (users log in again).
