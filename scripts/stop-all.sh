#!/bin/bash

# VTT Stack - Stop All Services
# Convenience script to stop all components cleanly
# Version: 2.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Stop services
stop_services() {
    log_info "Stopping all VTT Stack services..."
    
    cd "$PROJECT_DIR"
    
    # Stop FileBrowser
    if [[ -f "filebrowser/docker-compose.yml" ]]; then
        log_info "Stopping FileBrowser..."
        docker compose -f filebrowser/docker-compose.yml down 2>/dev/null || true
    fi
    
    # Stop Foundry VTT
    if [[ -f "foundry-vtt/docker-compose.yml" ]]; then
        log_info "Stopping Foundry VTT..."
        docker compose -f foundry-vtt/docker-compose.yml down 2>/dev/null || true
    fi
    
    # Stop Monitoring
    if [[ -f "monitoring/docker-compose.yml" ]]; then
        log_info "Stopping Monitoring stack..."
        docker compose -f monitoring/docker-compose.yml down 2>/dev/null || true
    fi
    
    log_info "All services stopped"
}

# Show status
show_status() {
    log_info "Remaining containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(foundry|grafana|prometheus|cadvisor|filebrowser)" || echo "  None"
}

# Main function
main() {
    echo "================================"
    echo "VTT Stack - Stopping Services"
    echo "================================"
    echo
    
    stop_services
    
    echo
    show_status
    
    log_info "All services stopped successfully"
}

# Run main function
main "$@"
