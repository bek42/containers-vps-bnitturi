#!/usr/bin/env bash
# Operational summary: container health and restarts, Tailscale state, exit-node advertisement, DoH reachability, resources.
# Prints no queries and no client data.
set -uo pipefail
DATA="$HOME/container-data/tailscale-gateway"
rc=0
for c in tailscale-gateway-dns tailscale-gateway; do
  s=$(docker inspect -f '{{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} restarts={{.RestartCount}} started={{.State.StartedAt}}' "$c" 2>/dev/null) || { echo "$c: MISSING"; rc=1; continue; }
  echo "$c: $s"; [[ "$s" == running\ health=healthy* ]] || rc=1
done
st=$(docker exec tailscale-gateway tailscale status --json 2>/dev/null)
if [ -n "$st" ]; then
  echo "$st" | jq -r '"tailscale: \(.BackendState)  node=\(.Self.HostName)  ips=\(.Self.TailscaleIPs|join(","))  online=\(.Self.Online)  exit_node_option=\(.Self.ExitNodeOption // false)"'
  echo "$st" | jq -e '.BackendState=="Running"' >/dev/null || rc=1
else echo "tailscale: unavailable"; rc=1; fi
adv=$(docker exec tailscale-gateway tailscale debug prefs 2>/dev/null | jq -r '.AdvertiseRoutes // [] | join(",")')
echo "advertised routes: ${adv:-none}"; [[ "$adv" == *0.0.0.0/0* ]] || rc=1
a=$(docker exec tailscale-gateway nslookup wikipedia.org 10.53.53.53 2>/dev/null | awk '/^Address/ && $2 !~ /[:#]53$/ {print $2; exit}')
echo "DoH via forwarder (wikipedia.org): ${a:-FAILED}"; [ -n "$a" ] || rc=1
docker stats --no-stream --format '{{.Name}}: cpu {{.CPUPerc}} mem {{.MemUsage}}' tailscale-gateway tailscale-gateway-dns
echo "data dir: $(du -sh "$DATA" 2>/dev/null | cut -f1)  disk free: $(df -h --output=avail "$HOME" | tail -1 | tr -d ' ')"
[ $rc = 0 ] && echo "OVERALL: OK" || echo "OVERALL: ATTENTION"
exit $rc
