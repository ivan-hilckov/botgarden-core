#!/usr/bin/env bash
set -euo pipefail

# Bot deployment script for botgarden-core
# Usage: ./scripts/deploy-bot.sh

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
    -n, --name NAME          Bot name (default: current directory name)
    -t, --token TOKEN        Telegram bot token
    -p, --port PORT          Bot port (default: 8080)
    --webhook-secret SECRET  Webhook secret for security
    --no-webhook            Skip webhook registration
    --dry-run               Show what would be done without executing
    --force                 Force deployment even if bot is running
    --help                  Show this help

EXAMPLES:
    $0 -n hello-bot -t "123456789:ABC..."
    $0 --name my-bot --token "TOKEN" --port 8081
    $0 --dry-run            # Preview deployment

The script expects to be run from a bot directory containing:
- Dockerfile
- docker-compose.bot.yml (or will create from template)
- .env (or will create from .env.example)

EOF
    exit 1
}

# Default values
BOT_NAME=$(basename "$(pwd)")
BOT_PORT=8080
BOT_TOKEN=""
WEBHOOK_SECRET=""
NO_WEBHOOK=false
DRY_RUN=false
FORCE=false
REMOTE_DIR="/opt/bots"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            BOT_NAME="$2"
            shift 2
            ;;
        -t|--token)
            BOT_TOKEN="$2"
            shift 2
            ;;
        -p|--port)
            BOT_PORT="$2"
            shift 2
            ;;
        --webhook-secret)
            WEBHOOK_SECRET="$2"
            shift 2
            ;;
        --no-webhook)
            NO_WEBHOOK=true
            shift
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
            usage
            ;;
    esac
done

echo "🤖 Botgarden Bot Deployment"
echo "=========================="

# Validate bot name
if [[ ! "$BOT_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
    error "Bot name must contain only lowercase letters, numbers, and hyphens, and start/end with alphanumeric"
fi

# Load core infrastructure config
CORE_ENV_FOUND=false

# Look for botgarden-core .env file in common locations
for env_path in "../.env" "../../.env" "../../../.env" "$HOME/botgarden-core/.env" "/opt/botgarden-core/.env"; do
    if [[ -f "$env_path" ]]; then
        log "Found botgarden-core config at: $env_path"
        set -a
        source "$env_path"
        set +a
        CORE_ENV_FOUND=true
        break
    fi
done

if [[ "$CORE_ENV_FOUND" == "false" ]]; then
    error "Cannot find botgarden-core .env file. Please ensure botgarden-core is deployed and configured."
fi

# Check required variables from core config
[[ -z "${VPS_HOST:-}" ]] && error "VPS_HOST not set in botgarden-core .env"
[[ -z "${VPS_USER:-}" ]] && error "VPS_USER not set in botgarden-core .env"
[[ -z "${DOMAIN:-}" ]] && error "DOMAIN not set in botgarden-core .env"

# Construct webhook URL
WEBHOOK_BASE="https://${DOMAIN}/webhook"
WEBHOOK_URL="${WEBHOOK_BASE}/${BOT_NAME}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -p ${VPS_SSH_PORT:-22}"
BOT_REMOTE_DIR="$REMOTE_DIR/$BOT_NAME"

log "Configuration:"
log "  Bot name: $BOT_NAME"
log "  Bot port: $BOT_PORT"
log "  Webhook URL: $WEBHOOK_URL"
log "  VPS: ${VPS_USER}@${VPS_HOST}"
log "  Remote dir: $BOT_REMOTE_DIR"
echo ""

# SSH command wrapper
ssh_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: ssh $SSH_OPTS $VPS_USER@$VPS_HOST '$*'"
    else
        ssh $SSH_OPTS "$VPS_USER@$VPS_HOST" "$@"
    fi
}

scp_exec() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: scp $SSH_OPTS $*"
    else
        scp $SSH_OPTS "$@"
    fi
}

# Preflight checks
log "Running preflight checks..."

# Check required files
[[ ! -f "Dockerfile" ]] && error "Dockerfile not found in current directory"

# Check/create bot environment file
if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        warn "Creating .env from .env.example"
        cp .env.example .env
    else
        log "Creating default .env file"
        cat > .env << EOF
# Bot Configuration
BOT_NAME=$BOT_NAME
BOT_TOKEN=$BOT_TOKEN
BOT_PORT=$BOT_PORT
WEBHOOK_SECRET=$WEBHOOK_SECRET
WEBHOOK_URL=$WEBHOOK_URL

# Database (from core infrastructure)
POSTGRES_HOST=bg-postgres
POSTGRES_PORT=5432
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Logging
LOG_LEVEL=INFO
TZ=${TZ:-UTC}
EOF
    fi
fi

# Update .env with current values if they were provided via command line
if [[ "$BOT_NAME" != "$(basename "$(pwd)")" ]]; then
    sed -i.bak "s|BOT_NAME=.*|BOT_NAME=$BOT_NAME|" .env
fi

if [[ -n "$BOT_TOKEN" && "$BOT_TOKEN" != "YOUR_TELEGRAM_BOT_TOKEN_HERE" ]]; then
    sed -i.bak "s|BOT_TOKEN=.*|BOT_TOKEN=$BOT_TOKEN|" .env
fi

if [[ -n "$WEBHOOK_SECRET" ]]; then
    # Add WEBHOOK_SECRET if it doesn't exist, or update if it does
    if grep -q "WEBHOOK_SECRET=" .env; then
        sed -i.bak "s|WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" .env
    else
        echo "WEBHOOK_SECRET=$WEBHOOK_SECRET" >> .env
    fi
fi

# Always update WEBHOOK_URL to match current bot name and domain
sed -i.bak "s|WEBHOOK_URL=.*|WEBHOOK_URL=$WEBHOOK_URL|" .env

# Add WEBHOOK_URL if it doesn't exist
if ! grep -q "WEBHOOK_URL=" .env; then
    echo "WEBHOOK_URL=$WEBHOOK_URL" >> .env
fi

# Check/create docker-compose.bot.yml
if [[ ! -f "docker-compose.bot.yml" ]]; then
    log "Creating docker-compose.bot.yml from template"
    cat > docker-compose.bot.yml << EOF
services:
  bot:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: \${BOT_NAME}
    restart: unless-stopped
    env_file:
      - .env
    expose:
      - "\${BOT_PORT:-8080}"
    networks:
      - botgarden
    volumes:
      - bot-data:/app/data
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
EOF
fi

# Test SSH connection
log "Testing SSH connection..."
if ! ssh_exec "echo 'SSH connection successful'" 2>/dev/null; then
    error "SSH connection failed"
fi

# Check if botgarden network exists
log "Checking botgarden network..."
if ! ssh_exec "docker network inspect botgarden >/dev/null 2>&1"; then
    error "Botgarden network not found. Deploy core infrastructure first using deploy-core.sh"
fi

# Check if bot is already running
if [[ "$FORCE" == "false" ]]; then
    log "Checking for existing bot..."
    if ssh_exec "docker ps --format '{{.Names}}' | grep -q '^$BOT_NAME\$'" 2>/dev/null; then
        error "Bot $BOT_NAME is already running. Use --force to override"
    fi
fi

# Main deployment
log "Starting bot deployment..."

# 1. Create bot directory
log "Creating bot directory..."
ssh_exec "mkdir -p $BOT_REMOTE_DIR"

# 2. Sync bot files
log "Syncing bot files..."
if [[ "$DRY_RUN" == "false" ]]; then
    rsync -az --delete -e "ssh $SSH_OPTS" \
        --exclude='.git' \
        --exclude='*.log' \
        --exclude='.DS_Store' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        ./ "$VPS_USER@$VPS_HOST:$BOT_REMOTE_DIR/"
fi

# 3. Stop existing bot if running
log "Checking for existing bot container..."
ssh_exec "
    # Stop and remove any existing container with this name
    if docker ps -a --format '{{.Names}}' | grep -q '^$BOT_NAME\$'; then
        echo 'Stopping existing bot container...'
        docker stop $BOT_NAME 2>/dev/null || true
        docker rm $BOT_NAME 2>/dev/null || true
        echo 'Existing container removed'
    fi
    
    # Also try to stop via docker-compose if directory exists
    if [ -d '$BOT_REMOTE_DIR' ]; then
        cd '$BOT_REMOTE_DIR'
        docker compose -f docker-compose.bot.yml down 2>/dev/null || true
    fi
"

# 4. Build and start bot
log "Building and starting bot..."
ssh_exec "
    cd $BOT_REMOTE_DIR
    docker compose -f docker-compose.bot.yml up -d --build --force-recreate
"

# 5. Wait for bot to be ready
log "Waiting for bot container to start..."
ssh_exec "
    cd $BOT_REMOTE_DIR
    
    # Wait for container to start
    for i in {1..30}; do
        if docker compose -f docker-compose.bot.yml ps | grep -q 'Up'; then
            echo 'Bot container is running'
            break
        elif [ \$i -eq 30 ]; then
            echo 'Bot container failed to start within 30 seconds'
            docker compose -f docker-compose.bot.yml logs
            exit 1
        else
            echo 'Waiting for bot to start... (\$i/30)'
            sleep 2
        fi
    done
    
    # Give bot time to initialize
    echo 'Bot started, waiting for initialization...'
    sleep 5
    echo 'Bot should be ready for webhooks'
"

# 6. Register webhook (if not disabled)
if [[ "$NO_WEBHOOK" == "false" && -n "$BOT_TOKEN" ]]; then
    log "Registering webhook with Telegram..."
    
    webhook_data="url=$WEBHOOK_URL&drop_pending_updates=true"
    if [[ -n "$WEBHOOK_SECRET" ]]; then
        webhook_data="$webhook_data&secret_token=$WEBHOOK_SECRET"
    fi
    
    if response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" -d "$webhook_data"); then
        if echo "$response" | grep -q '"ok":true'; then
            success "Webhook registered successfully"
        else
            warn "Webhook registration failed: $response"
        fi
    else
        warn "Failed to register webhook (network error)"
    fi
else
    log "Webhook registration skipped"
fi

# 7. Test webhook endpoint
log "Testing webhook endpoint..."
if webhook_status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$WEBHOOK_URL" 2>/dev/null); then
    if [[ "$webhook_status" == "200" || "$webhook_status" == "405" ]]; then
        success "Webhook endpoint accessible (status: $webhook_status)"
    else
        warn "Webhook endpoint returned status: $webhook_status"
    fi
else
    warn "Webhook endpoint not accessible"
fi

# 8. Display deployment summary
log "Gathering deployment information..."

container_status=$(ssh_exec "docker ps --filter name=$BOT_NAME --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'")

success "Bot $BOT_NAME deployed successfully!"
echo ""
echo "🤖 Bot Information:"
echo "  📛 Name: $BOT_NAME"
echo "  🔗 Webhook URL: $WEBHOOK_URL"
echo "  🚪 Port: $BOT_PORT"
echo "  📊 Container Status:"
echo "$container_status"
echo ""
echo "📋 Management Commands:"
echo "  📊 Status: ssh $VPS_USER@$VPS_HOST 'docker ps --filter name=$BOT_NAME'"
echo "  📄 Logs: ssh $VPS_USER@$VPS_HOST 'docker logs $BOT_NAME -f'"
echo "  🔄 Restart: ssh $VPS_USER@$VPS_HOST 'cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml restart'"
echo "  🛑 Stop: ssh $VPS_USER@$VPS_HOST 'cd $BOT_REMOTE_DIR && docker compose -f docker-compose.bot.yml down'"
echo ""
echo "🧪 Testing:"
echo "  curl -I $WEBHOOK_URL"
echo "  curl https://${DOMAIN}/health"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    warn "This was a dry run - no actual changes were made"
fi
