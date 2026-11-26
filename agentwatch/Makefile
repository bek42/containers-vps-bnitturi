.PHONY: up down restart clean restart-clean edit ps logs login status scan run backup restore

DATA := $(HOME)/container-data/agentwatch

up:
	age --decrypt -i ~/.config/age/keys.txt -o api_keys.ini api_keys.ini.age
	chmod 600 api_keys.ini
	sops exec-env agentwatch.env 'docker compose up -d'

down:
	docker compose down

restart: down up

clean:
	docker compose down --rmi all

restart-clean: clean up

edit:
	sops edit agentwatch.env

ps:
	docker compose ps

logs:
	docker compose logs --tail 30 -f

# One time (and again only if the login ever expires): sign Claude Code in with the subscription. It prints a URL to approve in a browser.
login:
	docker exec -it agentwatch-core claude auth login

status:
	docker exec agentwatch-core aw status

scan:
	docker exec agentwatch-core aw scan

run:
	docker exec agentwatch-core aw run

# Backup of everything that matters, EXCLUDING the Claude sign-in and the rebuildable site. Keeps 14 days.
backup:
	@mkdir -p $(DATA)/backups
	tar -C $(DATA) --exclude=./claude --exclude=./site --exclude=./backups --exclude=./logs -czf $(DATA)/backups/agentwatch-$$(date -u +%Y%m%dT%H%M%SZ).tar.gz .
	@find $(DATA)/backups -name 'agentwatch-*.tar.gz' -mtime +14 -delete
	@ls -lh $(DATA)/backups | tail -3

# make restore FILE=/home/bharani/container-data/agentwatch/backups/agentwatch-....tar.gz   (stops the stack, restores, starts it)
restore:
	@test -n "$(FILE)" || { echo "usage: make restore FILE=<backup.tar.gz>"; exit 1; }
	docker compose down
	tar -C $(DATA) -xzf $(FILE)
	$(MAKE) up
