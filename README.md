# Botgarden Core

**Infrastructure for hosting multiple Telegram bots on a single VPS**

Deploy and manage Telegram bots using Docker, Nginx, PostgreSQL with automatic SSL certificates.

## Quick Start

### 1. Setup Infrastructure

```bash
# Configure environment
cp env.example .env
# Edit .env with your VPS details and domain

# Deploy core infrastructure  
./scripts/deploy-core.sh
```

### 2. Deploy Static Website

```bash
# Deploy landing page
./scripts/deploy-static.sh
```

### 3. Deploy Your First Bot

```bash
# Copy bot template
cp -r bot-template my-bot
cd my-bot

# Configure bot
cp env.example .env
# Edit .env with your BOT_TOKEN

# Deploy bot
./deploy-bot.sh
```

## Configuration

### Core (.env)
```bash
DOMAIN=your-domain.com
LETSENCRYPT_EMAIL=admin@your-domain.com
VPS_HOST=your-vps-ip
VPS_USER=your-ssh-user
POSTGRES_USER=db_user
POSTGRES_PASSWORD=strong_password
POSTGRES_DB=botgarden_db
```

### Bot (.env in bot directory)
```bash
BOT_NAME=my-bot
BOT_TOKEN=123456789:ABC-DEF...
BOT_PORT=8080
WEBHOOK_SECRET=optional_secret
```

## Architecture

```
Internet (HTTPS) → Nginx → Bot Containers
                     ↓
                PostgreSQL (shared database)
```

### Components

- **Nginx**: SSL termination, webhook routing (`/webhook/botname` → `botname:8080`)
- **PostgreSQL**: Shared database for all bots
- **Bot Containers**: Individual aiogram-based bots

## Scripts

### Core Management
- `./scripts/deploy-core.sh` - Deploy infrastructure (Nginx + PostgreSQL + SSL)
- `./scripts/deploy-static.sh` - Deploy static website files

### Bot Management  
- `./deploy-bot.sh` - Deploy bot (run from bot directory)

All scripts use `.env` configuration only - no CLI parameters.

## Bot Template

Pre-configured aiogram 3.10 template with:
- Webhook setup with health checks
- PostgreSQL integration ready
- Docker containerization
- Automatic SSL webhook URLs

## SSL Certificates

- Managed by system-level certbot on VPS host
- Automatically copied to Docker containers
- Auto-renewal via cron job
- Zero-downtime certificate updates

## File Structure

```
botgarden-core/
├── docker-compose.yml      # Core infrastructure
├── env.example            # Configuration template
├── nginx/                 # Nginx configuration
├── scripts/               # Deployment scripts
├── static/                # Website files
└── bot-template/          # Bot template
    ├── Dockerfile
    ├── docker-compose.yml
    ├── deploy-bot.sh
    ├── env.example
    └── app/__main__.py
```

## License

MIT License - see [LICENSE](LICENSE) file.