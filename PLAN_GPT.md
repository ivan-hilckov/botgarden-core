### Botgarden Core — Production Infrastructure Plan

This plan delivers a minimal, secure, and scalable foundation to run multiple Telegram bots on a single VPS using Docker, Nginx, and PostgreSQL. It standardizes deployment for both the core stack and per‑bot instances with SSL termination, webhook routing, and SSH automation.

---

### 1) Recommended Components

- **Reverse proxy**: Nginx `nginx:1.25-alpine`
  - Lightweight, HTTP/2, TLSv1.3, solid performance
- **Database**: PostgreSQL `postgres:16-alpine`
  - Modern features, low idle RAM, stable
- **Certificates**: Certbot `certbot/certbot:v2.10.0`
  - One-shot container for issue/renew via webroot
- **Optional monitoring**:
  - **Logs**: Nginx access/error logs + `docker logs`
  - **Auto updates (opt-in)**: `containrrr/watchtower:1.7.1`
  - **Observability (later)**: `grafana/loki` + `grafana/promtail`

Notes:

- Keep the core stack small: only Nginx, Postgres, and volumes for certificates and data.
- Use Let’s Encrypt via webroot. Run renew via cron on the VPS.

---

### 2) Concrete Implementation Examples

#### 2.1 `docker-compose.yml` (botgarden-core)

Place in `botgarden-core/docker-compose.yml`.

```yaml
version: "3.9"

services:
  nginx:
    image: nginx:1.25-alpine
    container_name: bg-nginx
    restart: unless-stopped
    depends_on:
      - postgres
    ports:
      - "80:80"
      - "443:443"
    command: /bin/sh -c "envsubst < /etc/nginx/templates/core.conf.template > /etc/nginx/conf.d/core.conf && nginx -g 'daemon off;'"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/templates/core.conf.template:/etc/nginx/templates/core.conf.template:ro
      - certbot-www:/var/www/certbot:ro
      - letsencrypt:/etc/letsencrypt:ro
      - ./logs/nginx:/var/log/nginx
    environment:
      - TZ=${TZ}
      - DOMAIN=${DOMAIN}
      - ALT_DOMAINS=${ALT_DOMAINS}
    networks:
      - botgarden

  postgres:
    image: postgres:16-alpine
    container_name: bg-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      TZ: ${TZ}
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./backups:/backups
    ports:
      - "${POSTGRES_PORT}:5432"
    networks:
      - botgarden

  certbot:
    image: certbot/certbot:v2.10.0
    container_name: bg-certbot
    volumes:
      - certbot-www:/var/www/certbot
      - letsencrypt:/etc/letsencrypt
    entrypoint: ["/bin/sh", "-c", "sleep infinity"]
    networks:
      - botgarden

volumes:
  pg_data:
  certbot-www:
  letsencrypt:

networks:
  botgarden:
    name: botgarden
    driver: bridge
```

Why this layout:

- Single user-defined network `botgarden` lets independent bot projects join and be reachable by Nginx.
- Nginx uses `envsubst` to render a template from env vars on container start.
- `certbot` is a helper container for issue/renew tasks.

#### 2.2 Nginx config with SSL and dynamic webhook routing

Create `nginx/nginx.conf` and `nginx/templates/core.conf.template`.

`nginx/nginx.conf`:

```nginx
user  nginx;
worker_processes  auto;

error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
  worker_connections  1024;
}

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                  '$status $body_bytes_sent "$http_referer" '
                  '"$http_user_agent" "$http_x_forwarded_for"';
  access_log /var/log/nginx/access.log main;

  sendfile        on;
  keepalive_timeout  65;
  server_tokens off;

  include /etc/nginx/conf.d/*.conf;
}
```

`nginx/templates/core.conf.template`:

```nginx
server {
  listen 80;
  listen [::]:80;
  server_name ${DOMAIN} ${ALT_DOMAINS};

  location /.well-known/acme-challenge/ {
    root /var/www/certbot;
  }

  location / {
    return 301 https://$host$request_uri;
  }
}

server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name ${DOMAIN} ${ALT_DOMAINS};

  ssl_certificate     /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
  ssl_protocols       TLSv1.2 TLSv1.3;
  ssl_ciphers         HIGH:!aNULL:!MD5;

  add_header X-Content-Type-Options nosniff;
  add_header X-Frame-Options DENY;
  add_header Referrer-Policy no-referrer-when-downgrade;

  location = /healthz {
    return 200 'ok';
  }

  # /webhook/<botname> → http://<botname>:8080/webhook
  location ~* ^/webhook/(?<botname>[a-z0-9\-\_]+)$ {
    set $upstream_host "$botname:8080";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_http_version 1.1;
    proxy_read_timeout 75s;
    proxy_connect_timeout 5s;
    proxy_send_timeout 30s;
    proxy_pass http://$upstream_host/webhook;
  }
}
```

Scaling:

- Each bot container sets `container_name` to the bot name used in the webhook URL and listens on port `8080` at path `/webhook`.
- No per-bot Nginx edits are required.

#### 2.3 Issue and renew SSL certificates (Let’s Encrypt)

After `docker compose up -d`, obtain initial certs (ensure DNS points to your VPS and `.env` is set):

```bash
docker compose run --rm certbot certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" ${ALT_DOMAINS:+-d $ALT_DOMAINS} \
  --email "$LETSENCRYPT_EMAIL" --agree-tos --no-eff-email

docker compose exec nginx nginx -s reload
```

Renew via cron on VPS:

```bash
docker compose run --rm certbot certbot renew --webroot -w /var/www/certbot --quiet
docker compose exec nginx nginx -s reload || true
```

#### 2.4 `.env` templates

`botgarden-core/.env.core.example`:

```dotenv
# Core infrastructure
DOMAIN=example.com
ALT_DOMAINS=
LETSENCRYPT_EMAIL=admin@example.com

TZ=UTC

# Postgres
POSTGRES_USER=botgarden
POSTGRES_PASSWORD=change-me-strong
POSTGRES_DB=botgarden
POSTGRES_PORT=5432
```

Copy to `.env` and set proper values.

`hello-bot/.env.bot.example` (in each bot repo):

```dotenv
# Bot identity and runtime
BOT_NAME=hello-bot
BOT_PORT=8080

# Telegram
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN
WEBHOOK_SECRET=optional-secret
WEBHOOK_BASE=https://example.com/webhook  # final URL: ${WEBHOOK_BASE}/${BOT_NAME}

# Database (shared Postgres in core)
POSTGRES_HOST=bg-postgres
POSTGRES_PORT=5432
POSTGRES_DB=botgarden
POSTGRES_USER=botgarden
POSTGRES_PASSWORD=change-me-strong
```

#### 2.5 Dockerfile for `hello-bot`

Place in the bot repository as `Dockerfile` (assumes app binds `0.0.0.0:${BOT_PORT}` and `/webhook`).

```dockerfile
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    BOT_PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY . ./

RUN useradd -m bot && chown -R bot:bot /app
USER bot

EXPOSE 8080

CMD ["python", "-m", "app"]
```

#### 2.6 Minimal `docker-compose.bot.yml` (per bot)

```yaml
version: "3.9"
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ${BOT_NAME}
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - BOT_PORT=${BOT_PORT}
    networks:
      - botgarden
    expose:
      - "${BOT_PORT}"

networks:
  botgarden:
    external: true
```

This joins the `botgarden` network created by the core stack so Nginx can reach the bot as `http://$BOT_NAME:$BOT_PORT`.

#### 2.7 SSH deployment scripts (with error handling)

Place scripts in `botgarden-core/scripts/` and `hello-bot/scripts/`, then `chmod +x`.

`botgarden-core/scripts/deploy_core.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 -h <host> -u <ssh_user> [-p <ssh_port>]" >&2
  exit 1
}

HOST=""; SSH_USER=""; SSH_PORT=22
while getopts ":h:u:p:" opt; do
  case $opt in
    h) HOST=$OPTARG ;;
    u) SSH_USER=$OPTARG ;;
    p) SSH_PORT=$OPTARG ;;
    *) usage ;;
  esac
done
[[ -z "$HOST" || -z "$SSH_USER" ]] && usage

ROOT_DIR=/opt/botgarden-core

echo "[+] Ensuring Docker is installed on $HOST"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" 'command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh'
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" 'sudo usermod -aG docker $USER || true'

echo "[+] Creating target dir $ROOT_DIR"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "mkdir -p $ROOT_DIR"

echo "[+] Syncing repository files"
rsync -az --delete -e "ssh -p $SSH_PORT" ./ "$SSH_USER@$HOST:$ROOT_DIR/"

echo "[+] Preparing env (.env)"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "cd $ROOT_DIR && cp -n .env.core.example .env || true"

echo "[+] Bringing up core stack"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "cd $ROOT_DIR && docker compose up -d --remove-orphans"

echo "[i] If first run: obtain TLS certs and reload Nginx"
echo "    ssh -p $SSH_PORT $SSH_USER@$HOST 'cd $ROOT_DIR && \\
      docker compose run --rm certbot certbot certonly --webroot -w /var/www/certbot \\
        -d \"$DOMAIN\" ${ALT_DOMAINS:+-d $ALT_DOMAINS} \\
        --email \"$LETSENCRYPT_EMAIL\" --agree-tos --no-eff-email && \\
      docker compose exec nginx nginx -s reload'"

echo "[+] Core info:"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "bash -lc 'cd $ROOT_DIR && set -a && source .env && set +a && \\
  echo Postgres: host=bg-postgres port=\"\$POSTGRES_PORT\" user=\"\$POSTGRES_USER\" db=\"\$POSTGRES_DB\" && \\
  echo Webhook base: https://\$DOMAIN/webhook/<botname> && \\
  echo Health: https://\$DOMAIN/healthz'"

echo "[✓] Core deployed"
```

`hello-bot/scripts/deploy_bot.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 -h <host> -u <ssh_user> [-p <ssh_port>]" >&2
  exit 1
}

HOST=""; SSH_USER=""; SSH_PORT=22
while getopts ":h:u:p:" opt; do
  case $opt in
    h) HOST=$OPTARG ;;
    u) SSH_USER=$OPTARG ;;
    p) SSH_PORT=$OPTARG ;;
    *) usage ;;
  esac
done
[[ -z "$HOST" || -z "$SSH_USER" ]] && usage

BOT_DIR=/opt/bots/$(basename "$(pwd)")

echo "[+] Ensuring core network exists"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "docker network inspect botgarden >/dev/null 2>&1 || docker network create botgarden"

echo "[+] Creating target dir $BOT_DIR"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "mkdir -p $BOT_DIR"

echo "[+] Syncing bot repo"
rsync -az --delete -e "ssh -p $SSH_PORT" ./ "$SSH_USER@$HOST:$BOT_DIR/"

echo "[+] Preparing env (.env)"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "cd $BOT_DIR && cp -n .env.bot.example .env || true"

echo "[+] Building and starting bot"
ssh -p "$SSH_PORT" "$SSH_USER@$HOST" "cd $BOT_DIR && docker compose -f docker-compose.bot.yml up -d --build"

if [ -f .env ]; then
  set -a; source .env; set +a
  echo "[i] Webhook URL: ${WEBHOOK_BASE}/${BOT_NAME}"
fi

echo "[✓] Bot deployed"
```

Optional cron on VPS for cert renew (e.g. `crontab -e`):

```cron
0 3 * * * cd /opt/botgarden-core && docker compose run --rm certbot certbot renew --webroot -w /var/www/certbot --quiet && docker compose exec nginx nginx -s reload
```

---

### 3) Step-by-step Implementation Plan

#### VPS setup and SSH key configuration

- Create a non-root sudo user, upload SSH public key, disable password login.
- Install Docker: `curl -fsSL https://get.docker.com | sh` and re-login to apply `docker` group.
- Configure firewall to allow ports 22, 80, 443 (see Security section for `ufw`).

#### Botgarden-core infrastructure initialization

1. Clone `botgarden-core` locally.
2. Copy `.env.core.example` → `.env` and set values (`DOMAIN`, `LETSENCRYPT_EMAIL`, Postgres creds, `TZ`).
3. Run deployment: `scripts/deploy_core.sh -h <ip-or-domain> -u <ssh_user>`.
4. Obtain certificates (first run) and reload Nginx (commands printed by the script).

#### SSL certificate creation (Let’s Encrypt)

- Use the `certbot` container via webroot as shown above. Ensure DNS resolves to VPS.
- Add the renew cron afterwards.

#### PostgreSQL configuration with users/databases

- Default database and user created from `.env`.
- Optionally create per-bot DB or schemas:

```bash
docker compose exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE hello_bot;"
```

#### Nginx virtual hosts setup

- Provided template handles HTTP→HTTPS, ACME webroot challenge, and `/webhook/<botname>` routing.
- No per-bot config changes required if `container_name` equals `<botname>`.

#### Webhook endpoints testing

- Health: `curl -I https://$DOMAIN/healthz` should return `200`.
- Test route to a dummy upstream (if a bot is up):

```bash
curl -i https://$DOMAIN/webhook/hello-bot
```

#### First hello-bot deployment

1. Clone the `hello-bot` repo.
2. Fill `.env` from `.env.bot.example` (set `BOT_NAME`, `BOT_TOKEN`, DB creds, `WEBHOOK_BASE`).
3. Deploy: `scripts/deploy_bot.sh -h <ip-or-domain> -u <ssh_user>`.
4. Ensure the bot application registers its webhook at startup to `${WEBHOOK_BASE}/${BOT_NAME}` (aiogram snippet below).

Aiogram example (inside bot startup):

```python
from aiogram import Bot
import os, asyncio, aiohttp

BOT_TOKEN = os.environ["BOT_TOKEN"]
WEBHOOK_BASE = os.environ["WEBHOOK_BASE"].rstrip('/')
BOT_NAME = os.environ["BOT_NAME"]
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "")

async def set_webhook():
    url = f"{WEBHOOK_BASE}/{BOT_NAME}"
    if WEBHOOK_SECRET:
        url += f"?secret={WEBHOOK_SECRET}"
    bot = Bot(token=BOT_TOKEN, session=aiohttp.ClientSession())
    await bot.set_webhook(url=url, drop_pending_updates=True)
    await bot.session.close()

asyncio.run(set_webhook())
```

#### Backup and update procedures

- Backups (daily):

```bash
TS=$(date +%F_%H%M)
docker compose exec -T postgres pg_dumpall -U "$POSTGRES_USER" > "backups/pg_${TS}.sql"
find backups -type f -name 'pg_*.sql' -mtime +14 -delete
```

- Update core images safely:

```bash
docker compose pull
docker compose up -d
```

- Update a bot without downtime (rolling at container level):

```bash
docker compose -f docker-compose.bot.yml up -d --build
```

#### Monitoring and troubleshooting

- Nginx logs: `logs/nginx/access.log`, `logs/nginx/error.log`.
- Container logs: `docker logs bg-nginx`, `docker logs bg-postgres`, per-bot `docker logs <BOT_NAME>`.
- Network: ensure `botgarden` network exists and bots are attached.

---

### 4) Security and Best Practices

- **Secrets and API keys**

  - Store in `.env`; never commit real secrets. Keep only `*.example` in git.
  - Restrict repo access; use SSH, not passwords. Consider using an external secret manager later.

- **Network isolation**

  - Only Nginx exposes ports 80/443. Bots use `expose` only; no host port publishing.
  - All services share the private `botgarden` Docker network.

- **VPS firewall rules (ufw)**
  - Allow SSH, HTTP, HTTPS:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

- **PostgreSQL hardening**

  - Strong passwords, no host port exposure beyond what is necessary (optionally keep Postgres unexposed by removing the host port mapping and let bots connect over the Docker network only).
  - Regular backups and retention policy.

- **TLS**

  - Use Let’s Encrypt. Renew via cron. Reload Nginx post-renew.

- **Rolling updates**

  - Core: `docker compose pull && docker compose up -d`.
  - Bots: `docker compose -f docker-compose.bot.yml up -d --build`.
  - Use health checks per bot (optional) before switching traffic if you introduce multiple replicas later.

- **Least privilege**
  - Run bot processes as non-root users in containers.
  - Limit container capabilities (future enhancement).

---

### Outputs after deployment

- **PostgreSQL**: `host=bg-postgres port=$POSTGRES_PORT user=$POSTGRES_USER db=$POSTGRES_DB` (inside Docker network). If you need external access, use the mapped port from `.env` and VPS IP.
- **Webhook base**: `https://$DOMAIN/webhook/<botname>` → upstream `http://<botname>:8080/webhook` inside Docker network.
- **Health**: `https://$DOMAIN/healthz`.

With this plan, you can deploy the core stack and any number of independent bots on a single VPS using one command per component, with SSL termination, minimal resource usage, and clear automation paths.
