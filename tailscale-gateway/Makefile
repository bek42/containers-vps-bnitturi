.PHONY: up down restart ps logs edit login-url status test backup restore rollback pull

DATA := $(HOME)/container-data/tailscale-gateway
ENV  := tailscale-gateway.env
DC   := sops exec-env $(ENV)

up:            ## idempotent install/start: data dirs, config validation, start, show login URL if needed
	$(DC) 'scripts/install.sh'

down:
	$(DC) 'docker compose down'

restart:
	$(DC) 'docker compose restart'

pull:          ## controlled upgrade: bump image tags in docker-compose.yml first, then make pull up test
	$(DC) 'docker compose pull'

ps:
	$(DC) 'docker compose ps'

logs:
	$(DC) 'docker compose logs --tail 50 -f'

edit:
	sops edit $(ENV)

login-url:     ## one-time (or after logout): print the Tailscale login URL for node bnitturi-gateway
	@docker logs tailscale-gateway 2>&1 | grep -o 'https://login.tailscale.com/[^ ]*' | tail -1 || echo "no login URL (already logged in?)"

status:        ## health summary (no browsing data)
	scripts/healthcheck.sh

test:          ## server-side acceptance tests
	$(DC) 'scripts/validate.sh'

backup:        ## node identity + config snapshot (contains the node private key: kept 0600 under $(DATA)/backups)
	scripts/backup.sh

restore:       ## make restore FILE=$(DATA)/backups/tailscale-gateway-<stamp>.tar.gz
	@test -n "$(FILE)" || { echo "usage: make restore FILE=<backup.tar.gz>"; exit 1; }
	$(DC) 'scripts/restore.sh $(FILE)'

rollback:      ## stop and remove the gateway (keeps state and backups); host Tailscale unaffected
	$(DC) 'scripts/rollback.sh'
