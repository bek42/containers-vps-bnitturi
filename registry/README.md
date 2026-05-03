# Docker Registry with Automated Cleanup

A self-hosted Docker registry with web UI and automated tag cleanup. Designed to be portable across VPSs — clone the repo, set credentials, run two commands.

## What this does

- **Registry** (port 5000) — private Docker image registry with htpasswd auth
- **Registry UI** (port 8002) — web interface for browsing images
- **Regbot** — automated cleanup that runs weekly, keeping only the 2 most recent tags per repo (plus `latest`/`stable`/`main` always)
- **GC cron** — Sunday 3am, reclaims actual disk space after tag deletions

## Files

```
registry/
├── README.md           ← this file
├── docker-compose.yml  ← all 3 services
├── config.yml          ← registry config (auth, storage, etc.)
├── regbot.yml          ← cleanup script (Lua-based)
├── gc.sh               ← garbage collection script (run by cron)
└── setup.sh            ← one-time bootstrap for new VPS
```

## Setup on a new VPS

### 1. Clone the repo

```bash
git clone <your-repo> /home/bharani/containers
cd /home/bharani/containers/registry
```

### 2. Create the htpasswd file

The registry needs a username/password for pushing images. Generate one:

```bash
mkdir -p /home/bharani/container-data/registry/auth
docker run --rm --entrypoint htpasswd httpd:2 -Bbn youruser yourpassword \
  > /home/bharani/container-data/registry/auth/htpasswd
```

### 3. Create the secrets files (NOT in git)

**Registry UI credentials:**
```bash
mkdir -p /home/bharani/secrets
cat > /home/bharani/secrets/registry-ui.env << 'EOF'
NGINX_PROXY_HEADER_Authorization=Basic <base64-of-user:pass>
EOF
```

(To generate the base64: `echo -n 'youruser:yourpassword' | base64`)

**Regbot credentials:**
```bash
cat > /home/bharani/secrets/registry-regbot.env << 'EOF'
REGBOT_USER=youruser
REGBOT_PASS=yourpassword
EOF
```

### 4. Run setup (installs the GC cron)

```bash
sudo bash setup.sh
```

### 5. Start everything

```bash
docker compose up -d
```

### 6. Verify

```bash
docker compose ps                              # all 3 should be Up
curl -u youruser:yourpassword http://localhost:5000/v2/_catalog   # should list repos
docker logs regbot                             # should be quiet (server mode)
```

## How the cleanup works

**regbot.yml** is a Lua script that runs every 168 hours (7 days) inside the regbot container. For each repo it:

1. Lists all tags
2. Skips protected tags: `latest`, `stable`, `main`
3. Reads each tag's image creation timestamp
4. For tags **with** a creation date: keeps the 2 newest by date
5. For tags **without** a date (multi-arch/buildx images): falls back to alphabetical sort
6. Deletes everything beyond the keep limit

**gc.sh** is a shell script triggered by cron every Sunday at 3am. It runs the registry's built-in garbage collector to reclaim disk space from deleted manifests.

**Important:** Tag deletion alone doesn't free disk space — it only removes references. The GC step is what actually reclaims storage. The two-step design is intentional: tag deletion is safe to run anytime, GC needs more care.

## Manual operations

### Force a cleanup run now

```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once
```

### Dry-run (see what would be deleted, no changes)

```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once --dry-run
```

### Force garbage collection now

```bash
docker exec registry registry garbage-collect --delete-untagged \
  /etc/docker/registry/config.yml
```

### Check disk usage

```bash
df -h /
du -sh /home/bharani/container-data/registry/
```

### Check what's stored

```bash
# List all repos
curl -u youruser:yourpassword http://localhost:5000/v2/_catalog

# List tags for a repo
curl -u youruser:yourpassword http://localhost:5000/v2/<repo>/tags/list
```

## Configuration

### Change retention count

Edit `regbot.yml`:
```lua
keep_count = 2   -- change to whatever you want
```

Then commit and `docker compose restart regbot`.

### Add more protected tag names

Edit `regbot.yml`:
```lua
protected = { ["latest"] = true, ["stable"] = true, ["main"] = true, ["prod"] = true }
```

### Change cleanup frequency

Edit `regbot.yml`:
```yaml
defaults:
  interval: 168h   # weekly. Use 24h for daily, 720h for monthly, etc.
```

## Pushing images to the registry

From any machine with Docker:

```bash
docker login <vps-host>:5000 -u youruser -p yourpassword
docker tag myimage:latest <vps-host>:5000/myimage:v1
docker push <vps-host>:5000/myimage:v1
```

If using HTTP (not HTTPS), add this to `/etc/docker/daemon.json` on the client:
```json
{
  "insecure-registries": ["<vps-host>:5000"]
}
```

Then `sudo systemctl restart docker`.

## Troubleshooting

### Regbot logs are empty

Server mode is silent until the next scheduled run. Force a one-time run to verify:
```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once
```

### Registry is full / out of disk

Run cleanup + GC manually:
```bash
docker compose run --rm regbot -c /home/appuser/regbot.yml once
docker exec registry registry garbage-collect --delete-untagged \
  /etc/docker/registry/config.yml
```

### Cleanup says "could not read config" for some tags

This is fine — it happens with multi-arch images built by `docker buildx`. The script falls back to sorting by tag name for these.

### Registry won't delete (returns 405)

Make sure `config.yml` has:
```yaml
storage:
  delete:
    enabled: true
```

## Architecture notes

- All persistent data lives in `/home/bharani/container-data/registry/` (data + auth)
- Config lives in `/home/bharani/containers/registry/` (in git)
- Secrets live in `/home/bharani/secrets/` (NOT in git)
- The three containers share Docker's default network so regbot can reach `registry:5000` by service name