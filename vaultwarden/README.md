# Vaultwarden

Vaultwarden password manager with daily backup to OneDrive. Deployed as a Docker Swarm stack.

## Services

- `vaultwarden/server` — Vaultwarden server, exposed on port 8062
- `ttionya/vaultwarden-backup` — Daily backup at 05:05, zipped and uploaded to OneDrive via rclone

## Upgrade images

Update the image versions in `docker-compose.yml`, then:

```bash
docker compose pull
docker stack rm vaultwarden
docker stack deploy -c docker-compose.yml vaultwarden
```

## Check status

```bash
docker stack ps vaultwarden
docker stack services vaultwarden
```

## Troubleshooting: port conflict from old stack

If `docker stack ps vaultwarden` shows `"no suitable node (host-mode ports)"`, an old stack is holding port 8062. Find and remove it:

```bash
docker ps | grep vaultwarden        # identify the old stack name prefix
docker stack rm <old-stack-name>    # e.g. docker stack rm vw
docker stack deploy -c docker-compose.yml vaultwarden
```

## Secrets

All secrets are external and must exist in the Swarm secret store before deploying:

- `vw_domain_url`
- `vw_admin_token`
- `vw_smtp_host`
- `vw_smtp_port`
- `vw_email`
- `vw_email_pass`
- `vw_zip_pass`
