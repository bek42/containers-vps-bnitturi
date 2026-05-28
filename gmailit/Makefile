COMPOSE := docker compose -f simple-login-compose.yaml

.PHONY: up down restart edit

up:
	sops exec-env simplelogin.env '$(COMPOSE) up -d'

down:
	$(COMPOSE) down

restart: down up

edit:
	sops edit simplelogin.env
