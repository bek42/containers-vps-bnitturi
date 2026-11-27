#!/usr/bin/env bash
# Snapshot of the gateway node identity (tailscaled state, contains the node private key) and the repo config. Keeps 10.
set -euo pipefail
cd "$(dirname "$0")/.."
DATA="$HOME/container-data/tailscale-gateway"; mkdir -p "$DATA/backups"; chmod 700 "$DATA/backups"
out="$DATA/backups/tailscale-gateway-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
umask 077
# The state directory is root-owned (written inside the container), so read it through the container.
docker exec tailscale-gateway tar -C /var/lib -czf - tailscale > "$out.state"
tar -czf "$out" docker-compose.yml config tailscale-gateway.env -C "$(dirname "$out")" "$(basename "$out").state"
rm -f "$out.state"; chmod 600 "$out"
ls -1t "$DATA"/backups/tailscale-gateway-*.tar.gz | tail -n +11 | xargs -r rm -f
echo "backup: $out ($(du -h "$out" | cut -f1))"
