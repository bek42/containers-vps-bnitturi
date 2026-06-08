COMPOSE := docker compose -f simple-login-compose.yaml
SOPS    := sops exec-env simplelogin.env

.PHONY: up down restart clean restart-clean edit ps logs

up:
	$(SOPS) '$(COMPOSE) up -d'

down:
	$(SOPS) '$(COMPOSE) down'

restart: down up

clean:
	$(SOPS) '$(COMPOSE) down --rmi all'

restart-clean: clean up

edit:
	sops edit simplelogin.env

ps:
	$(SOPS) '$(COMPOSE) ps'

logs:
	$(SOPS) '$(COMPOSE) logs --tail 30 -f'
