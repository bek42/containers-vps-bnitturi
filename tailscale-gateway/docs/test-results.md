# Test results

**Date:** 2026-11-28.

- **Server side:** `make test` and `validate.sh --restart` on the VPS.
- **Client side:** a temporary, isolated Tailscale client (`tsgw-testclient`) in a container on a different server. Kernel mode, tailnet DNS accepted, exit node set to `bnitturi-gateway`, Allow LAN access off.

**Statuses:** PASS, FAIL, BLOCKED, MANUAL TEST REQUIRED.

## Static (S)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| S1 | Compose file valid | valid | valid | `docker compose config -q` | PASS |
| S2 | Scripts parse | no errors | ok | `bash -n` / `sh -n` on every script | PASS |
| S3 | Images pinned | no `:latest` | `adguard/dnsproxy:v0.86.0`, `tailscale/tailscale:v1.104.7` | validate S3 | PASS |
| S4 | No plaintext secrets in the repository | sops ciphertext only | only sops ciphertext | grep for auth keys and location hostnames | PASS |
| S5 | One upstream, no fallback | the location DoH URL only | upstream only from DOH_UPSTREAM; `fallback: []` | validate S5 | PASS |

## VPS and containers (V)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| V1 | Other services undisturbed | none failed or restarting | none failed or restarting | `docker ps -a` (one-shot jobs that exited with code 0 are ignored) | PASS |
| V2 | Host Tailscale `bnitturi` still connected | Running | Running, 100.108.52.74 | `tailscale status` on the host | PASS |
| V3 | Gateway node logged in | Running | bnitturi-gateway 100.66.56.98 | `tailscale status --json` in the container | PASS |
| V4 | Exit node advertised and approved | 0.0.0.0/0 and ::/0, ExitNodeOption | 0.0.0.0/0,::/0; `exit_node_option=true` | prefs; status | PASS |
| V5 | Healthy, with a restart policy | healthy, unless-stopped | both healthy, unless-stopped, 0 restarts | `docker inspect` | PASS |
| V6 | No host ports published | none | none | `docker port` | PASS |
| V7 | Host port 53 unchanged | resolved stub only | 127.0.0.53%lo:53, 127.0.0.54:53 | `ss -lntu` | PASS |
| V8 | Public IP is not an open resolver | no answer | no answer (from the VPS); connection refused (from another server) | dig and nslookup to the VPS IP | PASS |
| V9 | Least privilege | not privileged, read-only, minimal capabilities | not privileged, read-only. Gateway: NET_ADMIN and NET_RAW. dns: NET_BIND_SERVICE, uid 65534 | `docker inspect` | PASS |
| V10 | Identity persists across restart | same node ID | nrv7vAagNQ11CNTRL before and after | `validate.sh --restart` | PASS |
| V-F1 | Forwarder down: fail closed | client DNS fails, no fallback | wikipedia.org, chess.com and chess.com @9.9.9.9 all timed out. Restored after the restart. | `docker stop tailscale-gateway-dns`, then nslookup on the client | PASS |
| V-F2 | Gateway down: no DNS leak | client lookups fail | `wget: bad address` | `docker stop tailscale-gateway` | PASS |
| V-F3 | Gateway down: no traffic leak | traffic by IP does not go out directly | `wget` by IP timed out. After the restart the egress IP was the VPS again. | as above | PASS |
| V-F4 | Firewall order self-heals | the jump rule comes back | deleted `-j GW-FWD`, restored after about 8 s | watchdog | PASS |
| R1 | Resources | small | gateway about 17–19 MB and 0.1% CPU; dns about 6–7 MB and 0%; state 20 KB | `docker stats`, `make status` | PASS |

## DNS (D)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| D1 | wikipedia.org resolves | a real address | 185.15.58.224 | through the forwarder, and from the client through 100.100.100.100 | PASS |
| D2 | bbc.co.uk resolves | a real address | 151.101.64.81 and others | same | PASS |
| D3 | google.com resolves | a real address | 142.251.39.206 | forwarder | PASS |
| D4 | chess.com blocked | A 0.0.0.0, AAAA :: | 0.0.0.0 and :: | forwarder and client | PASS |
| D5 | www.chess.com blocked | 0.0.0.0 / :: | 0.0.0.0 and :: | forwarder and client | PASS |
| D6 | lichess.org blocked | 0.0.0.0 / :: | 0.0.0.0 and :: | forwarder and client | PASS |
| D7 | The block is Cloudflare's policy decision | the same name resolves unfiltered elsewhere | unfiltered 104.18.141.67; gateway 0.0.0.0 | 1.1.1.1 compared with the forwarder. With the block page disabled, Cloudflare answers blocked names with 0.0.0.0. | PASS |
| D7b | Decision visible in the Cloudflare DNS logs | "Blocked" for the location | not checked by me (needs the Zero Trust dashboard) | Zero Trust → Logs → DNS | MANUAL TEST REQUIRED |
| D8 | Upstream is the location endpoint only | one DoH URL | `--upstream=https://<location>.cloudflare-gateway.com/dns-query` | `docker inspect` | PASS |
| D9 | The gateway node's resolver is the forwarder | 10.53.53.53 | nameserver 10.53.53.53 | resolv.conf | PASS |
| D10 | MagicDNS still works on the exit-node client | tailnet names resolve | `bnitturi` resolves to 100.108.52.74 | client nslookup | PASS |
| D11 | No tailnet-wide DNS change was needed | filtering through 100.100.100.100 | client resolv.conf is 100.100.100.100; names are filtered | client | PASS |
| D12 | Plain DNS to another resolver is redirected | filtered answer | `nslookup chess.com 8.8.8.8` gives 0.0.0.0; `lichess.org 1.1.1.1` gives :: | client | PASS |
| D13 | Known over-blocking | (policy issue) | chessington.com gives 0.0.0.0 | forwarder. See the recommendation in security.md. | INFO |

## Routing (RT)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| RT1 | Egress through the gateway | the VPS public IPv4 | baseline 54.37.x (test server), then the VPS IPv4 with the exit node | api.ipify.org | PASS |
| RT2 | General browsing | works | en.wikipedia.org HTML received | wget | PASS |
| RT3 | Path quality | direct preferred | at first via DERP (lhr, 8 ms), later direct to the VPS IPv4 (2 ms) | `tailscale ping` | PASS |
| RT4 | IPv6 egress | rejected (no IPv6 egress) | the client had no IPv6 default route (no IPv6 on its network). The gateway's GW-FWD6 rejects all forwarded IPv6. | F2; client route table | MANUAL TEST REQUIRED (on a client with IPv6, e.g. the phone on mobile data) |
| RT5 | VPS default route unchanged | unchanged | not touched (no host changes) | no host commands were run | PASS |

## Security (SEC)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| F1 / F2 | Our chains are first | GW-FWD and GW-FWD6 at position 1 | yes, ahead of `ts-forward` | `iptables-nft -S FORWARD` | PASS |
| F3 / F4 / F5 | DNAT, 853 and DoH IPs, private ranges | present | 2 DNAT rules; 2 rules for 853; 68 DoH IP rules; 10/8, 172.16/12, 192.168/16 and the host | validate | PASS |
| SEC1 | DoT 1.1.1.1:853 and 8.8.8.8:853 | refused | no connection | nc on the client | PASS |
| SEC2 | DoH to 1.1.1.1, cloudflare-dns.com, dns.google | refused | connection refused (1.1.1.1, 104.16.249.249, 8.8.4.4) | wget on the client | PASS |
| SEC3 | VPS public IP from a client | refused | no connection on :443 | nc | PASS |
| SEC4 | Docker bridge 172.17.0.1 and the gateway network 10.53.53.1 | refused | no connection | nc | PASS |
| SEC5 | RFC1918 (192.168.1.1) | refused | no connection | nc | PASS |
| SEC6 | Site by IP (DNS-only limitation) | reachable (documented bypass) | chess.com's IP on 443 connected | nc | PASS (expected limitation) |
| SEC7 | Client access to tailnet services | limited by the access policy | default policy assumed (not confirmed); see client-setup.md | — | BLOCKED (needs a decision on the access policy) |

## Android (A) and hotspot (H)

| ID | Description | Expected | Actual | Evidence | Status |
|---|---|---|---|---|---|
| A1 | Always-on VPN reconnects after reboot | connected after unlock | — | — | MANUAL TEST REQUIRED |
| A2 | Lockdown: no data without the VPN | no data | — | — | MANUAL TEST REQUIRED |
| A3 | Mobile data: VPS IP, chess.com blocked | as stated | — | — | MANUAL TEST REQUIRED |
| A4 | Wi-Fi ↔ mobile data switch | reconnects | — | — | MANUAL TEST REQUIRED |
| A5 | Exit node can be turned off in the app | possible on the free plan (limitation) | — | — | MANUAL TEST REQUIRED |
| H1 | Phone public IP with the hotspot on | VPS IP | — | — | MANUAL TEST REQUIRED |
| H2 | Laptop public IP on the hotspot | mobile carrier IP (expected) | — | — | MANUAL TEST REQUIRED |
| H3 | Phone chess.com | blocked | — | — | MANUAL TEST REQUIRED |
| H4 | Laptop chess.com | loads (expected, not filtered) | — | — | MANUAL TEST REQUIRED |
| H5 | Cloudflare log shows the laptop's query | no (expected) | — | — | MANUAL TEST REQUIRED |
| H6 | Classification | UNSUPPORTED (expected) | — | — | MANUAL TEST REQUIRED |

## Acceptance criteria (kept separate)

1. **Working exit node:** PASS (V3, V4, RT1–RT3).
2. **Cloudflare DNS enforcement for exit-node clients:** PASS on the test client (D4–D7, D11, D12). The check in the Cloudflare log (D7b) is a manual test.
3. **Automatic Android VPN:** MANUAL TEST REQUIRED. Known limitation: the exit node can be turned off in the app on the free plan.
4. **Tethered-device enforcement:** not provided by this gateway. Expected to be UNSUPPORTED; to be confirmed on the real phone and laptop (H1–H6).
