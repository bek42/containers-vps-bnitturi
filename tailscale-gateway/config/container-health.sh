#!/bin/sh
# Container health for the tailscale service: node has a tailnet address, and the scoped firewall is in place and first.
wget -q -T 5 -O /dev/null http://127.0.0.1:9002/healthz || { echo "tailscale not logged in or no tailnet IP"; exit 1; }
[ "$(iptables-nft -S FORWARD 2>/dev/null | sed -n 2p)" = "-A FORWARD -j GW-FWD" ] || { echo "GW-FWD is not the first FORWARD rule"; exit 1; }
[ "$(ip6tables-nft -S FORWARD 2>/dev/null | sed -n 2p)" = "-A FORWARD -j GW-FWD6" ] || { echo "GW-FWD6 is not the first IPv6 FORWARD rule"; exit 1; }
iptables-nft -t nat -S PREROUTING 2>/dev/null | grep -q -- "-j GW-DNAT" || { echo "DNS redirect missing"; exit 1; }
exit 0
