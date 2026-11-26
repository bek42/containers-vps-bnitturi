# agentwatch

Personal AI research analyst: research collection, wiki, podcast and an interactive chat. Source: `bek42/agentwatch`.
One Compose project, two containers. CI (Commitizen, then build, then deploy with automatic rollback) pins the image lines to `tag@digest`.

| Service | Container | Image | Purpose |
|---|---|---|---|
| `agentwatch` | `agentwatch` | `reg.greatsky.co.uk/agentwatch:<version>` | Website server: wiki, `/listen` player, search, job API. `127.0.0.1:8085`, reached through the tunnel as `wiki.bnitturi.com` behind Cloudflare Access |
| `agentwatch-core` | `agentwatch-core` | `reg.greatsky.co.uk/agentwatch-core:<version>` | Scheduler, research pipeline, Claude worker (chat, on-demand episodes), narration, website build. No ports |

Data: `~/container-data/agentwatch/` = `workspace/` (research, wiki, episodes, state), `podcast/` (what the website reads and writes), `site/` (built website), `state/`, `logs/`, `backups/`, `claude/` (Claude Code sign-in).
Secrets: `agentwatch.env` (sops: OpenAI key, notification address), `api_keys.ini.age` (age: SMTP lookup). Claude uses the owner's subscription sign-in in `claude/`; no API key is configured anywhere.

```
make up | down | restart | ps | logs     standard stack commands (up decrypts secrets)
make login      one-time Claude Code subscription sign-in (prints a URL to approve)
make status | scan | run                  status, research scan now, one editorial run now
make backup | restore FILE=...
```

First start or after a migration the stack is in standby (`AW_STANDBY: "1"` in `docker-compose.yml`): it is up and can be signed in and inspected, but runs no jobs.
To go live, set it to `"0"`, commit, push, `git pull` on the host, `make up`.
Full guide, schedule, settings and troubleshooting: `docs/OPERATIONS.md` in `bek42/agentwatch`.
