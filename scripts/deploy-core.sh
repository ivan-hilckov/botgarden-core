#!/usr/bin/env bash
set -euo pipefail

# Deploy botgarden-core infrastructure to VPS

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

REMOTE_DIR="/opt/botgarden-core"

# Script accepts no parameters
[[ $# -gt 0 ]] && error "This script accepts no parameters. Configuration is read from .env file."

echo "Botgarden Core Infrastructure Deployment"
echo "==========================================="

# Check if .env exists and load it
if [[ -f ".env" ]]; then
    log "Loading configuration from .env..."
    set -a
    source .env
    set +a
else
    if [[ -f "env.example" ]]; then
        warn ".env not found, creating from env.example"
        cp env.example .env
        error "Please edit .env file with your configuration and run again"
    else
        error ".env file not found. Please create it from env.example"
    fi
fi

# Validate required parameters from .env
[[ -z "${VPS_HOST:-}" ]] && error "VPS_HOST is required in .env file"
[[ -z "${VPS_USER:-}" ]] && error "VPS_USER is required in .env file"
[[ -z "${DOMAIN:-}" ]] && error "DOMAIN is required in .env file"
[[ -z "${LETSENCRYPT_EMAIL:-}" ]] && error "LETSENCRYPT_EMAIL is required in .env file"

# SSH options (use VPS_SSH_PORT from .env or default to 22)
SSH_PORT=${VPS_SSH_PORT:-22}
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=60 -o ServerAliveCountMax=3 -p ${SSH_PORT}"

log "Configuration:"
log "  VPS: ${VPS_USER}@${VPS_HOST}:${SSH_PORT}"
log "  Domain: ${DOMAIN}"
log "  Email: ${LETSENCRYPT_EMAIL}"
log "  Remote dir: ${REMOTE_DIR}"
echo ""

# SSH command wrapper
ssh_exec() {
    ssh $SSH_OPTS "$VPS_USER@$VPS_HOST" "$@"
}

# Main deployment (existing containers will be automatically restarted)
log "Starting core infrastructure deployment..."

# Setup directory structure and copy SSL certificates
log "Setting up directories and SSL certificates..."
ssh_exec "
    sudo mkdir -p $REMOTE_DIR/{logs/nginx,backups,certs/live,certs/archive}
    sudo chown -R \$USER:\$USER $REMOTE_DIR
    
    # Copy SSL certificates from letsencrypt to project directory
    if [[ -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem ]]; then
        sudo mkdir -p $REMOTE_DIR/certs/live/${DOMAIN}
        sudo cp -L /etc/letsencrypt/live/${DOMAIN}/fullchain.pem /etc/letsencrypt/live/${DOMAIN}/privkey.pem $REMOTE_DIR/certs/live/${DOMAIN}/
        sudo chown -R \$USER:\$USER $REMOTE_DIR/certs/
        echo 'SSL certificates copied successfully'
    else
        echo 'Warning: SSL certificates not found in /etc/letsencrypt/live/${DOMAIN}/'
    fi
"

# Sync project files
log "Syncing project files..."
rsync -az --delete -e "ssh $SSH_OPTS" \
    --exclude='.git' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    --exclude='certs/' \
    ./ "$VPS_USER@$VPS_HOST:$REMOTE_DIR/"

# Start services with built-in wait
log "Starting core services..."
ssh_exec "
    cd $REMOTE_DIR
    docker compose down --remove-orphans 2>/dev/null || true
    docker compose up -d --wait --wait-timeout 60
"

# Test HTTP endpoint
log "Testing HTTP and HTTPS endpoints..."
sleep 5

if curl -s --connect-timeout 10 "http://${DOMAIN}/health" > /dev/null 2>&1; then
    success "HTTP endpoint is working"
else
    warn "HTTP endpoint not accessible yet (may need DNS propagation)"
fi

if curl -s --connect-timeout 10 "https://${DOMAIN}/health" >/dev/null 2>&1; then
    success "HTTPS endpoint is working"
else
    warn "HTTPS endpoint not accessible yet (may need time to propagate)"
fi

# Display deployment summary
success "Core infrastructure deployed successfully!"