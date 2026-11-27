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
# tailscale/ is written by root inside the container (node key); 700 keeps it private once the container owns it.
[ -O "$DATA/tailscale" ] && chmod 700 "$DATA/tailscale" || true

scripts/validate.sh --static
docker compose pull -q
docker compose up -d --remove-orphans
for i in $(seq 1 20); do
  st=$(docker inspect -f '{{.State.Status}}' tailscale-gateway 2>/dev/null || true)
  [ "$st" = running ] && break; sleep 2
done
sleep 5
if docker exec tailscale-gateway tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
  echo "tailscale-gateway is logged in and running."
else
  url=$(docker logs tailscale-gateway 2>&1 | grep -o 'https://login.tailscale.com/[^ ]*' | tail -1 || true)
  echo "Node bnitturi-gateway needs a one-time login. Open: ${url:-<run make login-url in a few seconds>}"
fi
docker compose ps
