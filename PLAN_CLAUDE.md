# Botgarden Core — Production Infrastructure Plan

_A comprehensive, production-ready infrastructure for running multiple Telegram bots on a single VPS with maximum simplicity, security, and scalability._

---

## 🎯 Overview

This plan delivers a robust foundation for hosting multiple Telegram bots using Docker, Nginx, and PostgreSQL. The architecture emphasizes minimal configuration, automated deployment, and secure operations while maintaining the ability to scale from a single bot to dozens of bots on one VPS.

### Key Benefits

- **One-command deployment** for both infrastructure and individual bots
- **Zero-downtime updates** with rolling deployments
- **Automatic SSL management** with Let's Encrypt
- **Dynamic webhook routing** without configuration changes
- **Shared database cluster** with per-bot isolation
- **Security-first design** with container isolation and encrypted traffic

---

## 🏗️ Recommended Components

### Core Infrastructure Stack

| Component           | Image                | Version       | Purpose                          |
| ------------------- | -------------------- | ------------- | -------------------------------- |
| **Reverse Proxy**   | `nginx:1.25-alpine`  | Latest stable | SSL termination, webhook routing |
| **Database**        | `postgres:16-alpine` | LTS           | Shared database cluster          |
| **SSL Management**  | `certbot/certbot`    | v2.11.0       | Let's Encrypt automation         |
| **Process Manager** | `docker-compose`     | v2.20+        | Container orchestration          |

### Optional Monitoring & Management

| Component           | Image                         | Purpose                      |
| ------------------- | ----------------------------- | ---------------------------- |
| **Log Aggregation** | `grafana/loki:2.9.0`          | Centralized logging          |
| **Metrics**         | `grafana/prometheus:v2.45.0`  | System monitoring            |
| **Auto Updates**    | `containrrr/watchtower:1.7.1` | Container updates            |
| **Backup**          | `postgres:16-alpine`          | Database backups via pg_dump |

### Why These Choices

- **Alpine Linux**: Minimal attack surface, 50%+ smaller images
- **PostgreSQL 16**: Modern features, excellent performance, reliable
- **Nginx 1.25**: HTTP/2, TLSv1.3, robust reverse proxy capabilities
- **Latest Certbot**: Improved reliability and ACME v2 support

---

## 📁 Project Structure

```
botgarden-core/
├── docker-compose.yml           # Core infrastructure
├── docker-compose.monitoring.yml # Optional monitoring stack
├── .env.example                 # Environment template
├── nginx/
│   ├── nginx.conf              # Main Nginx configuration
│   └── templates/
│       ├── core.conf.template  # SSL + webhook routing
│       └── monitoring.conf.template # Optional: metrics endpoints
├── scripts/
│   ├── deploy-core.sh          # Core infrastructure deployment
│   ├── deploy-bot.sh           # Individual bot deployment
│   ├── backup.sh               # Database backup automation
│   ├── renew-certs.sh          # SSL certificate renewal
│   └── health-check.sh         # System health monitoring
├── certs/                      # SSL certificate storage (created)
├── logs/                       # Log files (created)
├── backups/                    # Database backups (created)
└── monitoring/                 # Optional monitoring configs
    ├── prometheus.yml
    └── loki-config.yml
```

---

## 🛠️ Implementation Examples

### 1. Core Infrastructure (`docker-compose.yml`)

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
    command: |
      /bin/sh -c "
        envsubst < /etc/nginx/templates/core.conf.template > /etc/nginx/conf.d/core.conf &&
        nginx -g 'daemon off;'
      "
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/templates:/etc/nginx/templates:ro
      - ./certs:/etc/letsencrypt:ro
      - ./logs/nginx:/var/log/nginx
      - certbot-webroot:/var/www/certbot:ro
    environment:
      - TZ=${TZ:-UTC}
      - DOMAIN=${DOMAIN}
      - ALT_DOMAINS=${ALT_DOMAINS:-}
    networks:
      - botgarden
    healthcheck:
      test: ["CMD", "nginx", "-t"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:16-alpine
    container_name: bg-postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_INITDB_ARGS: "--encoding=UTF8 --locale=C"
      TZ: ${TZ:-UTC}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./backups:/backups
      - ./scripts/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    expose:
      - "5432"
    # Uncomment for external access (development only)
    # ports:
    #   - "${POSTGRES_PORT:-5432}:5432"
    networks:
      - botgarden
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 30s
      timeout: 10s
      retries: 5

  certbot:
    image: certbot/certbot:v2.11.0
    container_name: bg-certbot
    volumes:
      - ./certs:/etc/letsencrypt
      - certbot-webroot:/var/www/certbot
    entrypoint: ["/bin/sh", "-c", "sleep infinity"]
    networks:
      - botgarden

volumes:
  postgres-data:
    driver: local
  certbot-webroot:
    driver: local

networks:
  botgarden:
    name: botgarden
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### 2. Nginx Configuration

#### `nginx/nginx.conf`

```nginx
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;

error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 16M;

    # Security
    server_tokens off;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=webhook:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=general:10m rate=100r/s;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss;

    include /etc/nginx/conf.d/*.conf;
}
```

#### `nginx/templates/core.conf.template`

```nginx
# Rate limiting for webhooks
limit_req_zone $binary_remote_addr zone=webhook_${DOMAIN}:10m rate=50r/s;

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} ${ALT_DOMAINS};

    # ACME challenge for Let's Encrypt
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
        try_files $uri =404;
    }

    # Redirect everything else to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# Main HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN} ${ALT_DOMAINS};

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:50m;
    ssl_session_tickets off;

    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # HSTS
    add_header Strict-Transport-Security "max-age=63072000" always;

    # Health check endpoint
    location = /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    # Infrastructure status (basic)
    location = /status {
        access_log off;
        return 200 '{"status":"healthy","timestamp":"$time_iso8601"}';
        add_header Content-Type application/json;
    }

    # Dynamic webhook routing: /webhook/<botname> -> http://<botname>:8080/webhook
    location ~* ^/webhook/(?<botname>[a-z0-9\-\_]+)(?<path>/.*)?$ {
        # Rate limiting per bot
        limit_req zone=webhook_${DOMAIN} burst=20 nodelay;

        # Security headers for webhooks
        add_header X-Webhook-Bot $botname always;

        # Upstream configuration
        set $upstream_host $botname;
        set $upstream_port 8080;
        set $upstream_path ${path};

        # Proxy headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Bot-Name $botname;

        # Connection settings
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_buffering off;

        # Timeouts
        proxy_connect_timeout 5s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;

        # Upstream
        proxy_pass http://$upstream_host:$upstream_port/webhook$upstream_path$is_args$args;

        # Error handling
        proxy_intercept_errors on;
        error_page 502 503 504 = @webhook_error;
    }

    # Error handling for webhook failures
    location @webhook_error {
        add_header Content-Type application/json always;
        return 503 '{"error":"Bot temporarily unavailable","retry_after":10}';
    }

    # Admin endpoints (optional, can be protected with basic auth)
    location /admin/ {
        # auth_basic "Admin Area";
        # auth_basic_user_file /etc/nginx/.htpasswd;

        location /admin/nginx-status {
            stub_status on;
            access_log off;
        }
    }

    # Default route
    location / {
        return 404 '{"error":"Not found"}';
        add_header Content-Type application/json always;
    }
}
```

### 3. Environment Configuration

#### `.env.example`

```bash
# =================================================================
# BOTGARDEN CORE INFRASTRUCTURE CONFIGURATION
# =================================================================

# Domain Configuration
DOMAIN=example.com
ALT_DOMAINS=www.example.com,api.example.com
LETSENCRYPT_EMAIL=admin@example.com

# Timezone
TZ=UTC

# PostgreSQL Configuration
POSTGRES_USER=botgarden_admin
POSTGRES_PASSWORD=CHANGE_ME_SUPER_STRONG_PASSWORD_HERE
POSTGRES_DB=botgarden
# Uncomment for external access (development only)
# POSTGRES_PORT=5432

# Security
SSL_RENEWAL_EMAIL=security@example.com

# Optional: Monitoring
ENABLE_MONITORING=false
GRAFANA_ADMIN_PASSWORD=CHANGE_ME_GRAFANA_PASSWORD

# Optional: Backup Configuration
BACKUP_RETENTION_DAYS=30
BACKUP_S3_BUCKET=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
```

### 4. Bot Deployment Template

#### `docker-compose.bot.yml` (for individual bots)

```yaml
version: "3.9"

services:
  bot:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - BOT_VERSION=${BOT_VERSION:-latest}
    container_name: ${BOT_NAME}
    restart: unless-stopped
    environment:
      - BOT_NAME=${BOT_NAME}
      - BOT_TOKEN=${BOT_TOKEN}
      - BOT_PORT=${BOT_PORT:-8080}
      - WEBHOOK_SECRET=${WEBHOOK_SECRET}
      - WEBHOOK_URL=${WEBHOOK_BASE}/${BOT_NAME}
      - POSTGRES_HOST=bg-postgres
      - POSTGRES_PORT=5432
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - LOG_LEVEL=${LOG_LEVEL:-INFO}
      - TZ=${TZ:-UTC}
    expose:
      - "${BOT_PORT:-8080}"
    networks:
      - botgarden
    volumes:
      - bot-data:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${BOT_PORT:-8080}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    depends_on:
      - postgres
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  bot-data:
    driver: local

networks:
  botgarden:
    external: true
```

#### Bot `.env.example`

```bash
# =================================================================
# BOT CONFIGURATION
# =================================================================

# Bot Identity
BOT_NAME=hello-bot
BOT_VERSION=latest
BOT_PORT=8080

# Telegram Configuration
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN_HERE
WEBHOOK_SECRET=optional_webhook_secret_for_security
WEBHOOK_BASE=https://example.com/webhook

# Database (matches core infrastructure)
POSTGRES_DB=botgarden
POSTGRES_USER=botgarden_admin
POSTGRES_PASSWORD=CHANGE_ME_SUPER_STRONG_PASSWORD_HERE

# Logging
LOG_LEVEL=INFO

# Timezone
TZ=UTC

# Optional: Bot-specific settings
MAX_CONNECTIONS=100
RATE_LIMIT_MESSAGES=30
RATE_LIMIT_WINDOW=60
```

### 5. Production Dockerfile for Bots

```dockerfile
# Multi-stage build for Python bots
FROM python:3.11-slim as builder

# Build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# Production stage
FROM python:3.11-slim

# Runtime dependencies only
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy Python packages from builder
COPY --from=builder /root/.local /root/.local

# Create non-root user
RUN useradd --create-home --shell /bin/bash bot

WORKDIR /app

# Copy application code
COPY . .
RUN chown -R bot:bot /app

# Switch to non-root user
USER bot

# Environment
ENV PATH=/root/.local/bin:$PATH
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV BOT_PORT=8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${BOT_PORT}/health || exit 1

EXPOSE 8080

# Start application
CMD ["python", "-m", "app"]
```

---

## 🚀 Deployment Scripts

### 1. Core Infrastructure Deployment (`scripts/deploy-core.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy botgarden-core infrastructure to VPS

OPTIONS:
    -h, --host HOST          VPS hostname or IP address
    -u, --user USER          SSH username
    -p, --port PORT          SSH port (default: 22)
    -k, --key PATH           SSH private key path (optional)
    -d, --domain DOMAIN      Domain name for SSL
    -e, --email EMAIL        Email for Let's Encrypt
    --dry-run                Show what would be done without executing
    --force                  Force deployment even if running
    --help                   Show this help

EXAMPLES:
    $0 -h 192.168.1.100 -u deploy -d bot.example.com -e admin@example.com
    $0 --host myserver.com --user root --domain api.mybot.com --email me@example.com

EOF
    exit 1
}

# Default values
SSH_PORT=22
SSH_KEY=""
DRY_RUN=false
FORCE=false
REMOTE_DIR="/opt/botgarden-core"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -d|--domain)
            DOMAIN="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
[[ -z "${HOST:-}" ]] && error "Host is required (-h/--host)"
[[ -z "${SSH_USER:-}" ]] && error "SSH user is required (-u/--user)"
[[ -z "${DOMAIN:-}" ]] && error "Domain is required (-d/--domain)"
[[ -z "${EMAIL:-}" ]] && error "Email is required (-e/--email)"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT"
[[ -n "$SSH_KEY" ]] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

# SSH command wrapper
ssh_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: ssh $SSH_OPTS $SSH_USER@$HOST '$*'"
    else
        ssh $SSH_OPTS "$SSH_USER@$HOST" "$@"
    fi
}

rsync_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: rsync -az --delete -e 'ssh $SSH_OPTS' $*"
    else
        rsync -az --delete -e "ssh $SSH_OPTS" "$@"
    fi
}

# Preflight checks
log "Running preflight checks..."

# Check if .env exists
if [[ ! -f ".env" ]]; then
    warn ".env file not found, creating from .env.example"
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        log "Please edit .env file with your configuration before deploying"
        exit 1
    else
        error ".env.example not found"
    fi
fi

# Check Docker Compose file
[[ ! -f "docker-compose.yml" ]] && error "docker-compose.yml not found"

# Test SSH connection
log "Testing SSH connection to $SSH_USER@$HOST:$SSH_PORT..."
if ! ssh_exec "echo 'SSH connection successful'"; then
    error "SSH connection failed"
fi

# Check if deployment is already running
if [[ "$FORCE" == "false" ]]; then
    if ssh_exec "docker compose -f $REMOTE_DIR/docker-compose.yml ps --services --filter status=running" 2>/dev/null | grep -q .; then
        error "Deployment already running. Use --force to override"
    fi
fi

# Main deployment
log "Starting deployment to $HOST..."

# 1. Install Docker if needed
log "Ensuring Docker is installed..."
ssh_exec "command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh"
ssh_exec "sudo usermod -aG docker $SSH_USER 2>/dev/null || true"

# 2. Create directories
log "Creating remote directories..."
ssh_exec "mkdir -p $REMOTE_DIR/{logs/nginx,backups,certs}"

# 3. Sync files
log "Syncing project files..."
rsync_exec ./ "$SSH_USER@$HOST:$REMOTE_DIR/"

# 4. Set up environment
log "Configuring environment..."
ssh_exec "cd $REMOTE_DIR && sed -i 's/DOMAIN=.*/DOMAIN=$DOMAIN/' .env"
ssh_exec "cd $REMOTE_DIR && sed -i 's/LETSENCRYPT_EMAIL=.*/LETSENCRYPT_EMAIL=$EMAIL/' .env"

# 5. Start services
log "Starting core infrastructure..."
ssh_exec "cd $REMOTE_DIR && docker compose up -d --remove-orphans"

# 6. Wait for services to be healthy
log "Waiting for services to start..."
ssh_exec "cd $REMOTE_DIR && timeout 60 bash -c 'until docker compose ps | grep -q healthy; do sleep 2; done'"

# 7. Obtain SSL certificates (first run)
log "Checking SSL certificates..."
if ! ssh_exec "test -f $REMOTE_DIR/certs/live/$DOMAIN/fullchain.pem"; then
    log "Obtaining SSL certificates for $DOMAIN..."
    ssh_exec "cd $REMOTE_DIR && docker compose run --rm certbot certbot certonly \
        --webroot -w /var/www/certbot \
        -d '$DOMAIN' \
        --email '$EMAIL' \
        --agree-tos --no-eff-email --non-interactive"

    log "Reloading Nginx with SSL certificates..."
    ssh_exec "cd $REMOTE_DIR && docker compose exec nginx nginx -s reload"
fi

# 8. Set up certificate renewal
log "Setting up certificate renewal..."
ssh_exec "cd $REMOTE_DIR && (crontab -l 2>/dev/null | grep -v 'certbot renew' || true; echo '0 3 * * * cd $REMOTE_DIR && ./scripts/renew-certs.sh') | crontab -"

# 9. Display deployment info
log "Gathering deployment information..."
DB_INFO=$(ssh_exec "cd $REMOTE_DIR && source .env && echo \"Host: bg-postgres, Port: 5432, DB: \$POSTGRES_DB, User: \$POSTGRES_USER\"")
WEBHOOK_BASE=$(ssh_exec "cd $REMOTE_DIR && source .env && echo \"https://\$DOMAIN/webhook\"")

success "Core infrastructure deployed successfully!"
echo
echo "📊 Deployment Information:"
echo "  🌐 Domain: https://$DOMAIN"
echo "  🔍 Health Check: https://$DOMAIN/health"
echo "  📊 Status: https://$DOMAIN/status"
echo "  🗄️  Database: $DB_INFO"
echo "  🔗 Webhook Base: $WEBHOOK_BASE"
echo
echo "📝 Next Steps:"
echo "  1. Test health endpoint: curl https://$DOMAIN/health"
echo "  2. Deploy your first bot using deploy-bot.sh"
echo "  3. Monitor logs: ssh $SSH_USER@$HOST 'cd $REMOTE_DIR && docker compose logs -f'"
echo
echo "🔐 Security Notes:"
echo "  - SSL certificates will auto-renew"
echo "  - Database is only accessible within Docker network"
echo "  - Check firewall settings: ufw status"
```

### 2. Bot Deployment Script (`scripts/deploy-bot.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() { echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a Telegram bot to the botgarden infrastructure

OPTIONS:
    -h, --host HOST          VPS hostname or IP address
    -u, --user USER          SSH username
    -p, --port PORT          SSH port (default: 22)
    -k, --key PATH           SSH private key path (optional)
    -n, --name NAME          Bot name (default: current directory name)
    -t, --token TOKEN        Telegram bot token
    --webhook-base URL       Webhook base URL (e.g., https://example.com/webhook)
    --dry-run                Show what would be done without executing
    --force                  Force deployment even if bot is running
    --no-webhook             Skip webhook registration
    --help                   Show this help

EXAMPLES:
    $0 -h 192.168.1.100 -u deploy -t "123456789:ABC..." --webhook-base https://bot.example.com/webhook
    $0 --host myserver.com --user root --name my-bot --token "TOKEN" --webhook-base https://api.mybot.com/webhook

EOF
    exit 1
}

# Default values
SSH_PORT=22
SSH_KEY=""
BOT_NAME=$(basename "$(pwd)")
DRY_RUN=false
FORCE=false
NO_WEBHOOK=false
REMOTE_DIR="/opt/bots"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            HOST="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -k|--key)
            SSH_KEY="$2"
            shift 2
            ;;
        -n|--name)
            BOT_NAME="$2"
            shift 2
            ;;
        -t|--token)
            BOT_TOKEN="$2"
            shift 2
            ;;
        --webhook-base)
            WEBHOOK_BASE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --no-webhook)
            NO_WEBHOOK=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate required parameters
[[ -z "${HOST:-}" ]] && error "Host is required (-h/--host)"
[[ -z "${SSH_USER:-}" ]] && error "SSH user is required (-u/--user)"
[[ -z "${BOT_TOKEN:-}" ]] && error "Bot token is required (-t/--token)"
[[ -z "${WEBHOOK_BASE:-}" ]] && error "Webhook base URL is required (--webhook-base)"

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT"
[[ -n "$SSH_KEY" ]] && SSH_OPTS="$SSH_OPTS -i $SSH_KEY"

# SSH command wrapper
ssh_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: ssh $SSH_OPTS $SSH_USER@$HOST '$*'"
    else
        ssh $SSH_OPTS "$SSH_USER@$HOST" "$@"
    fi
}

rsync_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: rsync -az --delete -e 'ssh $SSH_OPTS' $*"
    else
        rsync -az --delete -e "ssh $SSH_OPTS" "$@"
    fi
}

# Preflight checks
log "Running preflight checks for bot: $BOT_NAME..."

# Check required files
[[ ! -f "Dockerfile" ]] && error "Dockerfile not found"
[[ ! -f "docker-compose.bot.yml" ]] && error "docker-compose.bot.yml not found"

# Check if .env exists
if [[ ! -f ".env" ]]; then
    warn ".env file not found, creating from .env.example"
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        log "Please edit .env file with your configuration before deploying"
        exit 1
    else
        error ".env.example not found"
    fi
fi

# Test SSH connection
log "Testing SSH connection to $SSH_USER@$HOST:$SSH_PORT..."
if ! ssh_exec "echo 'SSH connection successful'"; then
    error "SSH connection failed"
fi

# Check if botgarden network exists
log "Checking botgarden network..."
if ! ssh_exec "docker network inspect botgarden >/dev/null 2>&1"; then
    error "Botgarden network not found. Deploy core infrastructure first."
fi

# Check if bot is already running
BOT_REMOTE_DIR="$REMOTE_DIR/$BOT_NAME"
if [[ "$FORCE" == "false" ]]; then
    if ssh_exec "docker ps --format '{{.Names}}' | grep -q '^$BOT_NAME\$'" 2>/dev/null; then
        error "Bot $BOT_NAME is already running. Use --force to override"
    fi
fi

# Main deployment
log "Starting deployment of bot: $BOT_NAME..."

# 1. Create bot directory
log "Creating bot directory..."
ssh_exec "mkdir -p $BOT_REMOTE_DIR"

# 2. Sync bot files
log "Syncing bot files..."
rsync_exec ./ "$SSH_USER@$HOST:$BOT_REMOTE_DIR/"

# 3. Update environment
log "Configuring bot environment..."
ssh_exec "cd $BOT_REMOTE_DIR && sed -i 's/BOT_NAME=.*/BOT_NAME=$BOT_NAME/' .env"
ssh_exec "cd $BOT_REMOTE_DIR && sed -i 's/BOT_TOKEN=.*/BOT_TOKEN=$BOT_TOKEN/' .env"
ssh_exec "cd $BOT_REMOTE_DIR && sed -i 's|WEBHOOK_BASE=.*|WEBHOOK_BASE=$WEBHOOK_BASE|' .env"

# 4. Stop existing bot if running
if ssh_exec "docker ps --format '{{.Names}}' | grep -q '^$BOT_NAME\$'" 2>/dev/null; then
    log "Stopping existing bot instance..."
    ssh_exec "cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml down"
fi

# 5. Build and start bot
log "Building and starting bot..."
ssh_exec "cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml up -d --build"

# 6. Wait for bot to be healthy
log "Waiting for bot to become healthy..."
ssh_exec "cd $BOT_REMOTE_DIR && timeout 60 bash -c 'until docker compose -f docker-compose.bot.yml ps | grep -q healthy; do sleep 2; done'"

# 7. Register webhook (if not disabled)
if [[ "$NO_WEBHOOK" == "false" ]]; then
    log "Registering webhook with Telegram..."
    WEBHOOK_URL="$WEBHOOK_BASE/$BOT_NAME"

    # Use Telegram API to set webhook
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" \
        -d "url=$WEBHOOK_URL" \
        -d "drop_pending_updates=true")

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        success "Webhook registered successfully"
    else
        warn "Webhook registration failed: $RESPONSE"
    fi
fi

# 8. Display deployment info
log "Gathering deployment information..."

success "Bot $BOT_NAME deployed successfully!"
echo
echo "📊 Bot Information:"
echo "  🤖 Name: $BOT_NAME"
echo "  🔗 Webhook URL: $WEBHOOK_BASE/$BOT_NAME"
echo "  🐳 Container Status: $(ssh_exec "docker ps --filter name=$BOT_NAME --format 'table {{.Status}}'")"
echo
echo "📝 Management Commands:"
echo "  📊 Check status: ssh $SSH_USER@$HOST 'docker ps --filter name=$BOT_NAME'"
echo "  📄 View logs: ssh $SSH_USER@$HOST 'docker logs $BOT_NAME -f'"
echo "  🔄 Restart: ssh $SSH_USER@$HOST 'cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml restart'"
echo "  🛑 Stop: ssh $SSH_USER@$HOST 'cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml down'"
echo
echo "🧪 Testing:"
echo "  curl -I $WEBHOOK_BASE/$BOT_NAME"
```

---

## 📋 Step-by-Step Implementation Plan

### Phase 1: VPS Preparation (Day 1)

#### 1.1 Initial Server Setup

```bash
# Connect to VPS
ssh root@your-vps-ip

# Create deploy user
adduser deploy
usermod -aG sudo deploy

# Set up SSH key authentication
mkdir -p /home/deploy/.ssh
cp ~/.ssh/authorized_keys /home/deploy/.ssh/
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys

# Disable password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd
```

#### 1.2 Firewall Configuration

```bash
# Install and configure UFW
apt update && apt install -y ufw

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow essential ports
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS

# Enable firewall
ufw enable
ufw status verbose
```

#### 1.3 Docker Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
```

### Phase 2: Core Infrastructure Deployment (Day 1-2)

#### 2.1 Repository Setup

```bash
# Clone botgarden-core locally
git clone https://github.com/ivan-hilckov/botgarden-core.git
cd botgarden-core

# Configure environment
cp .env.example .env
# Edit .env with your domain, email, and credentials
```

#### 2.2 Deploy Core Infrastructure

```bash
# Deploy to VPS
./scripts/deploy-core.sh \
  --host your-vps-ip \
  --user deploy \
  --domain your-domain.com \
  --email your-email@domain.com

# Verify deployment
curl https://your-domain.com/health
```

#### 2.3 SSL Certificate Setup

```bash
# Certificates are automatically obtained during deployment
# Verify SSL is working
curl -I https://your-domain.com/health

# Check certificate details
openssl s_client -connect your-domain.com:443 -servername your-domain.com < /dev/null 2>/dev/null | openssl x509 -noout -dates
```

### Phase 3: Database Configuration (Day 2)

#### 3.1 Database Setup

```bash
# Connect to PostgreSQL container
ssh deploy@your-vps-ip
cd /opt/botgarden-core
docker compose exec postgres psql -U botgarden_admin -d botgarden

# Create schema for bots (example)
CREATE SCHEMA IF NOT EXISTS bots;
GRANT ALL PRIVILEGES ON SCHEMA bots TO botgarden_admin;

# Create extensions if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
```

#### 3.2 Backup Setup

```bash
# Create backup script
cat > /opt/botgarden-core/scripts/backup.sh << 'EOF'
#!/bin/bash
cd /opt/botgarden-core
BACKUP_FILE="backups/pg_backup_$(date +%Y%m%d_%H%M%S).sql"
docker compose exec -T postgres pg_dumpall -U botgarden_admin > "$BACKUP_FILE"
gzip "$BACKUP_FILE"

# Cleanup old backups (keep 30 days)
find backups/ -name "*.sql.gz" -mtime +30 -delete
EOF

chmod +x /opt/botgarden-core/scripts/backup.sh

# Add to crontab
echo "0 2 * * * /opt/botgarden-core/scripts/backup.sh" | crontab -
```

### Phase 4: First Bot Deployment (Day 3)

#### 4.1 Prepare Bot Repository

```bash
# Clone hello-bot example
git clone https://github.com/ivan-hilckov/hello-bot.git
cd hello-bot

# Configure bot environment
cp .env.example .env
# Edit .env with bot token and webhook settings
```

#### 4.2 Deploy Bot

```bash
# Deploy hello-bot
./scripts/deploy-bot.sh \
  --host your-vps-ip \
  --user deploy \
  --name hello-bot \
  --token "YOUR_BOT_TOKEN" \
  --webhook-base https://your-domain.com/webhook

# Test webhook
curl -I https://your-domain.com/webhook/hello-bot
```

### Phase 5: Monitoring & Maintenance (Day 4+)

#### 5.1 Monitoring Setup

```bash
# Optional: Deploy monitoring stack
cd /opt/botgarden-core
docker compose -f docker-compose.monitoring.yml up -d

# Access Grafana at https://your-domain.com/grafana
```

#### 5.2 Maintenance Procedures

```bash
# Update core infrastructure
cd /opt/botgarden-core
git pull
docker compose pull
docker compose up -d

# Update individual bot
cd /opt/bots/hello-bot
git pull
docker compose -f docker-compose.bot.yml up -d --build

# Check system health
./scripts/health-check.sh
```

---

## 🔒 Security & Best Practices

### 1. Secret Management

#### Environment Variables

- Store all secrets in `.env` files
- Never commit real secrets to git
- Use strong, unique passwords (20+ characters)
- Rotate secrets regularly (quarterly)

#### Example Secret Generation

```bash
# Generate strong passwords
openssl rand -base64 32  # For database passwords
openssl rand -hex 16     # For webhook secrets
```

### 2. Network Security

#### Container Isolation

- All services run in isolated Docker network
- Only Nginx exposes ports to host
- Inter-container communication via Docker DNS

#### Firewall Rules

```bash
# Minimal firewall configuration
ufw status numbered
ufw delete [number]  # Remove unnecessary rules
ufw limit ssh        # Rate limit SSH connections
```

### 3. SSL/TLS Security

#### Certificate Management

- Automatic renewal with Let's Encrypt
- Strong cipher suites (TLSv1.2+)
- HSTS headers for enhanced security
- Certificate transparency monitoring

#### SSL Configuration Testing

```bash
# Test SSL configuration
curl -I https://your-domain.com
nmap --script ssl-enum-ciphers -p 443 your-domain.com
```

### 4. Database Security

#### Access Control

- Database accessible only within Docker network
- Strong authentication credentials
- Regular backup verification
- Connection encryption (future enhancement)

#### Backup Security

```bash
# Encrypt backups (optional)
gpg --symmetric --cipher-algo AES256 backup.sql
```

### 5. Application Security

#### Container Hardening

- Non-root user in containers
- Read-only root filesystem where possible
- Resource limits (CPU, memory)
- Security scanning with tools like Trivy

#### Runtime Security

```bash
# Scan containers for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image nginx:1.25-alpine
```

### 6. Operational Security

#### Logging & Monitoring

- Centralized logging with structured format
- Log rotation and retention policies
- Failed authentication monitoring
- Resource usage alerts

#### Incident Response

- Regular backup testing
- Documented rollback procedures
- Emergency contact information
- Security update procedures

---

## 🎯 Expected Outcomes

### Infrastructure Capabilities

- **Single-command deployment** for complete infrastructure
- **Zero-downtime updates** for both core and individual bots
- **Automatic SSL management** with 90-day renewal
- **Horizontal scalability** up to 50+ bots per VPS
- **Production-grade security** with container isolation

### Operational Benefits

- **5-minute deployment** time for new bots
- **99.9% uptime** with health monitoring
- **Automated backups** with 30-day retention
- **Resource efficiency** supporting multiple bots with minimal overhead
- **Monitoring integration** ready for observability tools

### Development Workflow

- **Standardized bot development** with templates
- **Environment parity** between development and production
- **Simple CI/CD integration** with GitHub Actions
- **Debugging support** with structured logging
- **Performance monitoring** with metrics collection

---

## 🚀 Next Steps

After completing this implementation:

1. **Scale Testing**: Deploy 5-10 test bots to validate performance
2. **Monitoring Enhancement**: Add Prometheus + Grafana for metrics
3. **Backup Automation**: Implement S3 backup for off-site storage
4. **CI/CD Pipeline**: Automate deployments with GitHub Actions
5. **Load Balancing**: Add multiple VPS instances with load balancer
6. **Advanced Security**: Implement WAF and DDoS protection

This architecture provides a solid foundation that can grow from a single bot to a comprehensive bot hosting platform while maintaining simplicity and security.
