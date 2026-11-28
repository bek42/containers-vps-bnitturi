# Architecture

## Goal and scope

The goal is to apply the existing Cloudflare Zero Trust Gateway DNS policy to a device when it is away from home: on mobile data, other Wi-Fi or Ethernet, hotspots and public Wi-Fi.

- **Cloudflare is the only policy engine.** This stack keeps no blocklist of its own and logs no queries.
- **It filters DNS only.** It does not inspect HTTPS and installs no certificates. A site that is reached by IP address, or through an unknown encrypted resolver, is not blocked. See [security.md](security.md).

## Data path

```
client device (Tailscale app, exit node = bnitturi-gateway)
  │  WireGuard (direct UDP or DERP relay)
  ▼
container "tailscale-gateway"  own network namespace, kernel TUN tailscale0, Tailscale node "bnitturi-gateway"
  │  DNS: client → 100.100.100.100 (MagicDNS). Tailnet names are answered locally on the client.
  │       Other names go to the exit node's resolver: tailscaled in this container → /etc/resolv.conf → 10.53.53.53
  │       Plain DNS that a client sends to any other IP on port 53 is DNAT-ed to 10.53.53.53.
  │  Web traffic: filtered (GW-FWD), then MASQUERADE on eth0 (10.53.53.2)
  ▼
Docker bridge "tailscale-gateway" (br-tsgateway, 10.53.53.0/24) ──► host NAT ──► Internet (the VPS public IPv4)
  │
  └─► container "tailscale-gateway-dns" 10.53.53.53  AdGuard dnsproxy
          └─► DoH to the Cloudflare Gateway location endpoint https://<location>.cloudflare-gateway.com/dns-query
                  └─► Gateway DNS policy: blocked names answer 0.0.0.0 / ::
```

The Gateway policy is applied by the location's unique DoH URL, not by source IP. The shared resolver addresses 172.64.36.1 and 172.64.36.2 return **unfiltered** answers to queries from the VPS. This was measured: chess.com resolved to its real address. That is why the forwarder uses the DoH URL.

The Tailscale documentation says that a device using an exit node also uses that exit node as its DNS resolver. The exception is a tailnet nameserver with "Use with exit node" enabled. So **no tailnet-wide DNS setting was changed**. Clients that do not use the exit node, and MagicDNS, behave exactly as before. The test results confirm this: on the test client, chess.com was blocked while tailnet names still resolved through MagicDNS.

## Options considered

| Option | What it is | Decision |
|---|---|---|
| A. Native host Tailscale (`bnitturi`) as the exit node | Advertise the exit node from the host daemon, and point the host resolver or the host firewall at a filtering forwarder | **Rejected.** It needs host-wide changes: resolved, sysctl and the host nftables/ufw. The host is shared and has no passwordless sudo. Every host process would depend on the filter, and the host's own DNS would become circular. Mistakes there risk remote access to the VPS. |
| A2. Option A plus "Use with exit node" on the global 172.64.36.x nameservers | A tailnet DNS change only | **Rejected.** Queries would leave from the VPS IP, which is not a Gateway location, so they would not be filtered. It would also change every exit-node user tailnet-wide. |
| **B. Separate Tailscale node in a container** | Its own network namespace, kernel TUN, its own firewall rules inside that namespace, and a dedicated forwarder container | **Chosen.** There are no host changes. Only one tailscaled runs in each namespace (the host's tailscaled and this one never share one). Rollback is `docker compose down`, and the identity is separate, so access policy can tell the two nodes apart. |
| B-userspace. Option B with `TS_USERSPACE=true` | No TUN device or NET_ADMIN | **Rejected.** In userspace mode the forwarded traffic never passes a netfilter hook, so the DNS redirect and the DoT/DoH and private-range blocks would be impossible. |

## Components

| Item | Value |
|---|---|
| Tailscale node | `bnitturi-gateway`, Tailscale IPs 100.66.56.98 and fd7a:115c:a1e0::2034:3863, node ID `nrv7vAagNQ11CNTRL`, key expiry disabled, exit node approved |
| Containers | `tailscale-gateway` (`tailscale/tailscale:v1.104.7`, 10.53.53.2) and `tailscale-gateway-dns` (`adguard/dnsproxy:v0.86.0`, 10.53.53.53) |
| DNS forwarding address | 10.53.53.53:53. It is reachable only inside the `tailscale-gateway` Docker network. No ports are published on the host. |
| Egress | the VPS public IPv4, through Docker NAT. No IPv6 egress: IPv6 forwarding is rejected and clients fall back to IPv4. |
| Upstream | the Cloudflare Gateway location DoH URL only. The bootstrap resolvers `tls://1.1.1.1` and `tls://1.0.0.1` are used only to resolve that hostname. There is no fallback resolver. |
| Host node | `bnitturi` (native Tailscale). It is unchanged and is not an exit node. |

## Firewall (inside the gateway namespace only)

`config/gateway-init.sh` creates its own chains and makes them the first rules. Nothing on the host is touched.

- **GW-FWD** (filter FORWARD), in order:
  1. established traffic is allowed
  2. client DNS to 10.53.53.53 is allowed
  3. any other port 53 traffic is rejected
  4. TCP and UDP 853 (DoT/DoQ) are rejected
  5. RFC1918, CGNAT, link-local, multicast and the VPS's own public IP are rejected
  6. about 68 rules reject well-known DoH resolver IPs on port 443
  7. everything else is allowed
- **GW-DNAT** (nat PREROUTING): UDP and TCP 53 from `tailscale0` are redirected to the forwarder.
- **GW-SNAT** (nat POSTROUTING): MASQUERADE for 100.64.0.0/10 leaving eth0.
- **GW-FWD6** (ip6 FORWARD): everything from `tailscale0` is rejected.
- Rules are written with iptables-nft (kernel 7.0 has no legacy xtables), and tailscaled is run with `TS_DEBUG_FIREWALL_MODE=nftables`.
- A 15-second watchdog puts our chains back in first place if tailscaled reorders them. This was tested: a deleted jump rule came back after about 8 seconds.
- The container health check fails if the order is wrong.

## Login

The image's entrypoint waits only 60 seconds for an interactive login before it exits. With a restart policy, every restart then creates a new node key and a new URL. `make login` solves this:

1. It runs a one-shot tailscaled with no capabilities and userspace networking, using the same state directory.
2. It waits up to 15 minutes for the login to be approved.
3. It then starts the gateway.

`make up` does not start the node until the state holds a login, so a restart loop cannot happen.

## Resources (measured 2026-11-28)

| Container | Idle memory | Idle CPU | Limits |
|---|---|---|---|
| tailscale-gateway | about 19 MB | about 0.1% | 256 MB, 1 CPU, 128 pids |
| tailscale-gateway-dns | about 7 MB | 0% | 64 MB, 0.5 CPU, 64 pids |

On disk: the state directory is under 1 MB, and logs are capped at 10 MB × 3 and 5 MB × 2.
