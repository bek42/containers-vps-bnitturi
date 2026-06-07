.PHONY: up down restart clean restart-clean ps logs

up:
	docker compose up -d

down:
	docker compose down

restart: down up

clean:
	docker compose down --rmi all

restart-clean: clean up

ps:
	docker compose ps

logs:
	docker compose logs --tail 30 -f
