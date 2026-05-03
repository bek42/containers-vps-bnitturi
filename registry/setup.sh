#!/bin/bash
set -e

echo "==> Installing GC cron job..."
echo '0 3 * * 0 root /home/bharani/containers/registry/gc.sh' \
  | sudo tee /etc/cron.d/registry-gc

echo ""
echo "==> Done! Now do this manually:"
echo "    cat > /home/bharani/secrets/registry-regbot.env << 'SECRETS'"
echo "    REGBOT_USER=youruser"
echo "    REGBOT_PASS=yourpassword"
echo "    SECRETS"
echo ""
echo "    Then run: docker compose up -d"