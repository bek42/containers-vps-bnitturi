# vaultwarden

Vaultwarden (Bitwarden-compatible password manager) with daily encrypted backup to OneDrive. Reachable at `https://vault.bnitturi.com/safe/bems2304/` via Cloudflare tunnel.

> Migrated from a Docker Swarm stack to plain `docker compose` + sops. Old deploy docs (`docker stack deploy`, Swarm secrets) no longer apply.

## Services

| Service | Container | Image | Purpose |
|---|---|---|---|
| `vaultwarden` | `vaultwarden` | `vaultwarden/server:1.36.0`      | Password manager server |
| `vw-backup`   | `vw-backup`   | `ttionya/vaultwarden-backup:1.26.8` | Daily 05:05 backup, zipped, to OneDrive via rclone |

## Ports

- **127.0.0.1:8062 → 80** — localhost-only; the Cloudflare tunnel proxies `vault.bnitturi.com/safe/bems2304/*` to it.

## Secrets

Single sops-encrypted file: `vaultwarden.env`.

| Key | Feeds | Notes |
|---|---|---|
| `VW_DOMAIN`     | `DOMAIN`                      | Public URL incl. `/safe/bems2304` subpath |
| `VW_ADMIN_TOKEN`| `ADMIN_TOKEN`                 | `/admin` panel token |
| `VW_SMTP_HOST`  | `SMTP_HOST`                   | |
| `VW_SMTP_PORT`  | `SMTP_PORT`                   | |
| `VW_EMAIL`      | `SMTP_FROM` + `SMTP_USERNAME` | one value, two vars |
| `VW_EMAIL_PASS` | `SMTP_PASSWORD`               | |
| `VW_ZIP_PASS`   | `ZIP_PASSWORD` (vw-backup)    | backup archive password |

Edit with `make edit`.

## Operations

```bash
make up        # sops exec-env vaultwarden.env 'docker compose up -d'
make down      # docker compose down
make restart   # down + up
make edit      # sops edit vaultwarden.env
```

**Always go through `make up`.** Direct `docker compose up -d` starts vaultwarden with an empty `ADMIN_TOKEN`/`DOMAIN`/SMTP config.

## Data & backup

- Data dir: `~/container-data/vaultwarden/vw-data/` (SQLite DB, attachments, RSA keys) — the only persistent state, survives container recreation
- rclone config (OneDrive OAuth): `~/container-data/vaultwarden/vw-data/rclone` — part of the data dir, migrates with a data restore
- `vw-backup` runs daily at 05:05, zips the data (password = `VW_ZIP_PASS`), uploads to `OneDriveSync:/VaultwardenBackup/`, keeps 30 days

### Trigger a backup now

```bash
docker exec vw-backup backup
```

## Recovery on a new host

1. Install `age`, `sops`, `make`, `docker`, `docker compose`.
2. Place age private key at `~/.config/age/keys.txt`; symlink to `~/.config/sops/age/keys.txt`.
3. Clone repo, `cd vaultwarden`.
4. Restore `~/container-data/vaultwarden/vw-data/` from a OneDrive backup (includes the rclone config + DB + keys).
5. `make up`.

No Swarm init, no `docker secret create` — the seven values come from the encrypted `vaultwarden.env`.

## Troubleshooting

**Can't reach `/admin`.** `ADMIN_TOKEN` empty → you ran compose directly instead of `make up`.

**Backup not uploading.** Check rclone auth: `docker exec vw-backup rclone listremotes` should show `OneDriveSync:`. OAuth token may have expired; re-auth in the rclone config under the data dir.

**Emails not sending.** Verify SMTP values: `docker exec vaultwarden env | grep SMTP` (these are now plain env vars, visible here — by design with this pattern).
