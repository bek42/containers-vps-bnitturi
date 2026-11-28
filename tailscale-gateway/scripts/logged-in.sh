#!/usr/bin/env bash
# Exit 0 when the persisted state of bnitturi-gateway holds a logged-in profile (read through a one-shot container,
# because the state directory is root-owned 0700). Used by install.sh and login.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE=$(awk '/image: tailscale\/tailscale:/ {print $2}' docker-compose.yml)
docker run --rm --cap-drop ALL --network none --entrypoint sh \
  -v "$HOME/container-data/tailscale-gateway/tailscale:/s:ro" "$IMAGE" \
  -c 'grep -q "_profiles" /s/tailscaled.state 2>/dev/null' >/dev/null 2>&1
