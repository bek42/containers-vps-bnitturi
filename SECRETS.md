# Secrets management

How this repo handles secrets, why, and what to do on a new VPS.

## The patterns

Three patterns coexist, chosen by the shape of what's being protected:

| Pattern | When | Stacks |
|---|---|---|
| **sops + `exec-env`** | Secret is a set of named values consumed as env vars by the container | nginx, infisical, gmailit, vaultwarden |
| **Plain age** | Secret is a blob file the container reads from disk (no env-var interface) | tunnel |
| **No encrypted state** | Auth lives elsewhere (NPM Access List, internal DB) | registry, portainer |

### sops + exec-env

For env-var-shaped secrets. The flow:

1. Values stored in `<stack>/<name>.env`, sops-encrypted with the age recipient (see `.sops.yaml` at repo root)
2. Variable *names* stay readable in git; *values* appear as `ENC[AES256_GCM,...]`
3. `make up` runs `sops exec-env <name>.env 'docker compose up -d'` — sops decrypts in memory, exports vars to the subprocess shell, compose interpolates them into containers
4. No plaintext touches disk

Editing: `make edit` opens the decrypted file in `$EDITOR` with sops handling re-encrypt automatically on save.

### Plain age

For blob-shaped secrets the container reads from disk (cloudflared's tunnel JSON credentials):

1. Encrypted file `<name>.age` is committed
2. Decrypted file `<name>` is gitignored
3. `make up` decrypts → `docker compose up -d`
4. The plaintext file persists (gitignored) while the container runs, because the bind mount needs it

Less elegant than sops, but cloudflared can't take its credentials via env vars.

### No encrypted state

Registry uses NPM's Access List for auth — there are no registry-level secrets to encrypt. Portainer's admin credentials live in its data volume (`~/container-data/portainer/data/portainer.db`). Migration for these is "restore the data volume" — no secret-side work.

## Per-stack quick reference

| Stack | Encrypted file | Pattern | Notes |
|---|---|---|---|
| nginx | `nginx.env` | sops exec-env | mariadb root + npm-user passwords |
| infisical | `infisical.env` | sops exec-env | Neon DB URI, encryption + auth keys |
| gmailit | `simplelogin.env` | sops exec-env | `DB_URI` must be inlined (see Gotchas) |
| registry | — | (none) | NPM Access List handles auth |
| tunnel | `cloudflared/<id>.json.age` | plain age | cloudflared tunnel credentials |
| vaultwarden | `vaultwarden.env` | sops exec-env | Was Swarm; now compose. ADMIN_TOKEN should be Argon2id PHC string |
| portainer | — | (none) | Admin user inside data volume |

## Prerequisites on the VPS

```bash
sudo apt update
sudo apt install -y age make

# sops via direct download (no apt package on Ubuntu plucky):
SOPS_VER=3.13.1
curl -fsSLo /tmp/sops "https://github.com/getsops/sops/releases/download/v${SOPS_VER}/sops-v${SOPS_VER}.linux.amd64"
chmod +x /tmp/sops
sudo mv /tmp/sops /usr/local/bin/sops

# age private key
mkdir -p ~/.config/age
${EDITOR:-vi} ~/.config/age/keys.txt    # paste your saved private key
chmod 600 ~/.config/age/keys.txt

# sops looks for age keys here too
mkdir -p ~/.config/sops/age
ln -s ~/.config/age/keys.txt ~/.config/sops/age/keys.txt
```

Sanity check:
```bash
age --version && sops --version && make --version && docker compose version
```

## Bootstrap a fresh VPS

1. Install prerequisites above
2. `git clone git@github.com:bek42/containers-vps-bnitturi.git ~/containers`
3. Restore data dirs from backup (everything under `~/container-data/<stack>/`)
4. For each stack: `cd ~/containers/<stack> && make up`

Order: bring up nginx first (other stacks depend on its `shared-proxy` network), then the rest.

For registry, additionally run `sudo make install-cron` once to install the weekly GC cron.

## Day-to-day operations

Every stack with secrets exposes the same Makefile interface:

```bash
make up        # start (decrypt + docker compose up -d, wrapped in sops)
make down      # stop
make restart   # down + up
make edit      # open the encrypted file in your editor
make ps        # docker compose ps (sops-wrapped, no WARN noise)
make logs      # docker compose logs --tail 30 -f (sops-wrapped)
```

Stacks without secrets (registry, portainer) skip `make edit`. Tunnel adds `make encrypt` for re-encrypting after rotation.

## Gotchas (the things we learned the hard way)

### sops's env-file parser does NOT strip surrounding quotes

Bash strips surrounding `'...'` or `"..."` when reading env vars; sops's parser doesn't — the quotes become part of the value. So this:

```
ADMIN_TOKEN='$argon2id$v=19$...'
```

results in the container seeing `'$argon2id$v=19$...'` (literal leading quote), which breaks anything expecting the value to start with `$`. **Never wrap values in quotes** in sops-managed `.env` files. The `$` characters are safe unquoted — sops doesn't do shell-style `$VAR` expansion on values.

### Variable templates in `env_file` don't survive the switch to passthrough

If your old `env_file:`-based config had a value like:
```
DB_URI=postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@host/db
```
that interpolation was being performed by docker compose at file-load time using the project `.env`. Once you switch to `environment: ${DB_URI}` (sops passthrough), the literal `$POSTGRES_USER` is what flows through — there's no cross-interpolation between the sops shell env and the compose env_file env.

**Fix:** inline the values. `DB_URI=postgresql://simplelogin:realpassword@sl-db:5432/simplelogin` is robust regardless of loading mechanism. The password gets duplicated (`POSTGRES_PASSWORD` and inside `DB_URI`) — rotate them together.

### Bind-mounted credential files need mode 644, not 600

If a container reads a bind-mounted credential, the container's user (often a non-root UID like 65532) must be able to read the file. `chmod 600` makes it owner-only on the host (typically UID 1000), which the container's user can't see — `permission denied`. Use `644` for bind-mounted credentials. The file is gitignored and the host is single-user — the practical security delta is negligible.

### Service name vs container name in `docker compose` commands

```
docker compose logs app        # SERVICE name (the YAML key under services:)
docker logs nginx              # CONTAINER name (set by container_name:)
```

Compose commands use the service; raw docker commands use the container. Mix them up and you get `no such service` errors.

### Vaultwarden's `DOMAIN` has no trailing slash

`DOMAIN=https://vault.example.com/subpath` — no `/` at the end. Vaultwarden builds URLs by appending paths, and a trailing slash produces double-slash URLs that break OIDC, password-reset emails, and some clients.

### Always go through `make up`, never plain `docker compose up`

A direct `docker compose up -d` starts containers with empty values (compose warns `the X variable is not set, defaulting to a blank string`), then the app dies at startup. The `sops exec-env` wrapper inside `make up` is what populates the variables compose needs.

### WARN messages from read-only compose commands are harmless

`docker compose` parses the entire compose file for every subcommand, so it warns about `${VW_X}`-style placeholders any time the shell doesn't have them set. The containers were already created with correct values from `make up`, so the warnings have no effect. The Makefiles in this repo wrap `ps`/`down`/`logs` in `sops exec-env` too, which suppresses the warnings entirely.

### Tunnel decrypted JSON gets recreated on every `make up`

By design — the Makefile's `up` target runs `age --decrypt` before `docker compose up -d`. If you ever manually edit the decrypted JSON for testing, your changes are lost next `make up`. The source of truth is the `.age` file; use `make encrypt` to re-encrypt after legitimate rotations.

## Rotation

For sops-managed secrets:
```bash
cd ~/containers/<stack>
make edit       # update the value, save
make restart    # recreate containers with new value
```

If a value lives in two places (gmailit `POSTGRES_PASSWORD` <-> `DB_URI`), update both in the same `make edit` session.

For plain-age secrets (tunnel):
```bash
# put new plaintext JSON at cloudflared/<id>.json
make encrypt
make restart
git add cloudflared/*.json.age
git commit -m "tunnel: rotate credential"
git push
```

For no-encrypted-state stacks: rotate via the respective UI (NPM Access List for registry, Portainer admin for portainer).

## File layout

```
~/containers/
├── .sops.yaml                          # sops rules (age recipient, unencrypted_regex)
├── recipients.txt                      # age public key
├── SECRETS.md                          # this file
│
├── nginx/        { docker-compose.yml, Makefile, README.md, nginx.env (encrypted) }
├── infisical/    { docker-compose.yml, Makefile, README.md, infisical.env (encrypted) }
├── gmailit/      { simple-login-compose.yaml, Makefile, README.md,
│                   .env (plain config), simplelogin.env (encrypted) }
├── registry/     { docker-compose.yml, Makefile, README.md,
│                   config.yml, regbot.yml, gc.sh   # no encrypted state }
├── tunnel/       { docker-compose.yml, Makefile, README.md, .gitignore,
│                   cloudflared/{<id>.json.age, config.yml, hosts}
│                   cloudflared/<id>.json is decrypted at make up time, gitignored }
├── vaultwarden/  { docker-compose.yml, Makefile, README.md, vaultwarden.env (encrypted) }
└── portainer/    { docker-compose.yml, Makefile, README.md   # no encrypted state }
```

`~/container-data/` holds per-stack data volumes — lives outside the repo, restored from backup separately.

`~/secrets/` no longer exists. If anything still references it, that's a bug to fix.

## When something breaks

| Symptom | Likely cause | Fix |
|---|---|---|
| `AUTH_SECRET undefined` / `POSTGRES_PASSWORD undefined` / similar at container startup | Ran `docker compose up` directly instead of `make up` | Use `make up` |
| 502 from public URL right after `make restart` | Container's still booting | Wait 20-30s |
| `no such service` from `docker compose logs <X>` | Used container name where service name expected | Use the YAML service key |
| `permission denied` on a bind-mounted credential | File is mode 600; container's user can't read | `chmod 644 <file>` |
| App fails with literal `$POSTGRES_USER` in an error | Templated value in sops file not getting interpolated | Inline the values |
| 403 from curl but browser works | Cloudflare bot challenge on non-browser UA | Test in a browser, not curl |
| sops command fails: `Could not get data key` | Age private key missing / wrong recipient | Check `~/.config/age/keys.txt` and `.sops.yaml` recipient |