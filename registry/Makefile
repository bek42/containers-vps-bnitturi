.PHONY: up down restart clean restart-clean install-cron

up:
	docker compose up -d

down:
	docker compose down

restart: down up

clean:
	docker compose down --rmi all

restart-clean: clean up

install-cron:
	@( crontab -l 2>/dev/null | grep -v 'containers/registry/gc.sh' ; \
	   echo "0 3 * * 0 $(PWD)/gc.sh" ) | crontab -
	@echo "Installed in bharani's crontab (no root needed): $(PWD)/gc.sh"
