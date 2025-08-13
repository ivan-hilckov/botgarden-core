# Botgarden Core

**Production-ready infrastructure for hosting multiple Telegram bots on a single VPS**

A comprehensive, secure, and scalable foundation for running multiple Telegram bots using Docker, Nginx, and PostgreSQL. Built for simplicity, security, and zero-downtime operations.

## 🎯 Key Features

- **One-command deployment** for both infrastructure and individual bots
- **Zero-downtime updates** with rolling deployments
- **Automatic SSL management** with Let's Encrypt
- **Dynamic webhook routing** without configuration changes
- **Shared database cluster** with per-bot isolation
- **Security-first design** with container isolation and encrypted traffic
- **Production-grade monitoring** and logging capabilities

## 🏗️ Architecture

```
┌─── Internet ───┐
│                │
│   HTTPS/SSL    │
│                │
└────────────────┘
         │
    ┌────▼────┐
    │  Nginx  │  ← SSL termination, webhook routing
    │ (Port   │
    │ 80/443) │
    └────┬────┘
         │
    ┌────▼────┐
    │ Docker  │
    │ Network │  ← Internal communication
    │botgarden│
    └─┬─────┬─┘
      │     │
  ┌───▼──┐ ┌▼─────────┐
  │ Bot1 │ │PostgreSQL│
  │:8080 │ │  :5432   │
  └──────┘ └──────────┘
  ┌───▼──┐
  │ Bot2 │
  │:8080 │
  └──────┘
```

## 🚀 Quick Start

### Prerequisites

- VPS with Ubuntu 20.04+ (2GB RAM, 20GB storage minimum)
- Domain name pointing to your VPS
- SSH access to your VPS

### 1. VPS Setup

```bash
# Connect to your VPS
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

# Configure firewall
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp   # SSH
ufw allow 80/tcp   # HTTP
ufw allow 443/tcp  # HTTPS
ufw enable
```

### 2. Deploy Core Infrastructure

```bash
# Clone the repository locally
git clone https://github.com/your-username/botgarden-core.git
cd botgarden-core

# Configure environment
cp .env.example .env
# Edit .env with your domain, email, and database credentials

# Deploy to VPS
./scripts/deploy-core.sh \
  --host your-vps-ip \
  --user deploy \
  --domain your-domain.com \
  --email your-email@domain.com

# Verify deployment
curl https://your-domain.com/health
```

### 3. Deploy Your First Bot

```bash
# In your bot repository
cp .env.example .env
# Configure bot token and webhook settings

# Deploy bot
./scripts/deploy-bot.sh \
  --host your-vps-ip \
  --user deploy \
  --name hello-bot \
  --token "YOUR_BOT_TOKEN" \
  --webhook-base https://your-domain.com/webhook

# Test webhook
curl -I https://your-domain.com/webhook/hello-bot
```

## 📁 Project Structure

```
botgarden-core/
├── docker-compose.yml           # Core infrastructure
├── docker-compose.monitoring.yml # Optional monitoring stack
├── .env.example                 # Environment template
├── nginx/
│   ├── nginx.conf              # Main Nginx configuration
│   └── templates/
│       └── core.conf.template  # SSL + webhook routing
├── scripts/
│   ├── deploy-core.sh          # Core infrastructure deployment
│   ├── deploy-bot.sh           # Individual bot deployment
│   ├── backup.sh               # Database backup automation
│   └── renew-certs.sh          # SSL certificate renewal
├── certs/                      # SSL certificate storage (created)
├── logs/                       # Log files (created)
├── backups/                    # Database backups (created)
└── monitoring/                 # Optional monitoring configs
    ├── prometheus.yml
    └── loki-config.yml
```

## 🛠️ Technology Stack

| Component          | Image                | Version | Purpose                          |
| ------------------ | -------------------- | ------- | -------------------------------- |
| **Reverse Proxy**  | `nginx:1.25-alpine`  | Latest  | SSL termination, webhook routing |
| **Database**       | `postgres:16-alpine` | LTS     | Shared database cluster          |
| **SSL Management** | `certbot/certbot`    | v2.11.0 | Let's Encrypt automation         |
| **Orchestration**  | `docker-compose`     | v2.20+  | Container management             |

## 🔒 Security Features

- **Container Isolation**: All services run in isolated Docker networks
- **SSL/TLS Encryption**: Automatic HTTPS with Let's Encrypt certificates
- **Firewall Protection**: Minimal port exposure (22, 80, 443 only)
- **Non-root Containers**: All applications run as non-privileged users
- **Secret Management**: Environment-based configuration
- **Regular Updates**: Automated security patching capabilities

## 📊 Monitoring & Operations

### Health Checks

- **Infrastructure**: `https://your-domain.com/health`
- **Status API**: `https://your-domain.com/status`
- **Container Health**: Built-in Docker health checks

### Logging

- **Nginx Logs**: `logs/nginx/access.log`, `logs/nginx/error.log`
- **Container Logs**: `docker logs <container-name>`
- **Centralized Logging**: Optional Loki integration

### Backup & Recovery

```bash
# Manual backup
./scripts/backup.sh

# Restore from backup
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < backup.sql
```

## 🔧 Bot Development

### Bot Template Structure

```
your-bot/
├── Dockerfile
├── docker-compose.bot.yml
├── .env.example
├── requirements.txt
├── app/
│   ├── __main__.py
│   ├── handlers/
│   └── config.py
└── scripts/
    └── deploy-bot.sh
```

### Environment Variables

```bash
# Bot Identity
BOT_NAME=your-bot
BOT_TOKEN=YOUR_TELEGRAM_BOT_TOKEN
BOT_PORT=8080

# Webhook Configuration
WEBHOOK_BASE=https://your-domain.com/webhook
WEBHOOK_SECRET=optional_security_secret

# Database (shared with core)
POSTGRES_HOST=bg-postgres
POSTGRES_DB=botgarden
POSTGRES_USER=botgarden_admin
POSTGRES_PASSWORD=your_strong_password
```

## 📈 Scaling

### Single VPS Capacity

- **Lightweight bots**: 50+ concurrent bots
- **Medium bots**: 20-30 concurrent bots
- **Heavy bots**: 5-10 concurrent bots

### Multi-VPS Scaling

- Load balancer configuration
- Database clustering
- Shared storage solutions

## 🛡️ Best Practices

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

## 🆘 Troubleshooting

### Common Issues

**SSL Certificate Problems**

```bash
# Check certificate status
openssl s_client -connect your-domain.com:443 -servername your-domain.com

# Renew certificates manually
docker compose run --rm certbot certbot renew --webroot -w /var/www/certbot
docker compose exec nginx nginx -s reload
```

**Bot Not Receiving Webhooks**

```bash
# Check nginx logs
docker logs bg-nginx

# Test webhook URL
curl -I https://your-domain.com/webhook/bot-name

# Verify bot container is running
docker ps --filter name=bot-name
```

**Database Connection Issues**

```bash
# Check PostgreSQL status
docker logs bg-postgres

# Test database connection
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB
```

## 📚 Additional Resources

- [Detailed Implementation Plan](PLAN_CLAUDE.md)
- [Simplified Setup Guide](PLAN_GPT.md)
- [Bot Development Examples](examples/)
- [Security Guidelines](docs/security.md)
- [Monitoring Setup](docs/monitoring.md)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/your-username/botgarden-core/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-username/botgarden-core/discussions)
- **Documentation**: [Wiki](https://github.com/your-username/botgarden-core/wiki)

---

**Made with ❤️ for the Telegram bot community**
