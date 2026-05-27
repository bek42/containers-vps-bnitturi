# tunnel

Cloudflare Tunnel for inbound HTTPS routing. Maps four public hostnames to local services on the VPS via Cloudflare's edge.

## Service

| Service | Container | Image | Purpose |
|---|---|---|---|
| `cloudflare-tunnel` | `cloudflare-tunnel` | `cloudflare/cloudflared:latest` | Tunnel client |

Runs with `network_mode: host` so the tunnel can reach localhost-bound services on the VPS by port.

## Routes

Configured in `cloudflared/config.yml`:

| Hostname | Forwards to | Notes |
|---|---|---|
| `portainer.bnitturi.com` | `localhost:9000` | Portainer admin UI |
| `vault.bnitturi.com/safe/bems2304/*` | `localhost:8062` | Vaultwarden (path-scoped) |
| `app.gmailit.com` | `localhost:7777` | SimpleLogin (with `httpHostHeader` rewrite) |
| `v0u1t.bnitturi.com` | `localhost:8080` | Infisical |
| anything else | `http_status:404` | catch-all reject |

`reg.greatsky.co.uk` is on a separate tunnel, not this one.

## Secrets

The cloudflared credential file `<tunnel-id>.json` is encrypted at rest via `age` rather than sops. cloudflared reads it as a JSON blob from disk and needs every field intact (AccountTag, TunnelID, TunnelSecret) — there's no env-var interface for tunnel credentials. So we encrypt the whole file with age and decrypt-to-disk on `make up`.

- `cloudflared/<id>.json.age` — committed
- `cloudflared/<id>.json` — gitignored; created at `make up` time

Tunnel ID: `53f49069-a8cd-410e-821e-1f2b868cc70f`

## Operations

```bash
make up        # decrypt cred + docker compose up -d
make down      # docker compose down
make restart   # down + up
make encrypt   # re-encrypt the .json to .json.age (after rotation)
```

The decrypted JSON sits on disk (mode 600) while the tunnel runs. It's gitignored, same security boundary as `~/secrets/` was previously — but the encrypted form is what travels with the repo.

## Recovery on a new host

1. Install `age`, `make`, `docker`, `docker compose`.
2. Place age private key at `~/.config/age/keys.txt` (chmod 600).
3. Clone repo, `cd tunnel`.
4. `make up`.

The tunnel reconnects to Cloudflare's edge using the existing tunnel ID — no need to re-register, DNS routes are already in place at Cloudflare.

## Rotating the credential

If you ever regenerate the tunnel credential (compromise, audit, expiry):

```bash
# place new JSON at cloudflared/<id>.json (from Cloudflare dashboard or cloudflared CLI)
make encrypt
make restart
git add cloudflared/*.json.age
git commit -m "tunnel: rotate credential"
git push
```

## Changing routes

Edit `cloudflared/config.yml` (plain YAML, no secrets, safe to commit). Then either restart or signal a reload:

```bash
make restart                                       # full restart
# OR graceful in-place reload:
docker kill --signal=SIGHUP cloudflare-tunnel
```

## Troubleshooting

**`make up` fails on the age step.** Either the encrypted file is missing, the age key isn't at `~/.config/age/keys.txt`, or the recipient on the file doesn't match your key. Re-encrypt if needed: copy the plaintext in, `make encrypt`.

**Tunnel connects but a route 502s.** The ingress block expects the local service to be reachable. Check:
```bash
curl -sv http://localhost:<port>/
```

**Tunnel logs.**
```bash
docker logs --tail 50 cloudflare-tunnel
```
