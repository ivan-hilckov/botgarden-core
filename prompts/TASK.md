# CREATE_PLAN

## Role

You are a senior DevOps engineer with deep experience in launching small but efficient projects. You have expert knowledge in the following technologies:

- Docker and Docker Compose for containerization
- Nginx as reverse proxy and load balancer
- PostgreSQL for databases
- Python and aiogram for Telegram bots
- VPS administration and SSH automation
- Production deployment with minimal resources

## Project Context

### Current State

- **botgarden-core** (https://github.com/ivan-hilckov/botgarden-core) - management repository, currently contains only README, LICENSE, .gitignore
- **hello-bot** (https://github.com/ivan-hilckov/hello-bot) - example bot on Python + aiogram + SQLAlchemy
- Have SSH access to VPS
- Need to create production infrastructure

### Target Architecture

Create an infrastructure foundation for running multiple Telegram bots with the following components:

**botgarden-core** should contain:

- Docker Compose file with Nginx + PostgreSQL for production
- Nginx configuration with multiple webhook endpoints support
- SSL/TLS termination for secure webhook connections
- PostgreSQL cluster for all bots
- SSH deployment automation scripts
- Environment management system (.env templates)

**botgarden-core deployment process**:

1. Clone repository to local machine
2. Configure Nginx for VPS domain name/IP
3. Run SSH deploy script в†’ build and run containers on VPS
4. Output to user: PostgreSQL access credentials, endpoints

**hello-bot deployment process**:

1. Clone bot repository
2. Configure ENV variables: SSH access, PostgreSQL credentials, webhook URL
3. Run SSH deploy script в†’ build and run separate bot instance on VPS
4. Automatic database binding and webhook registration in Telegram

## Technical Requirements and Constraints

### Priorities

- **Maximum simplicity**: minimal configuration, clear scripts
- **Performance**: components should be lightweight and capable of handling high load
- **Security**: SSL termination, container isolation, secure secret storage
- **Scalability**: easy addition of new bots without changing core infrastructure

### Technology Stack

- **Containerization**: Docker + Docker Compose
- **Reverse Proxy**: Nginx (for SSL termination and webhook routing)
- **Database**: PostgreSQL (single cluster for all bots)
- **Bots**: Python 3.11+ + aiogram 3.x + SQLAlchemy
- **Deployment**: SSH automation with bash scripts

### Architectural Constraints

- Single VPS for entire infrastructure
- Telegram webhook requires HTTPS (ports 443, 8443, 80, 88)
- Minimal resource consumption
- No complex orchestration systems (Kubernetes, etc.)

## Expected Results

Please provide:

### 1. Recommended Components

- Specific Docker image versions
- Lightweight alternatives for production
- Monitoring and logging tools (optional)

### 2. Concrete Implementation Examples

- `docker-compose.yml` for botgarden-core
- Nginx configuration with SSL and webhook routing
- Dockerfile for hello-bot
- ENV file templates
- SSH deployment scripts with error handling

### 3. Step-by-step Implementation Plan

Detailed plan with key milestones:

- VPS setup and SSH key configuration
- botgarden-core infrastructure initialization
- SSL certificate creation (Let's Encrypt)
- PostgreSQL configuration with users and databases
- Nginx virtual hosts setup
- Webhook endpoints testing
- First hello-bot deployment
- Backup and update procedures
- Monitoring and troubleshooting

### 4. Security and Best Practices

- Secret and API key management
- Network isolation between containers
- VPS firewall rules
- PostgreSQL backup strategies
- Rolling updates without downtime

The result should allow deploying complete bot infrastructure with a single command and adding new bots to the existing system with minimal effort.

Result: Create PLAN_CLAUDE.md
