#!/usr/bin/env bash
set -euo pipefail

# Deploy static files to botgarden-core infrastructure

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
STATIC_DIR="static"

# Script accepts no parameters
[[ $# -gt 0 ]] && error "This script accepts no parameters. Configuration is read from .env file."

echo "📁 Botgarden Static Files Deployment"
echo "===================================="

# Load configuration
if [[ -f ".env" ]]; then
    set -a
    source .env
    set +a
else
    error "No .env file found. Please create it from env.example"
fi

# Check required variables
[[ -z "${VPS_HOST:-}" ]] && error "VPS_HOST not set in .env"
[[ -z "${VPS_USER:-}" ]] && error "VPS_USER not set in .env"
[[ -z "${DOMAIN:-}" ]] && error "DOMAIN not set in .env"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p ${VPS_SSH_PORT:-22}"

log "Configuration:"
log "  VPS: ${VPS_USER}@${VPS_HOST}"
log "  Domain: ${DOMAIN}"
log "  Static dir: ${STATIC_DIR}"
echo ""

# Check if static directory exists
if [[ ! -d "$STATIC_DIR" ]]; then
    error "Static directory '$STATIC_DIR' not found"
fi

# SSH command wrapper
ssh_exec() {
    ssh $SSH_OPTS "$VPS_USER@$VPS_HOST" "$@"
}

# Preflight checks
log "Running preflight checks..."

# Check if remote directory exists
if ! ssh_exec "test -d $REMOTE_DIR" 2>/dev/null; then
    error "Remote directory not found: $REMOTE_DIR. Deploy core infrastructure first."
fi

# Deploy static files
log "Deploying static files..."

# Sync static files
rsync -az --delete -e "ssh $SSH_OPTS" \
    --exclude='.DS_Store' \
    --exclude='Thumbs.db' \
    --exclude='*.tmp' \
    "$STATIC_DIR/" "$VPS_USER@$VPS_HOST:$REMOTE_DIR/static/"

success "Static files uploaded"

# Test HTTPS endpoint
log "Testing HTTPS endpoint..."
if curl -s --connect-timeout 10 "https://${DOMAIN}/" >/dev/null 2>&1; then
    success "HTTPS static files accessible"
else
    warn "HTTPS static files not accessible yet (may need time to propagate)"
fi

# Display deployment summary
success "Static files deployment completed!"
