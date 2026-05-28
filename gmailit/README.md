# gmailit (SimpleLogin)

Self-hosted [SimpleLogin](https://simplelogin.io/) — email aliasing service. Exposed at `https://app.gmailit.com` via Cloudflare tunnel.

For initial setup and upgrade procedure see `SimpleLogin-Setup-Upgrade-Guide.md` in this directory.

## Services

| Service (compose) | Container | Image | Purpose |
|---|---|---|---|
| `postfix`    | `postfix`       | `private/postfix:latest` (built locally) | SMTP server (ports 25, 587) |
| `postgres`   | `sl-db`         | `postgres:12.1`                          | Application DB |
| `migration`  | `sl-migration`  | `simplelogin/app:4.6.5-beta`             | One-shot DB migration |
| `init`       | `sl-init`       | `simplelogin/app:4.6.5-beta`             | One-shot init after migration |
| `app`        | `sl-app`        | `simplelogin/app:4.6.5-beta`             | Web UI/API on `127.0.0.1:7777` |
| `email`      | `sl-email`      | `simplelogin/app:4.6.5-beta`             | Incoming mail handler |
| `job-runner` | `sl-job-runner` | `simplelogin/app:4.6.5-beta`             | Background jobs |

## Ports

- **25 / 587** — SMTP, publicly exposed (required for incoming mail)
- **127.0.0.1:7777** — App HTTP, localhost-only; the cloudflared tunnel proxies `app.gmailit.com` to it

## Configuration

Two env files, split by sensitivity:

| File | In git? | Contents |
|---|---|---|
| `.env`            | yes (plain) | Public config — `DOMAIN`, `URL`, `DKIM_*`, `POSTGRES_DB`, `POSTGRES_USER`, etc. |
| `simplelogin.env` | yes (sops-encrypted) | Secrets — `POSTGRES_PASSWORD`, `FLASK_SECRET`, `DB_URI` |

Edit secrets with `make edit`. Edit public config by editing `.env` directly.

Six services share the same secret vars; the compose uses a YAML anchor (`x-sl-secret-env`) to declare them once and reference them per-service.

## Operations

```bash
make up        # sops exec-env simplelogin.env 'docker compose -f simple-login-compose.yaml up -d'
make down      # docker compose -f simple-login-compose.yaml down
make restart   # down + up
make edit      # sops edit simplelogin.env
```

**Always go through `make up`.** A direct `docker compose -f simple-login-compose.yaml up -d` starts containers with empty `POSTGRES_PASSWORD`/`FLASK_SECRET`/`DB_URI`, and the app fails at startup.

## Recovery on a new host

1. Install `age`, `sops`, `make`, `docker`, `docker compose`.
2. Place age private key at `~/.config/age/keys.txt`; symlink to `~/.config/sops/age/keys.txt`.
3. Clone repo, `cd gmailit`.
4. Restore `~/container-data/gmailit/` from backup (DB volume, DKIM keys, postfix configs, ACME certs).
5. Confirm MX / DKIM / SPF DNS records are in place per `SimpleLogin-Setup-Upgrade-Guide.md`.
6. `make up`.

## Rotating secrets

If you rotate `POSTGRES_PASSWORD`, remember to update `DB_URI` in the same edit — it contains the password inline. Otherwise the app and the DB will diverge and half the services will fail to connect:

```bash
make edit
# update both POSTGRES_PASSWORD and DB_URI in the same save
make restart
```

## Troubleshooting

**App or DB fails with "POSTGRES_PASSWORD: undefined" / "DB_URI: undefined".** You ran compose directly instead of via `make up`. The sops exec-env wrapper is what populates the variables.

**Half the services start, half can't reach the DB.** `DB_URI` and `POSTGRES_PASSWORD` drifted apart (one was rotated without the other). Reconcile in `make edit` and `make restart`.
