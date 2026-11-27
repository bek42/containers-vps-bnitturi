#!/usr/bin/env bash
# Restore the node identity from a backup made by backup.sh (config comes from git, not from the backup).
set -euo pipefail
cd "$(dirname "$0")/.."
f="${1:?usage: restore.sh <backup.tar.gz>}"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
tar -xzf "$f" -C "$tmp"; st=$(ls "$tmp"/*.state)
docker compose stop tailscale
docker run --rm -i --entrypoint sh -v "$HOME/container-data/tailscale-gateway/tailscale:/var/lib/tailscale" tailscale/tailscale:v1.104.7 \
  -c 'rm -rf /var/lib/tailscale/* && tar -C /var/lib -xzf -' < "$st"
docker compose up -d
echo "restored node identity from $f"
