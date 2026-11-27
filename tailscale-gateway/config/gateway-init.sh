#!/bin/sh
# Entry point of the tailscale service: install the gateway's scoped firewall in THIS container's network namespace, keep it
# ahead of tailscaled's own rules, then hand over to the image's containerboot. Nothing here touches the host's firewall.
set -eu
IPT=iptables-nft
IP6=ip6tables-nft
DNS="${GW_DNS_IP:-10.53.53.53}"
HOST4="${GW_HOST_IPV4:-}"
# Well-known public DNS-over-HTTPS / DoT resolver addresses (IP-literal DoH and DoH3). Partial by nature: see docs/security.md.
DOH_IPS="1.1.1.1 1.0.0.1 1.1.1.2 1.0.0.2 1.1.1.3 1.0.0.3 104.16.248.249 104.16.249.249 162.159.61.4 172.64.41.4 \
8.8.8.8 8.8.4.4 9.9.9.9 149.112.112.112 9.9.9.10 149.112.112.10 9.9.9.11 149.112.112.11 94.140.14.14 94.140.15.15 \
94.140.14.140 94.140.14.141 208.67.222.222 208.67.220.220 146.112.41.2 185.228.168.9 185.228.169.9 76.76.2.0 76.76.10.0 \
45.90.28.0/24 45.90.30.0/24 194.242.2.2 76.76.19.19 76.223.122.150"
PRIVATE4="0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4"

chain() {  # chain TOOL TABLE NAME : create or empty a chain
  $1 -t "$2" -N "$3" 2>/dev/null || $1 -t "$2" -F "$3"
}
first() {  # first TOOL TABLE PARENT CHILD : make "-j CHILD" the first rule of PARENT (idempotent)
  if [ "$($1 -t "$2" -S "$3" | sed -n 2p)" != "-A $3 -j $4" ]; then
    while $1 -t "$2" -D "$3" -j "$4" 2>/dev/null; do :; done
    $1 -t "$2" -I "$3" 1 -j "$4"
    echo "gateway-init: placed $4 first in $2/$3"
  fi
}

# --- IPv4 forwarding policy for traffic arriving from tailnet clients (tailscale0) ---
chain $IPT filter GW-FWD
$IPT -A GW-FWD -m conntrack --ctstate RELATED,ESTABLISHED -j RETURN
$IPT -A GW-FWD -i tailscale0 -d "$DNS"/32 -p udp --dport 53 -j RETURN          # redirected client DNS (see GW-DNAT)
$IPT -A GW-FWD -i tailscale0 -d "$DNS"/32 -p tcp --dport 53 -j RETURN
$IPT -A GW-FWD -i tailscale0 -p udp --dport 53 -j REJECT --reject-with icmp-admin-prohibited   # defensive; DNAT handles 53
$IPT -A GW-FWD -i tailscale0 -p tcp --dport 53 -j REJECT --reject-with tcp-reset
$IPT -A GW-FWD -i tailscale0 -p tcp --dport 853 -j REJECT --reject-with tcp-reset              # DNS over TLS
$IPT -A GW-FWD -i tailscale0 -p udp --dport 853 -j REJECT --reject-with icmp-admin-prohibited  # DNS over QUIC
for n in $PRIVATE4 ${HOST4:+$HOST4/32}; do                                         # host, Docker networks, LANs, CGNAT
  $IPT -A GW-FWD -i tailscale0 -d "$n" -j REJECT --reject-with icmp-admin-prohibited
done
for n in $DOH_IPS; do
  $IPT -A GW-FWD -i tailscale0 -d "$n" -p tcp --dport 443 -j REJECT --reject-with tcp-reset
  $IPT -A GW-FWD -i tailscale0 -d "$n" -p udp --dport 443 -j REJECT --reject-with icmp-admin-prohibited
done
$IPT -A GW-FWD -j RETURN

# --- Client DNS on port 53, to any address, is answered by the Cloudflare forwarder ---
chain $IPT nat GW-DNAT
$IPT -t nat -A GW-DNAT -i tailscale0 -p udp --dport 53 -j DNAT --to-destination "$DNS":53
$IPT -t nat -A GW-DNAT -i tailscale0 -p tcp --dport 53 -j DNAT --to-destination "$DNS":53
chain $IPT nat GW-SNAT
$IPT -t nat -A GW-SNAT -s 100.64.0.0/10 -o eth0 -j MASQUERADE                      # replies must come back through this namespace

# --- IPv6: this gateway has no IPv6 egress; reject forwarded IPv6 so clients fall back to IPv4 at once (no leak, no hang) ---
chain $IP6 filter GW-FWD6
$IP6 -A GW-FWD6 -i tailscale0 -j REJECT --reject-with icmp6-adm-prohibited
$IP6 -A GW-FWD6 -j RETURN

ensure() {
  first $IPT filter FORWARD GW-FWD
  first $IPT nat PREROUTING GW-DNAT
  first $IPT nat POSTROUTING GW-SNAT
  first $IP6 filter FORWARD GW-FWD6
}
ensure
echo "gateway-init: firewall installed (dns $DNS)"

# tailscaled installs its own chains after start; keep ours first. The container health check fails if this ever lapses.
( while sleep 15; do ensure 2>&1 | sed 's/^/gateway-init: /' || true; done ) &

exec /usr/local/bin/containerboot
