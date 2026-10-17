# CLAUDE.md

## Where things run

- **Dev machine** (`vps-ab21cf59`, this checkout at `~/projects/containers-vps-bnitturi`): editing only. No service containers, no `~/container-data`.
- **Deploy host**: `ssh bnitturi` (hostname `vps-0f67a25d`, user `bharani`), reached over Tailscale. The containers run here.
  - Repo clone: `~/containers` (same GitHub remote, branch `main`)
  - Runtime data: `~/container-data/<service>/`
  - sops/age keys are on the host, so `make up` etc. work there.

## Deploying a change

Run each service from its own directory on the deploy host, always through the Makefile (it injects secrets via `sops exec-env`; a bare `docker compose up` starts the service without secrets):

```bash
ssh bnitturi 'cd ~/containers && git pull && cd <service> && docker compose pull && make up'
```

## Image updates: how to check

- Docker Hub tags: `curl -s "https://hub.docker.com/v2/repositories/<ns>/<repo>/tags?page_size=15&ordering=last_updated"`
- Read the GitHub release notes for breaking changes before you bump.
- After bumping a tag, also update the image table in that service's `README.md`.
- To verify a deploy: `docker ps` shows the new tag, the container's image ID matches the tag's image ID, the container is healthy, the logs show the expected version, and the local port responds.
- Public URLs sit behind Cloudflare. A plain `curl` gets a `403` bot challenge (`cf-mitigated: challenge`), so pass a browser `-A` user-agent when checking them.
