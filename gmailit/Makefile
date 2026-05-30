COMPOSE := docker compose -f simple-login-compose.yaml
SOPS    := sops exec-env simplelogin.env

.PHONY: up down restart edit ps logs

up:
	$(SOPS) '$(COMPOSE) up -d'

down:
	$(SOPS) '$(COMPOSE) down'

restart: down up

edit:
	sops edit simplelogin.env

ps:
	$(SOPS) '$(COMPOSE) ps'

logs:
	$(SOPS) '$(COMPOSE) logs --tail 30 -f'
