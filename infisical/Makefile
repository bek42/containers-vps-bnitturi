.PHONY: up down restart clean restart-clean edit ps logs

up:
	TAILSCALE_IP=$$(tailscale ip -4) sops exec-env infisical.env 'docker compose up -d'

down:
	sops exec-env infisical.env 'docker compose down'

restart: down up

clean:
	sops exec-env infisical.env 'docker compose down --rmi all'

restart-clean: clean up

edit:
	sops edit infisical.env

ps:
	sops exec-env infisical.env 'docker compose ps'

logs:
	sops exec-env infisical.env 'docker compose logs --tail 30 -f'
