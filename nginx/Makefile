KEY        := $(HOME)/.config/age/keys.txt
RECIPIENTS := ../recipients.txt

.PHONY: up down restart decrypt encrypt

up: decrypt
	docker compose up -d

down:
	docker compose down

restart: down up

decrypt:
	@find . -name '*.age' -type f | while read -r f; do \
	  plain="$${f%.age}"; \
	  [ -f "$$plain" ] || age --decrypt --identity $(KEY) --output "$$plain" "$$f"; \
	done

encrypt:
	@find . -name '*.age' -type f | while read -r f; do \
	  plain="$${f%.age}"; \
	  if [ -f "$$plain" ]; then \
	    age --encrypt --armor --recipients-file $(RECIPIENTS) --output "$$f.new" "$$plain" && \
	    mv "$$f.new" "$$f"; \
	  fi; \
	done
