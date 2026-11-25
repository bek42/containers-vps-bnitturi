# agentwatch

Wiki site and podcast feed for the agentwatch project (source: `bek42/agentwatch`). CI builds the image and bumps the tag in `docker-compose.yml` on every deploy.

| Service | Container | Image | Purpose |
|---|---|---|---|
| `agentwatch` | `agentwatch` | `reg.greatsky.co.uk/agentwatch:<sha>` | Python server: Quartz wiki, `/listen` podcast player + API, private feed |

Bound to `127.0.0.1:8085`; reached through the tunnel as `wiki.bnitturi.com` behind Cloudflare Access.
Podcast data: `~/container-data/agentwatch/podcast/` (mounted read-write at `/data`: `episodes/`, `state.json`, `token`). Episodes are uploaded from the dev box with `publish_podcast.sh` and deleted from the `/listen` page.
