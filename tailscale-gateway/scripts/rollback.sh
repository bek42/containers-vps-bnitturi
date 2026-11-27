#!/usr/bin/env bash
# Remove the gateway without touching anything else on the host. Keeps ~/container-data/tailscale-gateway (identity, backups).
# Clients that selected bnitturi-gateway as exit node lose internet until they deselect it (fail closed) - deselect first.
# To decommission fully, also remove the machine "bnitturi-gateway" in the Tailscale admin console. To roll back a config change
# instead, "git revert" the commit in the containers repo, git pull on the host, and make up.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose down --remove-orphans
docker network rm tailscale-gateway 2>/dev/null || true
echo "tailscale-gateway stopped and removed. Host Tailscale (bnitturi): $(tailscale status --self --peers=false 2>/dev/null | head -1)"
