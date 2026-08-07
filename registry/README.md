# registry

Self-hosted Docker registry with web UI and automated tag cleanup. Reachable at `https://reg.greatsky.co.uk` via Cloudflare tunnel → NPM.

## Services

| Service (compose) | Container | Image | Purpose |
|---|---|---|---|
| `registry`    | `registry`    | `registry:3.0`                  | OCI-compliant image registry |
| `registry-ui` | `registry-ui` | `joxit/docker-registry-ui:main` | Web interface for browsing |
| `regbot`      | `regbot`      | `regclient/regbot:latest`       | Weekly automated tag cleanup |

## Auth model

Authentication happens **at NPM** (Access List: `dockerhub`), not at the registry itself. The registry has no native auth configured.

Consequences:
- One auth dialog per `docker login reg.greatsky.co.uk`
- Internal services (regbot, registry-ui) reach `registry:5000` over the docker network without auth
- User management lives in the NPM admin UI, not in htpasswd files

Defense-in-depth via dual-layer auth is intentionally skipped — single user, single homelab, simpler operations.

## Ports

- **5000** — registry HTTP. Not published to the host; only reachable via the docker network and via NPM through `shared-proxy`.
- **8002** — registry-ui. Bound to `127.0.0.1:8002` only; access via NPM proxy host or SSH tunnel.

## Networks

- `default` — three services connected so regbot and registry-ui can resolve `registry:5000` by name
- `shared-proxy` (external) — only the registry service is on this; NPM proxies `reg.greatsky.co.uk` to it

## Operations

```bash
make up        # docker compose up -d
make down      # docker compose down
make restart   # down + up
```

This stack has no secrets — no sops, no encrypted env file. All configuration lives in plain YAML in this directory.

## Pushing images

```bash
docker login reg.greatsky.co.uk      # uses NPM access list creds
docker tag myapp:latest reg.greatsky.co.uk/myapp:v1
docker push reg.greatsky.co.uk/myapp:v1
```

For the automated login flow see the `docker-registry.env` / `make login` pattern at the repo root.

## Tag cleanup

`regbot` runs the Lua script in `regbot.yml` every 168h. For each repo it:

1. Lists all tags
2. Skips protected tags: `latest`, `stable`, `main`
3. Reads each tag's image creation timestamp
4. Keeps the 2 newest dated tags; falls back to alphabetical for tags without a date (multi-arch buildx images)
5. Deletes everything else

Tag deletion alone doesn't free disk space — only references. `gc.sh` (Sunday 3am, via bharani's user crontab — `make install-cron`) runs the registry's garbage collector to reclaim storage. `gc.sh` pipes its output through `tee` rather than a plain `>>` redirect, so a full disk (which can make the log file itself unwritable) can't silently prevent GC from running — that's what happened on 2026-07-12: the registry filled to 100% and the weekly job left no trace at all because the log redirect failed before the cleanup command ever started. Log lives at `~/container-data/registry/gc.log`, not `/var/log`, so it doesn't need root to write.

### Manual operations

```bash
# Force a cleanup run now:
docker compose run --rm regbot -c /home/appuser/regbot.yml once

# Dry-run:
docker compose run --rm regbot -c /home/appuser/regbot.yml once --dry-run

# Force GC now:
docker exec registry registry garbage-collect --delete-untagged /etc/distribution/config.yml

# Disk usage:
du -sh /home/bharani/container-data/registry/

# List repos / tags:
curl -u USER:PASS https://reg.greatsky.co.uk/v2/_catalog
curl -u USER:PASS https://reg.greatsky.co.uk/v2/<repo>/tags/list
```

## Recovery on a new host

1. Install `make`, `docker`, `docker compose`.
2. Clone repo, `cd registry`.
3. Restore `~/container-data/registry/data/` from backup if you want to keep existing images.
4. `make install-cron` (no sudo needed — installs into the current user's crontab).
5. `make up`.

Data dir is the only state. Auth lives in the NPM stack — restore that volume separately.

## Tuning

`regbot.yml`:

```lua
keep_count = 2                                                       -- retention
protected = { ["latest"] = true, ["stable"] = true, ["main"] = true } -- never-delete tags
```

```yaml
defaults:
  interval: 168h   # 24h for daily, 720h for monthly
```

Then `make restart`.

## Troubleshooting

**regbot logs are empty.** Server mode is silent until the next scheduled run. Force a one-time run:
```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once
```

**"could not read config" for some tags.** Multi-arch buildx images don't have a single creation timestamp. The script falls back to alphabetical sort for these — expected, not a problem.

**Registry won't delete tags (405).** Verify `config.yml` has `storage.delete.enabled: true`.

**403 in browser, 401 from CLI.** The 401 is correct — `docker login` once and the CLI works. A browser 403 usually means the NPM Access List has `Satisfy: All` with `0 Rules`; set Satisfy to `Any` or add an `allow 0.0.0.0/0` rule.

**Disk fills up and pushes start failing with 500s.** Check `df -h /` first. Since `regbot` only prunes to `keep_count` tags per repo, sustained growth across many repos can still fill the disk faster than the weekly GC reclaims it. Force both manually:
```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once
docker exec registry registry garbage-collect --delete-untagged /etc/distribution/config.yml
```
Verify `crontab -l` actually contains the `gc.sh` line — a disk that reaches 100% can prevent the job's own log write (and, before the `tee` fix, silently prevented the job from running at all).
