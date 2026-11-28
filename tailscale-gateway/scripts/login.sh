#!/usr/bin/env bash
# One-time interactive login of node bnitturi-gateway (also after a logout or a deleted machine). Run through "make login".
# Why a separate step: the image's entrypoint gives an interactive login only 60 s, then exits; the container restarts with a
# fresh node key and a new URL each minute, so a human can never finish. Here a one-shot tailscaled (userspace networking,
# no capabilities, no firewall, default Docker network) logs in with the same state directory and waits up to 15 minutes.
# The gateway container is stopped meanwhile and started again afterwards; the persisted identity is then reused.
set -euo pipefail
cd "$(dirname "$0")/.."
STATE="$HOME/container-data/tailscale-gateway/tailscale"
IMAGE=$(awk '/image: tailscale\/tailscale:/ {print $2}' docker-compose.yml)
NAME=tsgw-login
SOCK=/tmp/tailscaled.sock

if scripts/logged-in.sh; then echo "bnitturi-gateway is already logged in (state present). Nothing to do."; exit 0; fi

docker compose stop tailscale >/dev/null 2>&1 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT
docker run -d --name "$NAME" --cap-drop ALL --security-opt no-new-privileges:true \
  -v "$STATE:/var/lib/tailscale" --entrypoint tailscaled "$IMAGE" \
  --statedir=/var/lib/tailscale --tun=userspace-networking --socket="$SOCK" >/dev/null
sleep 3
docker exec -d "$NAME" sh -c "tailscale --socket=$SOCK login --hostname=bnitturi-gateway --advertise-exit-node \
  --accept-dns=false --accept-routes=false --ssh=false --timeout=15m >/tmp/login.out 2>&1"

url=""
for _ in $(seq 1 30); do
  url=$(docker exec "$NAME" sh -c 'grep -o "https://login.tailscale.com/[^ ]*" /tmp/login.out 2>/dev/null | head -1' || true)
  [ -n "$url" ] && break; sleep 1
done
[ -n "$url" ] || { echo "no login URL appeared"; docker logs --tail 20 "$NAME"; exit 1; }
echo "Open this URL and approve node bnitturi-gateway (valid for 15 minutes):"
echo "  $url"

for _ in $(seq 1 180); do
  if docker exec "$NAME" tailscale --socket="$SOCK" status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
    echo "Logged in: $(docker exec "$NAME" tailscale --socket="$SOCK" ip -4)"
    docker stop -t 10 "$NAME" >/dev/null   # graceful stop so the state is flushed
    echo "Starting the gateway with the new identity."
    exec scripts/install.sh
  fi
  sleep 5
done
echo "Timed out waiting for approval; run make login again."; exit 1
