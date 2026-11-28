# Security

## Hardening

| Control | tailscale-gateway | tailscale-gateway-dns |
|---|---|---|
| Privileged | no | no |
| Capabilities | everything dropped, then NET_ADMIN and NET_RAW added (needed for the TUN device and firewall) | everything dropped, then NET_BIND_SERVICE added (the binary's file capability) |
| no-new-privileges | yes | yes |
| Root filesystem | read-only. tmpfs for /tmp, /run and /root/.cache | read-only |
| User | root (tailscaled in kernel mode needs it) | 65534 (nobody) |
| Published ports | none | none |
| Limits | 256 MB, 1 CPU, 128 pids | 64 MB, 0.5 CPU, 64 pids |
| Logs | json-file, 10 MB × 3 | json-file, 5 MB × 2. Query logging is off (`verbose: false`) |

- **Scope.** The firewall rules exist only in the gateway container's network namespace. The sysctls (ip_forward) are namespaced too. The host's nftables and ufw, its routes, its resolver and its Tailscale node are untouched.
- **Secrets.**
  - `tailscale-gateway.env` is sops-encrypted. It holds the DoH URL (which identifies the Cloudflare location), the host IP and an optional auth key. The plaintext never appears in Git or in an image.
  - The node's private state is in `~/container-data/tailscale-gateway/tailscale` (root, mode 0700).
  - Backups are 0600 in a 0700 directory. They contain the node key, so treat them like a password.
- **Exposure.** The VPS public IP does not answer DNS (tested from another server). The forwarder is reachable only on the gateway's internal Docker network. There is no web UI.
- **Client isolation.** Exit-node clients cannot reach RFC1918, CGNAT, link-local or multicast addresses, or the VPS's public IP. That covers the host's Docker networks and services. Access to other tailnet devices is governed by the tailnet access policy, not by this firewall. See the proposed policy in [client-setup.md](client-setup.md).

## What is enforced, and where

| Layer | Enforces | Bypassed by |
|---|---|---|
| Cloudflare Gateway DNS policy (location DoH) | blocked names answer 0.0.0.0 / :: | anything that does not resolve through this forwarder |
| Gateway firewall | plain DNS to any IP is redirected; DoT/DoQ on 853 is rejected; well-known DoH resolver IPs are rejected; no IPv6 | DoH or DoT through an unlisted provider or a proxy; a VPN or proxy app; Tor; visiting a site by IP address (tested: chess.com's IP was reachable on 443) |
| Tailscale exit node selection | all of the phone's traffic goes through the gateway | the user turning the exit node off in the app (locking it needs a paid plan); signing out; uninstalling |
| Android always-on plus lockdown | no data without a VPN | none for the phone's own apps, but it does not require the exit node and does not cover tethering |
| Parental controls (Family Link) | app installs, possibly settings | unverified |

**This is DNS filtering, not complete website blocking.** It does not stop:
- a VPN or proxy app
- an unlisted DoH resolver
- a site reached by IP address
- hotspot clients
- the exit node being turned off

## Recommended Cloudflare policy corrections (NOT applied; needs approval)

1. **Fix the over-blocking.** The current expression matches "chess" anywhere in a name. That also blocks unrelated names: `chessington.com` resolved to 0.0.0.0. Use an explicit list of domains instead, for example `chess.com`, `chesscomfiles.com`, `lichess.org`, `lichess1.org`, `lichess.ovh`, `chess24.com`, `chesskid.com`, `chessbase.com`, `chess.net`, `chesstempo.com`, `chessable.com`, matched with "Domain in" (which covers subdomains). Or use an anchored regex such as `(^|\.)(chess|lichess)[a-z0-9-]*\.[a-z]+$`. Test it in a non-blocking policy before switching.
2. **Block DoH and DoT resolver hostnames** with a separate policy (Domain in): `dns.google`, `cloudflare-dns.com`, `mozilla.cloudflare-dns.com`, `one.one.one.one`, `dns.quad9.net`, `dns.adguard-dns.com`, `doh.opendns.com`, `dns.nextdns.io`, `doh.cleanbrowsing.org`, `freedns.controld.com`, `dns.mullvad.net`. Alternatively, block Cloudflare's DoH category, if your plan's category list includes one.
3. **Block `use-application-dns.net`** (Firefox's canary domain). It currently resolves, so Firefox may turn on its own DoH.
4. Optionally, block the "Anonymizer" / "Proxies & VPNs" security or content categories to reduce the VPN and proxy-app bypass.

## Monitoring without browsing history

`make status` shows only infrastructure facts:
- container state, health and restart count
- Tailscale state, IPs and online status
- the advertised routes
- one DoH test through the forwarder
- CPU and memory
- the state directory size and free disk space

It never shows which client asked for which name. Per-query visibility lives only in Cloudflare's logs, under the existing Zero Trust settings.
