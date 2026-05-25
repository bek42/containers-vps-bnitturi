# nginx

Nginx Proxy Manager (NPM) + MariaDB-Aria. The HTTPS frontend for everything on the VPS, plus the SQL store NPM uses to persist proxy host configs.

## Services

| Service (compose) | Container | Image | Purpose |
|---|---|---|---|
| `app` | `nginx` | `jc21/nginx-proxy-manager:2.14.0` | Reverse proxy + admin UI |
| `db`  | `mariadb` | `jc21/mariadb-aria:10.11.5` | NPM's data store |

**Service name vs container name matters.** Compose commands use the service name (`docker compose logs app`); raw docker uses the container name (`docker logs nginx`).

## Ports

| Port | Purpose |
|---|---|
| 80  | HTTP (redirects to 443 for proxied hosts) |
| 81  | NPM admin UI |
| 443 | HTTPS |

## Networks

Owns `shared-proxy`. Other stacks (registry, future stacks) attach to it as `external: true` so NPM can reach them by container name. This compose declares the network locally (not external) — it gets created on `make up` and other stacks join it.

## Secrets

Single sops-encrypted file: `nginx.env`. Contains:

- `DB` — password for the `npm` MySQL user
- `DB_RT` — MariaDB root password

Both values are AES-encrypted at rest; the file is safe to commit. Variable names stay readable in git so diffs make sense.

## Operations

```bash
make up        # sops exec-env nginx.env 'docker compose up -d'
make down      # docker compose down
make restart   # down + up
make edit      # sops edit nginx.env (decrypts to tempfile, re-encrypts on save)
```

**Always go through `make up`.** Running `docker compose up -d` directly starts the containers with empty `${DB}` and `${DB_RT}` (compose will warn), and NPM will silently fail to authenticate against the existing MariaDB volume.

## Data

Persistent host paths (preserved across container recreates):

- `~/container-data/ngnix/data` — NPM config, proxy hosts, SSL settings
- `~/container-data/ngnix/letsencrypt` — TLS certs from Let's Encrypt
- `~/container-data/ngnix/mariadb-aria/data` — MariaDB data dir

(`ngnix` is misspelled in the filesystem path. Left as-is to avoid breaking the volume mount.)

## Recovery on a new host

1. Install `age`, `sops`, `make`, `docker`, `docker compose`.
2. Place age private key at `~/.config/age/keys.txt` (chmod 600).
3. Symlink: `mkdir -p ~/.config/sops/age && ln -s ~/.config/age/keys.txt ~/.config/sops/age/keys.txt`.
4. Clone repo and `cd nginx`.
5. Restore `~/container-data/ngnix/` from backup if you want to keep existing proxy hosts and certs.
6. `make up`.

If step 5 is skipped, NPM initializes a fresh DB on first start with the credentials from `nginx.env`, and you re-create proxy hosts through the admin UI.
