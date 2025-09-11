# 📘 SimpleLogin Self-Hosted Setup & Upgrade Guide

This guide documents how to deploy and maintain a self-hosted
[SimpleLogin](https://github.com/simple-login/app) instance with email
forwarding, Postfix, DKIM signing, and OVH/Cloudflare DNS integration.

------------------------------------------------------------------------

## 1. 🔧 Prerequisites

-   VPS with public IP (e.g., OVH)\
-   Domain name (e.g., `gmailit.com`)\
-   Cloudflare (or your DNS provider)\
-   Docker + Docker Compose installed\
-   Basic understanding of DNS, Postfix, TLS

------------------------------------------------------------------------

## 2. 📡 DNS Configuration

Configure DNS for `gmailit.com` in Cloudflare:

### A Records

  --------------------------------------------------------------------------
  Name          Type      Value                  Proxy       Purpose
  ------------- --------- ---------------------- ----------- ---------------
  gmailit.com   A         `51.68.227.202`        DNS only    Root mail/web
                                                             host

  smtp          A         `51.68.227.202`        DNS only    Outbound SMTP

  app           CNAME     `<CF Tunnel ID>`       Proxied     Web dashboard
                                                             (via tunnel)
  --------------------------------------------------------------------------

### MX Records

  Name          Type   Value              Priority   Proxy
  ------------- ------ ------------------ ---------- ----------
  gmailit.com   MX     smtp.gmailit.com   10         DNS only

### TXT Records

-   **SPF**

        v=spf1 ip4:51.68.227.202 -all

-   **DKIM** (selector `dkim`)

        dkim._domainkey.gmailit.com  IN TXT "v=DKIM1; k=rsa; p=<your-public-key>"

-   **DMARC**

        _dmarc.gmailit.com  IN TXT "v=DMARC1; p=quarantine; rua=mailto:postmaster@gmailit.com"

-   **TLS-RPT** (optional)

        _smtp._tls.gmailit.com  IN TXT "v=TLSRPTv1; rua=mailto:postmaster@gmailit.com"

-   **MTA-STS** (optional, requires policy file)

        _mta-sts.gmailit.com  IN TXT "v=STSv1; id=20240901"

✅ Ensure **PTR/rDNS** at OVH is set:\
`51.68.227.202 → smtp.gmailit.com`

------------------------------------------------------------------------

## 3. 📦 Container Setup

### Directory Structure

    ~/containers/gmailit/
      ├── docker-compose.yml
      ├── .env
      ├── secrets/
      │   ├── dkim.key
      │   └── dkim.pub.key
      ├── container-data/
          ├── pgp/
          ├── upload/

### Example `docker-compose.yml`

``` yaml
version: "3.9"

services:
  app:
    image: simplelogin/app:4.6.5-beta
    container_name: sl-app
    env_file:
      - ./gmailit.env
    volumes:
      - ./container-data/gmailit/upload:/code/static/upload
    depends_on:
      - db
    restart: unless-stopped

  email:
    image: simplelogin/app:4.6.5-beta
    container_name: sl-email
    command: ["python", "email_handler.py"]
    env_file:
      - ./gmailit.env
    volumes:
      - ./container-data/gmailit/pgp:/sl/pgp
      - ./container-data/gmailit/upload:/code/static/upload
      - ./secrets/dkim.key:/dkim.key:ro
      - ./secrets/dkim.pub.key:/dkim.pub.key:ro
    environment:
      - DKIM_PRIVATE_KEY_PATH=/dkim.key
      - DKIM_SELECTOR=dkim
      - EMAIL_DOMAIN=gmailit.com
    depends_on:
      - app
    restart: unless-stopped

  db:
    image: postgres:14
    container_name: sl-db
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    env_file:
      - ./db.env
    restart: unless-stopped
```

------------------------------------------------------------------------

## 4. 🔑 DKIM Setup

1.  Generate key:

    ``` bash
    openssl genrsa -out dkim.key 2048
    openssl rsa -in dkim.key -pubout -out dkim.pub.key
    ```

2.  Place in `secrets/` and mount into `sl-email`.\

3.  Add DNS TXT record:

        dkim._domainkey.gmailit.com "v=DKIM1; k=rsa; p=<contents of dkim.pub.key>"

4.  Verify:

    ``` bash
    docker exec -it sl-email openssl rsa -in /dkim.key -pubout -outform DER 2>/dev/null | openssl base64 -A
    dig txt dkim._domainkey.gmailit.com +short
    ```

    Both must match.

------------------------------------------------------------------------

## 5. 📬 Postfix Setup

Postfix runs inside the `sl-app` container.\
- Ensure `/etc/postfix/main.cf` is configured with: -
`myhostname = smtp.gmailit.com` - `smtpd_tls_security_level = may` -
`smtpd_tls_cert_file` and `smtpd_tls_key_file` (Let's Encrypt or
certbot) - Restart container after edits: `bash   docker restart sl-app`

------------------------------------------------------------------------

## 6. 🚀 Deployment

``` bash
docker compose pull
docker compose up -d
docker ps
```

Check logs:

``` bash
docker logs -f sl-email
docker logs -f sl-app
```

------------------------------------------------------------------------

## 7. ✅ Testing Deliverability

Send test mail and check with: - **Gmail → "Show original"**\
- Verify: - `SPF: PASS` - `DKIM: PASS` - `DMARC: PASS` - If DKIM fails:
check selector, key, permissions.\
- If SPF fails: check IPs in TXT record.

Use <https://www.mail-tester.com> for score.

------------------------------------------------------------------------

## 8. 🔄 Upgrades

1.  Pull latest image:

    ``` bash
    docker compose pull
    docker compose up -d
    ```

2.  Check logs for DB migrations:

    ``` bash
    docker logs sl-app | grep migration
    ```

3.  Backup before upgrading:

    ``` bash
    docker exec -t sl-db pg_dumpall -c -U postgres > backup.sql
    ```

------------------------------------------------------------------------

## 9. 🛠 Maintenance

-   Monitor logs:

    ``` bash
    docker logs -f sl-email
    docker logs -f sl-app
    ```

-   Rotate DKIM keys annually (update DNS + container).\

-   Check blocklists:
    [mxtoolbox.com/blacklists](https://mxtoolbox.com/blacklists).\

-   Adjust **DMARC policy**:

    -   Start with `p=none`\
    -   Move to `p=quarantine` → `p=reject` once confident.

------------------------------------------------------------------------

## 10. 🔒 Security Best Practices

-   Keep all DNS **DNS only** (no proxy) for mail records.\
-   TLS certificates via Let's Encrypt + cron renewal.\
-   Limit outgoing rate in Postfix (`anvil`) to avoid spam-flagging.\
-   Use separate mailbox for TLSRPT and DMARC reports.

------------------------------------------------------------------------
