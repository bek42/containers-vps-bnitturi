.PHONY: up down restart edit ps logs

up:
	sops exec-env vaultwarden.env 'docker compose up -d'

down:
	sops exec-env vaultwarden.env 'docker compose down'

restart: down up

edit:
	sops edit vaultwarden.env

ps:
	sops exec-env vaultwarden.env 'docker compose ps'

logs:
	sops exec-env vaultwarden.env 'docker compose logs --tail 30 -f'
