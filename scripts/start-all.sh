#!/bin/bash

# VTT Stack - Start All Services
# Convenience script to start all components
# Version: 2.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed"
        exit 1
    fi
    
    # Check if .env files exist
    local missing_env=false
    
    if [[ ! -f "$PROJECT_DIR/foundry-vtt/.env" ]]; then
        log_warn "foundry-vtt/.env not found - using example file"
        if [[ -f "$PROJECT_DIR/foundry-vtt/.env.example" ]]; then
            cp "$PROJECT_DIR/foundry-vtt/.env.example" "$PROJECT_DIR/foundry-vtt/.env"
            log_warn "Please edit foundry-vtt/.env with your credentials"
        fi
        missing_env=true
    fi
    
    if [[ ! -f "$PROJECT_DIR/monitoring/.env" ]]; then
        log_warn "monitoring/.env not found - using example file"
        if [[ -f "$PROJECT_DIR/monitoring/.env.example" ]]; then
            cp "$PROJECT_DIR/monitoring/.env.example" "$PROJECT_DIR/monitoring/.env"
        fi
        missing_env=true
    fi
    
    if [[ ! -f "$PROJECT_DIR/filebrowser/.env" ]]; then
        log_warn "filebrowser/.env not found - using example file"
        if [[ -f "$PROJECT_DIR/filebrowser/.env.example" ]]; then
            cp "$PROJECT_DIR/filebrowser/.env.example" "$PROJECT_DIR/filebrowser/.env"
        fi
        missing_env=true
    fi
    
    if [[ "$missing_env" == true ]]; then
        log_warn "Environment files were created from examples"
        log_warn "Please review and update them with your actual credentials"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_info "Prerequisites check passed"
}

# Create necessary directories
create_directories() {
    log_step "Creating necessary directories..."
    
    mkdir -p "$PROJECT_DIR/foundry-vtt/data/campaign1"
    mkdir -p "$PROJECT_DIR/foundry-vtt/data/campaign2"
    mkdir -p "$PROJECT_DIR/foundry-vtt/shared_assets"
    
    # Set permissions (Linux/macOS only)
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Setting directory permissions..."
        chown -R 1000:1000 "$PROJECT_DIR/foundry-vtt/data" 2>/dev/null || {
            log_warn "Could not change ownership (may need sudo)"
        }
    fi
}

# Start monitoring stack
start_monitoring() {
    log_step "Starting monitoring stack..."
    
    cd "$PROJECT_DIR/monitoring"
    
    # Create grafana directories if they don't exist
    mkdir -p grafana/provisioning/datasources
    mkdir -p grafana/provisioning/dashboards
    mkdir -p grafana/dashboards
    
    docker compose up -d
    
    log_info "Monitoring stack started"
    log_info "  Grafana: http://localhost:3000"
}

# Start Foundry VTT
start_foundry() {
    log_step "Starting Foundry VTT..."
    
    cd "$PROJECT_DIR/foundry-vtt"
    docker compose up -d
    
    log_info "Foundry VTT started"
    log_info "  Campaign 1: http://localhost:30000"
    log_info "  Campaign 2: http://localhost:30001"
}

# Start FileBrowser
start_filebrowser() {
    log_step "Starting FileBrowser..."
    
    cd "$PROJECT_DIR/filebrowser"
    docker compose up -d
    
    log_info "FileBrowser started"
    log_info "  URL: http://localhost:8080"
}

# Wait for services to be healthy
wait_for_healthy() {
    log_step "Waiting for services to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        local all_healthy=true
        
        # Check Foundry containers
        for container in foundry-campaign1 foundry-campaign2; do
            if docker ps | grep -q "$container"; then
                local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
                if [[ "$health" != "healthy" ]]; then
                    all_healthy=false
                    break
                fi
            fi
        done
        
        if [[ "$all_healthy" == true ]]; then
            log_info "All services are healthy!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    echo
    log_warn "Some services may still be starting..."
    return 1
}

# Show status
show_status() {
    log_step "Current status:"
    echo
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(foundry|grafana|prometheus|cadvisor|filebrowser)" || true
    echo
}

# Main function
main() {
    echo "================================"
    echo "VTT Stack - Starting Services"
    echo "================================"
    echo
    
    check_prerequisites
    create_directories
    start_monitoring
    start_foundry
    start_filebrowser
    
    echo
    wait_for_healthy
    
    echo
    show_status
    
    log_info "All services started successfully!"
    echo
    echo "Access your services:"
    echo "  Campaign 1:  http://localhost:30000"
    echo "  Campaign 2:  http://localhost:30001"
    echo "  Grafana:     http://localhost:3000"
    echo "  FileBrowser: http://localhost:8080"
    echo
    echo "View logs:"
    echo "  docker logs -f foundry-campaign1"
    echo "  docker logs -f foundry-campaign2"
    echo
}

# Run main function
main "$@"
