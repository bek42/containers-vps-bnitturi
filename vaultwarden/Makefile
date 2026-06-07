.PHONY: up down restart clean restart-clean edit ps logs

up:
	sops exec-env vaultwarden.env 'docker compose up -d'

down:
	sops exec-env vaultwarden.env 'docker compose down'

restart: down up

clean:
	sops exec-env vaultwarden.env 'docker compose down --rmi all'

restart-clean: clean up

edit:
	sops edit vaultwarden.env

ps:
	sops exec-env vaultwarden.env 'docker compose ps'

logs:
	sops exec-env vaultwarden.env 'docker compose logs --tail 30 -f'
