# agentwatch

Wiki site and podcast feed for the agentwatch project (source: `bek42/agentwatch`). CI builds the image and bumps the tag in `docker-compose.yml` on every deploy.

| Service | Container | Image | Purpose |
|---|---|---|---|
| `agentwatch` | `agentwatch` | `reg.greatsky.co.uk/agentwatch:<sha>` | nginx serving the Quartz wiki and `/podcast/` |

Bound to `127.0.0.1:8085`; reached through the tunnel as `wiki.bnitturi.com` behind Cloudflare Access.
Podcast files: `~/container-data/agentwatch/podcast/` (mounted read-only at `/podcast`).
