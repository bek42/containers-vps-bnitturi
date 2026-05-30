.PHONY: up down restart ps logs

up:
	docker compose up -d

down:
	docker compose down

restart: down up

ps:
	docker compose ps

logs:
	docker compose logs --tail 30 -f
