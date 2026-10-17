COMPOSE := docker compose -f simple-login-compose.yaml
# .env (config) and simplelogin.env (secrets) are both sops-encrypted; decrypt both into the env
sops-run = sops exec-env .env 'sops exec-env simplelogin.env "$(1)"'

.PHONY: up down restart clean restart-clean edit ps logs

up:
	$(call sops-run,$(COMPOSE) up -d)

down:
	$(call sops-run,$(COMPOSE) down)

restart: down up

clean:
	$(call sops-run,$(COMPOSE) down --rmi all)

restart-clean: clean up

edit:
	sops edit simplelogin.env

ps:
	$(call sops-run,$(COMPOSE) ps)

logs:
	$(call sops-run,$(COMPOSE) logs --tail 30 -f)
