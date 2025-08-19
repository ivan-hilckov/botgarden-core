#!/usr/bin/env bash
set -euo pipefail

# Deploy Telegram bot to botgarden-core infrastructure

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

BOT_NAME=$(basename "$(pwd)")
REMOTE_DIR="/opt/bots"

# Script accepts no parameters
[[ $# -gt 0 ]] && error "This script accepts no parameters. Configuration is read from .env file."

echo "🤖 Botgarden Bot Deployment"
echo "=========================="

# Load bot configuration from .env
if [[ ! -f ".env" ]]; then
    error ".env file not found. Please create it with BOT_TOKEN and other bot configuration."
fi

log "Loading bot configuration from .env..."
set -a
source .env
set +a

# Load core infrastructure config from standard location
if [[ -f "../.env" ]]; then
    log "Loading core infrastructure config..."
    set -a
    source ../.env
    set +a
else
    error "Cannot find botgarden-core .env file at ../.env. Please ensure botgarden-core is deployed."
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
    ssh $SSH_OPTS "$VPS_USER@$VPS_HOST" "$@"
}

# Preflight checks
log "Running preflight checks..."

# Check required files
[[ ! -f "Dockerfile" ]] && error "Dockerfile not found in current directory"
[[ ! -f "docker-compose.yml" ]] && error "docker-compose.yml not found in current directory"

# Validate required bot configuration
[[ -z "${BOT_TOKEN:-}" ]] && error "BOT_TOKEN is required in .env file"

# Main deployment
log "Starting bot deployment..."

# Create directory and sync files
log "Syncing bot files..."
ssh_exec "mkdir -p $BOT_REMOTE_DIR"
rsync -az --delete -e "ssh $SSH_OPTS" \
    --exclude='.git' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    ./ "$VPS_USER@$VPS_HOST:$BOT_REMOTE_DIR/"

# Deploy bot
log "Deploying bot..."
ssh_exec "
    cd $BOT_REMOTE_DIR
    
    # Stop existing bot if running
    docker compose down 2>/dev/null || true
    
    # Build and start bot
    docker compose up -d --build --force-recreate --wait --wait-timeout 60
    
    echo 'Bot deployment completed'
"

# Register webhook and test
log "Registering webhook..."
webhook_data="url=$WEBHOOK_URL&drop_pending_updates=true"
if [[ -n "${WEBHOOK_SECRET:-}" ]]; then
    webhook_data="$webhook_data&secret_token=$WEBHOOK_SECRET"
fi

if response=$(curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/setWebhook" -d "$webhook_data"); then
    if echo "$response" | grep -q '"ok":true'; then
        success "Webhook registered successfully"
    else
        warn "Webhook registration failed"
    fi
else
    warn "Failed to register webhook"
fi

# Display deployment summary
success "Bot $BOT_NAME deployed successfully!"
