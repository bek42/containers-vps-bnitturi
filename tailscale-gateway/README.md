# tailscale-gateway

A Tailscale exit node (`bnitturi-gateway`) whose clients get Cloudflare Zero Trust DNS filtering, for devices away from home.
It is separate from the host's own Tailscale node (`bnitturi`), which it does not touch.

| Service | Container | Image | Purpose |
|---|---|---|---|
| `tailscale` | `tailscale-gateway` | `tailscale/tailscale:v1.104.7` | Own node identity, kernel networking, advertised exit node, scoped firewall inside its own namespace |
| `dns` | `tailscale-gateway-dns` | `adguard/dnsproxy:v0.86.0` | Forwards all DNS to the Cloudflare Gateway location DoH endpoint. No fallback, no published ports |

Data: `~/container-data/tailscale-gateway/` = `tailscale/` (node state, root-owned, private), `dns-proxy/` (unused: the forwarder is stateless), `secrets/`, `backups/`.
Secrets: `tailscale-gateway.env` (sops: DoH location URL, host IPv4, optional auth key). This repository is public; never put them anywhere else.

```
make up          install/start (idempotent); prints the one-time login URL      make test      server-side acceptance tests
make status      health summary                                                 make logs | ps | restart | down
make backup      node identity snapshot      make restore FILE=...               make rollback  remove the gateway (state kept)
```

Docs: `docs/architecture.md`, `client-setup.md`, `android-setup.md`, `hotspot-limitations.md`, `security.md`, `troubleshooting.md`, `test-results.md`.
