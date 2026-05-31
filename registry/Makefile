.PHONY: up down restart install-cron

up:
	docker compose up -d

down:
	docker compose down

restart: down up

install-cron:
	@echo "0 3 * * 0 root $(PWD)/gc.sh" \
	  | sudo tee /etc/cron.d/registry-gc > /dev/null
	@echo "Installed: /etc/cron.d/registry-gc"
