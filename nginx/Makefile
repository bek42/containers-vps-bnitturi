.PHONY: up down restart edit ps logs

up:
	sops exec-env nginx.env 'docker compose up -d'

down:
	sops exec-env nginx.env 'docker compose down'

restart: down up

edit:
	sops edit nginx.env

ps:
	sops exec-env nginx.env 'docker compose ps'

logs:
	sops exec-env nginx.env 'docker compose logs --tail 30 -f'
