# Botgarden Core

**Production-ready infrastructure for hosting multiple Telegram bots on a single VPS**

A comprehensive, secure, and scalable foundation for running multiple Telegram bots using Docker, Nginx, and PostgreSQL. Built for simplicity, security, and zero-downtime operations.

## Key Features

- **One-command deployment** for both infrastructure and individual bots
- **Automatic SSL management** with Let's Encrypt integration
- **Dynamic webhook routing** without configuration changes
- **Shared PostgreSQL database** with per-bot isolation
- **Security-first design** with container isolation and encrypted traffic
- **Comprehensive monitoring** with health checks and system audits
- **Simple management** with intuitive scripts for all operations

## Architecture

### System Architecture

```
┌─── Internet ───┐
│  HTTPS/SSL     │
│  Port 80/443   │
└────────────────┘
         │
    ┌────▼────────┐
    │     VPS     │
    │ Ubuntu Host │
    └─────┬───────┘
          │
    ┌─────▼─────────┐
    │ Docker Engine │
    └─────┬─────────┘
          │
    ┌─────▼─────────┐
    │   botgarden   │  ← Docker Network
    │   network     │
    └─┬─────────┬───┘
      │         │
  ┌───▼───┐ ┌──▼──────┐
  │bg-nginx│ │bg-postgres│
  │:80/443│ │  :5432   │
  └───┬───┘ └─────────┘
      │
  ┌───▼───┐ ┌─────────┐
  │ Bot1  │ │  Bot2   │
  │:8080  │ │ :8080   │
  └───────┘ └─────────┘
```

### SSL Certificate Flow

```
1. System certbot (on VPS host) → /etc/letsencrypt/
2. Copy to project → /opt/botgarden-core/certs/
3. Mount in nginx → /etc/nginx/certs/
4. Nginx serves HTTPS using mounted certificates
```

### Component Details

- **VPS Host**: Ubuntu server with Docker and system certbot
- **Docker Network**: Isolated botgarden network for internal communication
- **Nginx Container**: Handles SSL termination and webhook routing
- **PostgreSQL Container**: Shared database for all bots
- **Bot Containers**: Individual Telegram bots with webhook endpoints

## Quick Start

### Prerequisites

- VPS with Ubuntu 20.04+ (2GB RAM, 20GB storage minimum)
- Domain name pointing to your VPS
- SSH access to your VPS

### 1. Prepare Your VPS

```bash
# Clone the repository locally
git clone https://github.com/your-username/botgarden-core.git
cd botgarden-core

# Configure environment
cp env.example .env
# Edit .env with your VPS details, domain, and credentials

# Prepare VPS (installs Docker, creates directories, etc.)
./scripts/prepare-vps.sh
```

### 2. Deploy Core Infrastructure

```bash
# Deploy infrastructure with SSL certificates
./scripts/deploy-core.sh

# Or with custom options
./scripts/deploy-core.sh --domain your-domain.com --email your@email.com

# Verify deployment
curl https://your-domain.com/health
```

### 3. Deploy Your First Bot

```bash
# Create bot from template
cp -r bot-template my-awesome-bot
cd my-awesome-bot

# Configure bot
cp env.example .env
# Edit .env with your bot token

# Deploy bot
./deploy-bot.sh --name my-awesome-bot --token "YOUR_BOT_TOKEN"

# Test webhook
curl -I https://your-domain.com/webhook/my-awesome-bot
```

## Deployment Process

### Core Infrastructure Deployment

The `deploy-core.sh` script performs the following steps:

1. **VPS Preparation**: Installs Docker if not present
2. **Directory Structure**: Creates required directories (`/opt/botgarden-core/`)
3. **File Synchronization**: Uploads all project files via rsync
4. **Service Startup**: Starts nginx and PostgreSQL containers
5. **SSL Certificate Setup**:
   - Temporarily stops nginx container
   - Uses system `certbot --standalone` to obtain certificates
   - Copies certificates from `/etc/letsencrypt/` to project `./certs/`
   - Restarts containers with SSL configuration
6. **Cron Setup**: Configures automatic certificate renewal

### Bot Deployment Process

The `deploy-bot.sh` script (located in bot directory) performs:

1. **Configuration Discovery**: Finds botgarden-core `.env` file
2. **Environment Setup**: Creates/updates bot `.env` with webhook URLs
3. **Docker Compose Generation**: Creates `docker-compose.bot.yml` if missing
4. **Network Validation**: Ensures botgarden Docker network exists
5. **Container Deployment**: Builds and starts bot container
6. **Webhook Registration**: Registers webhook URL with Telegram API
7. **Health Verification**: Waits for bot to become healthy

### Static Files Deployment

The `deploy-static.sh` script provides:

1. **Change Detection**: Compares local vs remote file checksums
2. **Selective Upload**: Only uploads changed files
3. **Backup Option**: Can backup existing files before deployment
4. **Verification**: Tests web accessibility after deployment

## Project Structure

```
botgarden-core/
├── docker-compose.yml           # Simplified core infrastructure
├── env.example                  # Environment template
├── nginx/
│   ├── nginx.conf              # Main Nginx configuration
│   └── botgarden-ssl.conf.template  # SSL + webhook routing
├── scripts/
│   ├── deploy-core.sh          # Core infrastructure deployment
│   ├── deploy-bot.sh           # Individual bot deployment  
│   ├── health-check.sh         # System health monitoring
│   ├── stop-services.sh        # Service management
│   ├── vps-audit.sh           # VPS system audit
│   ├── prepare-vps.sh         # VPS preparation
│   └── renew-certs.sh         # SSL certificate renewal
├── certs/                      # SSL certificate storage (created)
├── logs/                       # Log files (created)
├── backups/                    # Database backups (created)
├── reports/                    # Audit reports (created)
└── bot-template/               # Template for new bots
    ├── Dockerfile
    ├── docker-compose.yml
    ├── env.example
    └── app/
```

## Technology Stack

| Component          | Image                | Version | Purpose                          |
| ------------------ | -------------------- | ------- | -------------------------------- |
| **Reverse Proxy**  | `nginx:1.25-alpine`  | Latest  | SSL termination, webhook routing |
| **Database**       | `postgres:16-alpine` | LTS     | Shared database cluster          |
| **SSL Management** | `certbot/certbot`    | v2.11.0 | Let's Encrypt automation         |
| **Orchestration**  | `docker-compose`     | v2.20+  | Container management             |

## Security Features

### SSL/TLS Management

The system uses a hybrid approach for SSL certificate management:

1. **Certificate Generation**: System-level `certbot` on VPS host
   - Runs `certbot certonly --standalone` to obtain certificates
   - Stores certificates in `/etc/letsencrypt/` on host
   - Requires stopping Docker nginx temporarily during initial setup

2. **Certificate Distribution**: 
   - Certificates copied from `/etc/letsencrypt/live/DOMAIN/` to `./certs/live/DOMAIN/`
   - Project certs directory mounted as volume in nginx container
   - Nginx container accesses certificates at `/etc/nginx/certs/`

3. **Automatic Renewal**:
   - Cron job runs `./scripts/renew-certs.sh` daily at 3 AM
   - Uses `sudo certbot renew` to update system certificates
   - Copies renewed certificates to Docker volume
   - Reloads nginx configuration without downtime

### Security Features

- **Container Isolation**: All services run in isolated Docker networks
- **SSL/TLS Encryption**: Automatic HTTPS with Let's Encrypt certificates
- **Firewall Protection**: Minimal port exposure (22, 80, 443 only)
- **Non-root Containers**: All applications run as non-privileged users
- **Secret Management**: Environment-based configuration
- **Certificate Security**: Proper file permissions and ownership

## Monitoring & Operations

### Health Checks

```bash
# Comprehensive system health check
./scripts/health-check.sh

# Quick status check
./scripts/health-check.sh --remote

# JSON output for monitoring systems
./scripts/health-check.sh --json
```

### System Auditing

```bash
# Generate detailed VPS audit report
./scripts/vps-audit.sh

# Quick system overview
./scripts/vps-audit.sh --quick

# Include sensitive information (ports, users)
./scripts/vps-audit.sh --include-sensitive
```

### Service Management

```bash
# Stop all services
./scripts/stop-services.sh

# Stop only core infrastructure
./scripts/stop-services.sh --core-only

# Stop only bot services
./scripts/stop-services.sh --bots-only

# Force stop with cleanup
./scripts/stop-services.sh --force --remove-orphans
```

### Static Files Deployment

```bash
# Deploy updated static files (website, landing page)
./scripts/deploy-static.sh

# Preview changes without deploying
./scripts/deploy-static.sh --dry-run

# Deploy with backup of existing files
./scripts/deploy-static.sh --backup

# Force deploy even if no changes detected
./scripts/deploy-static.sh --force
```

## Bot Development

### Creating a New Bot

```bash
# Use the bot template (recommended)
cp -r bot-template my-new-bot
cd my-new-bot

# Configure your bot
cp env.example .env
# Edit .env with your bot token and settings

# Deploy your bot
./deploy-bot.sh --name my-new-bot --token "YOUR_BOT_TOKEN"
```

### Bot Template Structure

```
your-bot/
├── deploy-bot.sh               # Bot deployment script
├── Dockerfile                  # Container definition
├── docker-compose.yml          # Bot service configuration
├── env.example                 # Environment template
├── requirements.txt            # Python dependencies
└── app/
    ├── __main__.py            # Bot entry point
    └── handlers/              # Bot handlers
```

### Environment Variables

The bot deployment script automatically configures:

- `BOT_NAME` - Unique bot identifier
- `BOT_TOKEN` - Telegram bot token
- `BOT_PORT` - Internal bot port (default: 8080)
- `WEBHOOK_URL` - Automatic webhook URL generation
- `POSTGRES_*` - Database connection (shared with core)

### Bot Management

```bash
# Deploy/update bot (from bot directory)
./deploy-bot.sh --name my-bot --token "TOKEN"

# Check bot status
ssh user@vps 'docker ps --filter name=my-bot'

# View bot logs
ssh user@vps 'docker logs my-bot -f'

# Stop bot
ssh user@vps 'cd /opt/bots/my-bot && docker compose -f docker-compose.bot.yml down'
```

## Scaling

### Single VPS Capacity

- **Lightweight bots**: 50+ concurrent bots
- **Medium bots**: 20-30 concurrent bots
- **Heavy bots**: 5-10 concurrent bots

### Multi-VPS Scaling

- Load balancer configuration
- Database clustering
- Shared storage solutions

## Best Practices

### Security

- Use strong, unique passwords (20+ characters)
- Rotate secrets regularly (quarterly)
- Keep systems updated
- Monitor access logs
- Use SSH keys, not passwords

### Operations

- Test deployments in staging first
- Monitor resource usage
- Set up alerting for critical issues
- Maintain regular backups
- Document custom configurations

### Development

- Use environment parity
- Implement health checks
- Structure logs properly
- Handle graceful shutdowns
- Test webhook endpoints

## Troubleshooting

### Diagnostic Commands

```bash
# Comprehensive health check
./scripts/health-check.sh --verbose

# System audit with detailed report
./scripts/vps-audit.sh --include-sensitive

# Check specific issues
curl -I https://your-domain.com/health
```

### Common Issues

**SSL Certificate Problems**

```bash
# Check certificate status and renewal
./scripts/health-check.sh --remote

# Manual certificate renewal
ssh user@vps 'sudo certbot renew --dry-run'

# Restart nginx after certificate update
ssh user@vps 'cd /opt/botgarden-core && docker compose restart nginx'
```

**Bot Not Receiving Webhooks**

```bash
# Test webhook endpoint
curl -I https://your-domain.com/webhook/your-bot-name

# Check bot container status
ssh user@vps 'docker ps --filter name=your-bot-name'

# View bot logs
ssh user@vps 'docker logs your-bot-name --tail 50'

# Check nginx routing logs
ssh user@vps 'cd /opt/botgarden-core && docker compose logs nginx | grep webhook'
```

**Database Connection Issues**

```bash
# Check database status
./scripts/health-check.sh --remote

# Test database connection
ssh user@vps 'cd /opt/botgarden-core && docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "SELECT version();"'

# View database logs
ssh user@vps 'cd /opt/botgarden-core && docker compose logs postgres'
```

### Emergency Procedures

```bash
# Stop all services
./scripts/stop-services.sh --force

# Restart core infrastructure
./scripts/deploy-core.sh --force

# Generate emergency audit report
./scripts/vps-audit.sh --output emergency_audit.md
```

## Additional Resources

- [Detailed Implementation Plan](PLAN_CLAUDE.md) - Complete infrastructure design and implementation guide
- [Bot Template](bot-template/) - Ready-to-use bot template with best practices
- [Scripts Documentation](scripts/) - Detailed documentation for all management scripts

## Script Reference

### Core Management (from botgarden-core directory)
- `./scripts/deploy-core.sh` - Deploy core infrastructure with SSL
- `./scripts/prepare-vps.sh` - Prepare VPS with Docker and dependencies  
- `./scripts/health-check.sh` - Comprehensive system health monitoring
- `./scripts/stop-services.sh` - Stop services with various options
- `./scripts/deploy-static.sh` - Deploy static web files quickly
- `./scripts/vps-audit.sh` - Generate detailed VPS audit reports

### Bot Management (from bot directory)
- `./deploy-bot.sh` - Deploy individual bot to infrastructure

### Maintenance
- `./scripts/renew-certs.sh` - SSL certificate renewal (automated via cron)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/your-username/botgarden-core/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-username/botgarden-core/discussions)
- **Documentation**: [Wiki](https://github.com/your-username/botgarden-core/wiki)

---

**Made with ❤️ for the Telegram bot community**
