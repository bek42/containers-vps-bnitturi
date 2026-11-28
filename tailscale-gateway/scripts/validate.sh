#!/usr/bin/env bash
# Validation for tailscale-gateway.
#   validate.sh --static   configuration checks only (run by install.sh before starting anything)
#   validate.sh            static + live server-side tests (run through "make test"; needs the sops env)
#   validate.sh --restart  also restarts the tailscale container and checks the node identity persists
# Output: one line per test, "ID | result | evidence". Exit status 1 if any test FAILs.
set -uo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-}"
FAILS=0
row() { printf '%-6s | %-4s | %s\n' "$1" "$2" "$3"; [ "$2" = FAIL ] && FAILS=$((FAILS + 1)); return 0; }
check() { local id=$1 desc=$2; shift 2; local out; if out=$("$@" 2>&1); then row "$id" PASS "$desc: ${out//$'\n'/ }"; else row "$id" FAIL "$desc: ${out//$'\n'/ }"; fi; }

# ---------------- static ----------------
check S1 "compose file valid" bash -c 'docker compose config -q && echo ok'
check S2 "shell scripts parse" bash -c 'for f in scripts/*.sh; do bash -n "$f" || exit 1; done; for f in config/*.sh; do sh -n "$f" || exit 1; done; echo ok'
check S3 "images pinned to versions" bash -c '! grep -E "^\s+image:" docker-compose.yml | grep -qE ":latest|image: [^:]+$" && grep -E "^\s+image:" docker-compose.yml | awk "{print \$2}" | paste -sd" "'
check S4 "no plaintext secrets committed" bash -c '! grep -rIlE "tskey-[a-z]+-|[a-z0-9]{8,}\.cloudflare-gateway\.com" --exclude=tailscale-gateway.env --exclude=validate.sh . && grep -q "ENC\[AES256_GCM" tailscale-gateway.env && echo "only sops ciphertext"'
check S5 "forwarder has one upstream, no fallback" bash -c '! grep -qE "^upstream:" config/dns-proxy.conf && grep -qE "^fallback: \[\]" config/dns-proxy.conf && [ "$(grep -c -- "--upstream=" docker-compose.yml)" = 1 ] && echo "upstream only from DOH_UPSTREAM; fallback []"'
[ "$MODE" = "--static" ] && { [ $FAILS = 0 ]; exit; }

# ---------------- VPS and containers ----------------
check V1 "other services still running" bash -c 'bad=$( { docker ps -a --filter status=restarting --format "{{.Names}}"; docker ps -a --filter status=exited --format "{{.Names}} {{.Status}}" | grep -v "Exited (0)" | cut -d" " -f1; } | grep -v "^tailscale-gateway" || true); [ -z "$bad" ] && echo "$(docker ps -q | wc -l) containers running, none failed or restarting" || { echo "failed or restarting: $bad"; exit 1; }'
check V2 "host Tailscale (bnitturi) still connected" bash -c 'tailscale status --json | jq -e ".BackendState==\"Running\"" >/dev/null && tailscale ip -4'
check V3 "gateway node logged in" bash -c 'docker exec tailscale-gateway tailscale status --json | jq -er "select(.BackendState==\"Running\") | \"\(.Self.HostName) \(.Self.TailscaleIPs|join(\" \"))\""'
check V4 "exit node advertised (IPv4 and IPv6 default routes)" bash -c 'docker exec tailscale-gateway tailscale debug prefs | jq -er ".AdvertiseRoutes | select(index(\"0.0.0.0/0\") and index(\"::/0\")) | join(\",\")"'
check V5 "both containers healthy, restart policy set" bash -c 'for c in tailscale-gateway tailscale-gateway-dns; do docker inspect -f "{{.Name}} {{.State.Health.Status}} {{.HostConfig.RestartPolicy.Name}}" $c; done | tee /dev/stderr | grep -vq -e "healthy unless-stopped$" && exit 1 || true'
check V6 "no host ports published by the gateway" bash -c '[ -z "$(docker port tailscale-gateway)$(docker port tailscale-gateway-dns)" ] && echo "none"'
check V7 "host port 53 listeners unchanged (resolved stub only)" bash -c 'l=$(ss -Hlntu | awk "\$5 ~ /:53\$/ {print \$5}" | sort -u | paste -sd" "); echo "$l"; ! echo "$l" | grep -vqE "^(127\.0\.0\.5[34](%lo)?:53 ?)+$"'
check V8 "public IPv4 does not answer DNS" bash -c 'out=$(dig +time=2 +tries=1 wikipedia.org @"$HOST_PUBLIC_IPV4" 2>&1); ! echo "$out" | grep -q "status: NOERROR" && echo "no answer from public address"'
check V9 "gateway runs least-privilege" bash -c 'docker inspect -f "{{.Name}} priv={{.HostConfig.Privileged}} ro={{.HostConfig.ReadonlyRootfs}} capadd={{.HostConfig.CapAdd}} capdrop={{.HostConfig.CapDrop}} user={{.Config.User}}" tailscale-gateway tailscale-gateway-dns | tee /dev/stderr | grep -q "priv=true" && exit 1 || true'
if [ "$MODE" = "--restart" ]; then
  before=$(docker exec tailscale-gateway tailscale status --json | jq -r .Self.ID)
  docker compose restart tailscale >/dev/null 2>&1
  for _ in $(seq 1 40); do [ "$(docker inspect -f "{{.State.Health.Status}}" tailscale-gateway)" = healthy ] && break; sleep 3; done
  check V10 "node identity persists across restart" bash -c "after=\$(docker exec tailscale-gateway tailscale status --json | jq -r .Self.ID); echo \"before=$before after=\$after\"; [ \"$before\" = \"\$after\" ]"
fi

# ---------------- DNS through the forwarder (as the gateway serves exit-node clients) ----------------
q() { docker exec tailscale-gateway nslookup -type="$1" "$2" 10.53.53.53 2>/dev/null | awk '/^Address/ && $2 !~ /^10\.53\.53\.53(:|#)53$/ {print $2}' | head -2 | paste -sd,; }
allow() { local a; a=$(q A "$1"); echo "$1 -> $a"; [ -n "$a" ] && [ "$a" != 0.0.0.0 ]; }
block() { local a b; a=$(q A "$1"); b=$(q AAAA "$1"); echo "$1 A=$a AAAA=$b"; [ "$a" = 0.0.0.0 ] && [ "$b" = "::" ]; }
check D1 "wikipedia.org resolves" allow wikipedia.org
check D2 "bbc.co.uk resolves" allow bbc.co.uk
check D3 "google.com resolves" allow google.com
check D4 "chess.com blocked by Gateway policy (0.0.0.0 / ::)" block chess.com
check D5 "www.chess.com blocked" block www.chess.com
check D6 "lichess.org blocked" block lichess.org
check D7 "block is Cloudflare's decision, not a failure (same name resolves unfiltered)" bash -c 'u=$(dig +short +time=3 chess.com @1.1.1.1 | head -1); f=$(docker exec tailscale-gateway nslookup chess.com 10.53.53.53 | awk "/^Address/ && \$2 !~ /:53\$/ {print \$2; exit}"); echo "unfiltered=$u gateway=$f"; [ -n "$u" ] && [ "$u" != 0.0.0.0 ] && [ "$f" = 0.0.0.0 ]'
check D8 "forwarder upstream is the location DoH endpoint only" bash -c 'docker inspect -f "{{join .Args \" \"}}" tailscale-gateway-dns | grep -oE -- "--upstream=https://[a-z0-9]+\.cloudflare-gateway\.com/dns-query" | sed -E "s#//[a-z0-9]+\.#//<location>.#"'
check D9 "gateway node's own resolver is the forwarder" bash -c 'docker exec tailscale-gateway cat /etc/resolv.conf | grep -E "^nameserver" | paste -sd" " | tee /dev/stderr | grep -qx "nameserver 10.53.53.53"'

# ---------------- scoped firewall (inside the gateway namespace only) ----------------
check F1 "GW-FWD is the first IPv4 FORWARD rule" bash -c 'docker exec tailscale-gateway iptables-nft -S FORWARD | sed -n 2p | grep -x -- "-A FORWARD -j GW-FWD"'
check F2 "GW-FWD6 is the first IPv6 FORWARD rule" bash -c 'docker exec tailscale-gateway ip6tables-nft -S FORWARD | sed -n 2p | grep -x -- "-A FORWARD -j GW-FWD6"'
check F3 "client DNS on 53 redirected to the forwarder" bash -c 'docker exec tailscale-gateway iptables-nft -t nat -S GW-DNAT | grep -c "to-destination 10.53.53.53:53" | grep -qx 2 && echo "udp+tcp DNAT present"'
check F4 "DoT/DoQ 853 and known DoH IPs rejected" bash -c 'r=$(docker exec tailscale-gateway iptables-nft -S GW-FWD); echo "$(echo "$r" | grep -c "dport 853") rules for 853, $(echo "$r" | grep -c "dport 443") for DoH IPs"; echo "$r" | grep -q "dport 853" && echo "$r" | grep -q "dport 443"'
check F5 "host and private ranges unreachable from clients" bash -c 'docker exec tailscale-gateway iptables-nft -S GW-FWD | grep -E "^-A GW-FWD -d (10.0.0.0/8|172.16.0.0/12|192.168.0.0/16|$HOST_PUBLIC_IPV4/32)" | wc -l | grep -qx 4 && echo "10/8 172.16/12 192.168/16 host"'

# ---------------- resources ----------------
row R1 INFO "$(docker stats --no-stream --format '{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}' tailscale-gateway tailscale-gateway-dns | paste -sd';')"

echo "failures: $FAILS"
[ $FAILS = 0 ]
