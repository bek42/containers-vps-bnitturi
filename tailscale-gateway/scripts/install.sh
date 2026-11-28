#!/usr/bin/env bash
# Idempotent install/start of tailscale-gateway. Run through "make up" (needs DOH_UPSTREAM and HOST_PUBLIC_IPV4 from sops).
# Touches only: ~/container-data/tailscale-gateway, the Docker network "tailscale-gateway" and the two gateway containers.
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="$HOME/container-data/tailscale-gateway"
: "${DOH_UPSTREAM:?DOH_UPSTREAM missing: run through make up}" "${HOST_PUBLIC_IPV4:?HOST_PUBLIC_IPV4 missing: run through make up}"
[[ "$DOH_UPSTREAM" =~ ^https://[a-z0-9]+\.cloudflare-gateway\.com/dns-query$ ]] || { echo "DOH_UPSTREAM is not a Cloudflare Gateway location DoH URL" >&2; exit 1; }
[ -c /dev/net/tun ] || { echo "/dev/net/tun missing" >&2; exit 1; }

mkdir -p "$DATA"/{tailscale,dns-proxy,secrets,backups}
chmod 700 "$DATA/secrets" "$DATA/backups"
# tailscale/ holds the node private key. It is owned by root (the container user, which has no DAC_OVERRIDE) with mode 700.
if [ "$(stat -c %u "$DATA/tailscale")" != 0 ]; then
  docker run --rm --entrypoint sh -v "$DATA/tailscale:/s" tailscale/tailscale:v1.104.7 -c 'chown -R 0:0 /s && chmod 700 /s'
fi

scripts/validate.sh --static
docker compose pull -q
if ! scripts/logged-in.sh; then
  # Not logged in yet: start only the forwarder. Starting the node now would loop (the image's login wait is 60 s).
  docker compose up -d --remove-orphans dns
  docker compose stop tailscale >/dev/null 2>&1 || true
  echo "Node bnitturi-gateway is not logged in. Run: make login"
  docker compose ps; exit 0
fi
docker compose up -d --remove-orphans
for _ in $(seq 1 30); do
  docker exec tailscale-gateway tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"' && break; sleep 2
done
if docker exec tailscale-gateway tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
  echo "tailscale-gateway is logged in and running."
else
  echo "tailscale-gateway did not reach Running; see make logs" >&2
fi
docker compose ps
