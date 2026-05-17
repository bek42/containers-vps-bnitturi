# Infisical

Self-hosted secrets manager. Exposed at `https://secrets.bnitturi.com` via Cloudflare tunnel.

## Services

- `infisical/infisical` — Web UI + API on port 8080
- `redis:7-alpine` — Queue and cache backend

Database is hosted on **Neon** (free tier, no maintenance required).

## First-time setup

```bash
# Create data directory
mkdir -p /home/bharani/container-data/infisical/redis

# Create secrets file (never commit this)
cat > /home/bharani/secrets/infisical.env << 'EOF'
DB_CONNECTION_URI=<neon-connection-string>
REDIS_URL=redis://infisical-redis:6379
ENCRYPTION_KEY=<32-char-hex>
AUTH_SECRET=<32-char-hex>
SITE_URL=https://secrets.bnitturi.com
EOF

# Generate keys if needed
openssl rand -hex 16  # run twice — one for ENCRYPTION_KEY, one for AUTH_SECRET

# Deploy
docker compose up -d
```

## Upgrade

```bash
docker compose pull
docker compose up -d
```

## Check status

```bash
docker compose ps
docker compose logs infisical
```

## Secrets file location

`/home/bharani/secrets/infisical.env` — not in git
