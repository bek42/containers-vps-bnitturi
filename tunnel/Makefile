TUNNEL_ID := 53f49069-a8cd-410e-821e-1f2b868cc70f
CRED      := cloudflared/$(TUNNEL_ID).json

.PHONY: up down restart encrypt

up:
	age --decrypt -i ~/.config/age/keys.txt -o $(CRED) $(CRED).age
	chmod 644 $(CRED)
	docker compose up -d

down:
	docker compose down

restart: down up

encrypt:
	age -R ../recipients.txt -a -o $(CRED).age $(CRED)
