# Operations, troubleshooting and recovery

Run every command from `~/containers/tailscale-gateway` on the VPS. Changes reach the host only through Git: commit in the containers repository, push, `git pull` on the host, then `make up`.

## Commands

| Purpose | Command |
|---|---|
| Status (health summary, no browsing data) | `make status` |
| Acceptance tests (server side) | `make test`. Add the restart check with `sops exec-env tailscale-gateway.env 'scripts/validate.sh --restart'` |
| Logs | `make logs`, or `docker logs --tail 100 tailscale-gateway` |
| Tailscale state | `docker exec tailscale-gateway tailscale status`, plus `tailscale netcheck` for direct vs relayed connectivity |
| DNS check through the forwarder | `docker exec tailscale-gateway nslookup chess.com 10.53.53.53` should give 0.0.0.0. `wikipedia.org` should give a real address. |
| Connectivity | `docker exec tailscale-gateway wget -qO- https://api.ipify.org` should give the VPS IP |
| Restart | `make restart`, or `docker compose restart tailscale` |
| Start or reinstall (idempotent) | `make up` |
| Log in again (after a logout or a deleted machine) | `make login`: opens a URL and waits up to 15 minutes |
| Upgrade | Change the image tags in `docker-compose.yml` and commit. Then on the host: `git pull`, `make pull up test` |
| Backup | `make backup`: node identity plus config, written to `~/container-data/tailscale-gateway/backups` (keeps 10, mode 0600) |
| Restore | `make restore FILE=~/container-data/tailscale-gateway/backups/tailscale-gateway-<stamp>.tar.gz` |
| Rollback (remove the gateway) | `make rollback`: stops and removes both containers and the network, and keeps state and backups. Clients using it lose internet until they turn the exit node off. The host Tailscale is unaffected. To remove it completely, also `git revert` the commits and delete the machine in the admin console. |

## Failure behaviour (fail closed)

| Failure | Client effect | Tested |
|---|---|---|
| Forwarder down | All DNS times out. There is no fallback and nothing unfiltered. | yes (V-F1) |
| Gateway container down | No DNS and no traffic: the client keeps its exit node and does not fall back to a direct path. | yes (V-F2, V-F3) |
| Cloudflare DoH unreachable | DNS fails. The dns health check turns unhealthy. | by design (no fallback configured) |
| tailscaled reorders firewall chains | The watchdog restores them within 15 seconds. The health check flags it in the meantime. | yes (V-F4) |
| Phone's Tailscale stopped | With lockdown on, no data. Without it, **unfiltered**. | MANUAL TEST REQUIRED |

## Common problems

| Symptom | Check | Fix |
|---|---|---|
| `make up` says "not logged in" | the state was removed or the machine was deleted | `make login` |
| Node offline in the admin console | `docker ps`, `make logs` | `make up` |
| Clients have no internet | `make status`. Is the exit node still approved? Edit route settings in the admin console. | `make restart` |
| Everything blocked, or nothing blocked | `nslookup wikipedia.org 10.53.53.53` and `nslookup chess.com 10.53.53.53` from inside the gateway | Check the location DoH URL (`make edit`) and the Cloudflare policy |
| Slow | `tailscale ping <client>` from inside the gateway: "via DERP" means relayed traffic | Direct connections need UDP from outside to reach the gateway. That would mean publishing a UDP port and changing ufw, which is a host firewall change that needs approval. Relayed traffic works, only slower. |

## Parent-controlled recovery (the child's phone)

Use this when the phone has no data: gateway down, a Wi-Fi login page, or travel.

1. **Emergency calls and SMS always work.** They do not use the VPN.
2. **Short-term internet without filtering:** a parent unlocks the phone, goes to Settings → VPN → Tailscale ⚙, and turns off **Block connections without VPN**. Turn it back on afterwards.
3. **Filtering without the VPS:** at home, the home network's own Cloudflare setup still applies.
4. **The gateway itself:** `make status`, then `make restart`. If the state is lost, use `make restore FILE=...`; failing that, `make login` and approve the URL.
5. Only a parent account holds the Tailscale admin role and the Family Link controls.
