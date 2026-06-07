.PHONY: up down restart clean restart-clean edit ps logs

up:
	sops exec-env nginx.env 'docker compose up -d'

down:
	sops exec-env nginx.env 'docker compose down'

restart: down up

clean:
	sops exec-env nginx.env 'docker compose down --rmi all'

restart-clean: clean up

edit:
	sops edit nginx.env

ps:
	sops exec-env nginx.env 'docker compose ps'

logs:
	sops exec-env nginx.env 'docker compose logs --tail 30 -f'
