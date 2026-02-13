#!/bin/bash

# VTT Stack - Full Deployment Script
# Deploys all optimizations and updates
# Run as root on the server

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check if root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log_step "=== VTT STACK DEPLOYMENT ==="
log_info "Starting deployment at $(date)"
echo

# Find project directory
PROJECT_DIR=""
if [[ -d "/home/foundry/vtt-stack" ]]; then
    PROJECT_DIR="/home/foundry/vtt-stack"
elif [[ -d "/opt/vtt-stack" ]]; then
    PROJECT_DIR="/opt/vtt-stack"
elif [[ -d "/root/vtt-stack" ]]; then
    PROJECT_DIR="/root/vtt-stack"
else
    log_error "Could not find vtt-stack directory"
    log_info "Please specify the path:"
    read -r PROJECT_DIR
    if [[ ! -d "$PROJECT_DIR" ]]; then
        log_error "Directory not found: $PROJECT_DIR"
        exit 1
    fi
fi

log_info "Found project at: $PROJECT_DIR"
cd "$PROJECT_DIR"

# Step 1: System Update
log_step "Step 1/10: Updating system packages..."
apt-get update
apt-get upgrade -y
apt-get autoremove -y
log_info "System updated"

# Step 2: Pull latest changes
log_step "Step 2/10: Pulling latest changes from GitLab..."
if [[ -d ".git" ]]; then
    git pull origin main
    log_info "Code updated"
else
    log_warn "Not a git repository, skipping pull"
fi

# Step 3: Check disk space
log_step "Step 3/10: Checking disk space..."
DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 80 ]]; then
    log_warn "Disk usage is at ${DISK_USAGE}%"
    log_info "Cleaning up..."
    docker system prune -f
    apt-get autoclean
else
    log_info "Disk usage is ${DISK_USAGE}% - OK"
fi

# Step 4: Backup current state
log_step "Step 4/10: Creating backup..."
BACKUP_DIR="/backups/pre-deployment-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup data
tar czf "$BACKUP_DIR/foundry-data.tar.gz" -C foundry-vtt/data . 2>/dev/null || true
cp foundry-vtt/.env "$BACKUP_DIR/" 2>/dev/null || true
cp monitoring/.env "$BACKUP_DIR/" 2>/dev/null || true
log_info "Backup created at: $BACKUP_DIR"

# Step 5: Stop all services
log_step "Step 5/10: Stopping all services..."
./scripts/stop-all.sh 2>/dev/null || {
    log_warn "Stop script failed, stopping manually..."
    docker stop foundry-campaign1 foundry-campaign2 filebrowser grafana prometheus cadvisor beszel beszel-agent 2>/dev/null || true
    docker rm foundry-campaign1 foundry-campaign2 filebrowser grafana prometheus cadvisor beszel beszel-agent 2>/dev/null || true
}
log_info "Services stopped"

# Step 6: Update Foundry VTT configuration
log_step "Step 6/10: Updating Foundry VTT configuration..."
cd foundry-vtt

# Check if .env exists, create from example if not
if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        log_warn "Created .env from example - PLEASE EDIT IT"
    fi
fi

# Recreate containers with new config
docker compose down
docker compose pull
docker compose up -d
cd ..

log_info "Foundry VTT updated"

# Step 7: Deploy Nginx (if not already deployed)
log_step "Step 7/10: Deploying Nginx reverse proxy..."
if [[ -d "nginx" ]]; then
    cd nginx
    
    # Check if nginx is already running
    if docker ps | grep -q "nginx-proxy"; then
        log_info "Nginx already running, updating..."
        docker compose down
    fi
    
    docker compose up -d
    cd ..
    log_info "Nginx deployed"
else
    log_warn "Nginx directory not found, skipping"
fi

# Step 8: Update Monitoring
log_step "Step 8/10: Updating monitoring stack..."
cd monitoring

if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        log_warn "Created monitoring/.env from example"
    fi
fi

docker compose up -d
cd ..
log_info "Monitoring stack updated"

# Step 9: Update FileBrowser
log_step "Step 9/10: Updating FileBrowser..."
cd filebrowser

if [[ ! -f ".env" ]]; then
    if [[ -f ".env.example" ]]; then
        cp .env.example .env
        log_warn "Created filebrowser/.env from example"
    fi
fi

docker compose up -d
cd ..
log_info "FileBrowser updated"

# Step 10: Network optimization
log_step "Step 10/10: Applying network optimizations..."
if [[ -f "scripts/optimize-network.sh" ]]; then
    chmod +x scripts/optimize-network.sh
    ./scripts/optimize-network.sh || log_warn "Network optimization had issues, continuing..."
else
    log_warn "Network optimization script not found"
fi

# Restart Docker to apply network changes
log_info "Restarting Docker..."
systemctl restart docker

# Wait for Docker to be ready
sleep 5

# Start all services
log_step "Starting all services..."
./scripts/start-all.sh 2>/dev/null || {
    log_warn "Start script failed, starting manually..."
    docker compose -f foundry-vtt/docker-compose.yml up -d
    docker compose -f monitoring/docker-compose.yml up -d
    docker compose -f filebrowser/docker-compose.yml up -d
    if [[ -d "nginx" ]]; then
        docker compose -f nginx/docker-compose.yml up -d
    fi
}

# Verify deployment
log_step "Verifying deployment..."
sleep 10

echo
echo "=== Container Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo
echo "=== Health Checks ==="
for container in foundry-campaign1 foundry-campaign2 nginx-proxy; do
    if docker ps | grep -q "$container"; then
        health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "N/A")
        log_info "$container: $health"
    else
        log_warn "$container: Not running"
    fi
done

# Final summary
echo
log_step "=== DEPLOYMENT COMPLETE ==="
log_info "Finished at $(date)"
echo
echo "Access your services:"
echo "  Campaign 1:  http://$(hostname -I | awk '{print $1}'):30000"
echo "  Campaign 2:  http://$(hostname -I | awk '{print $1}'):30001"
echo "  Grafana:     http://$(hostname -I | awk '{print $1}'):3000"
echo "  FileBrowser: http://$(hostname -I | awk '{print $1}'):8080"
if docker ps | grep -q "nginx-proxy"; then
    echo "  Nginx Proxy: http://$(hostname -I | awk '{print $1}')"
fi
echo
echo "View logs:"
echo "  docker logs -f foundry-campaign1"
echo "  docker logs -f nginx-proxy"
echo
echo "Backup location: $BACKUP_DIR"
echo
log_info "Deployment successful!"
