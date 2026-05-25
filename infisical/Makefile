.PHONY: up down restart edit

up:
	sops exec-env infisical.env 'docker compose up -d'

down:
	docker compose down

restart: down up

edit:
	sops edit infisical.env
