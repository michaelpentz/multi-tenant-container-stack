#!/bin/bash

# VTT Stack - Setup Script
# Automated setup and installation
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

# Check if running on supported OS
check_os() {
    log_step "Checking operating system..."
    
    case "$OSTYPE" in
        linux-gnu*)
            log_info "Linux detected"
            ;;
        darwin*)
            log_info "macOS detected"
            ;;
        msys*|cygwin*|mingw*)
            log_info "Windows detected (Git Bash)"
            ;;
        *)
            log_warn "Unknown OS: $OSTYPE"
            log_warn "This script is designed for Linux, macOS, or Windows Git Bash"
            ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed"
        log_info "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker version
    DOCKER_VERSION=$(docker --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    log_info "Docker version: $DOCKER_VERSION"
    
    # Check Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed"
        log_info "Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    COMPOSE_VERSION=$(docker compose version --short)
    log_info "Docker Compose version: $COMPOSE_VERSION"
    
    log_info "All prerequisites met"
}

# Create directory structure
create_directories() {
    log_step "Creating directory structure..."
    
    cd "$PROJECT_DIR"
    
    # Create data directories
    mkdir -p foundry-vtt/data/campaign1
    mkdir -p foundry-vtt/data/campaign2
    mkdir -p foundry-vtt/shared_assets
    
    # Create Grafana directories
    mkdir -p monitoring/grafana/provisioning/datasources
    mkdir -p monitoring/grafana/provisioning/dashboards
    mkdir -p monitoring/grafana/dashboards
    
    log_info "Directory structure created"
}

# Copy environment files
setup_env_files() {
    log_step "Setting up environment files..."
    
    cd "$PROJECT_DIR"
    
    # Foundry VTT
    if [[ ! -f "foundry-vtt/.env" ]]; then
        if [[ -f "foundry-vtt/.env.example" ]]; then
            cp foundry-vtt/.env.example foundry-vtt/.env
            log_info "Created foundry-vtt/.env from example"
        fi
    else
        log_warn "foundry-vtt/.env already exists, skipping"
    fi
    
    # Monitoring
    if [[ ! -f "monitoring/.env" ]]; then
        if [[ -f "monitoring/.env.example" ]]; then
            cp monitoring/.env.example monitoring/.env
            log_info "Created monitoring/.env from example"
        fi
    else
        log_warn "monitoring/.env already exists, skipping"
    fi
    
    # FileBrowser
    if [[ ! -f "filebrowser/.env" ]]; then
        if [[ -f "filebrowser/.env.example" ]]; then
            cp filebrowser/.env.example filebrowser/.env
            log_info "Created filebrowser/.env from example"
        fi
    else
        log_warn "filebrowser/.env already exists, skipping"
    fi
}

# Set permissions (Linux/macOS only)
set_permissions() {
    log_step "Setting permissions..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Setting ownership for data directories..."
        
        # The containers run as UID 1000
        sudo chown -R 1000:1000 "$PROJECT_DIR/foundry-vtt/data" 2>/dev/null || {
            log_warn "Could not change ownership (may need to run with sudo)"
            log_info "You can manually fix permissions later with:"
            log_info "  sudo chown -R 1000:1000 foundry-vtt/data/"
        }
    else
        log_info "Skipping permission setup on Windows"
    fi
}

# Pull Docker images
pull_images() {
    log_step "Pulling Docker images..."
    
    cd "$PROJECT_DIR"
    
    log_info "Pulling Foundry VTT image..."
    docker pull felddy/foundryvtt:13.351 || log_warn "Could not pull Foundry VTT image"
    
    log_info "Pulling monitoring images..."
    docker pull gcr.io/cadvisor/cadvisor:v0.47.2 || log_warn "Could not pull cAdvisor image"
    docker pull prom/prometheus:v2.48.0 || log_warn "Could not pull Prometheus image"
    docker pull grafana/grafana:10.2.3 || log_warn "Could not pull Grafana image"
    
    log_info "Pulling FileBrowser image..."
    docker pull filebrowser/filebrowser:v2.26.0 || log_warn "Could not pull FileBrowser image"
    
    log_info "Docker images pulled"
}

# Verify installation
verify_installation() {
    log_step "Verifying installation..."
    
    cd "$PROJECT_DIR"
    
    # Check if compose files are valid
    log_info "Validating docker-compose files..."
    
    docker compose -f foundry-vtt/docker-compose.yml config > /dev/null 2>&1 && {
        log_info "✓ Foundry VTT compose file is valid"
    } || {
        log_error "✗ Foundry VTT compose file has errors"
    }
    
    docker compose -f monitoring/docker-compose.yml config > /dev/null 2>&1 && {
        log_info "✓ Monitoring compose file is valid"
    } || {
        log_error "✗ Monitoring compose file has errors"
    }
    
    docker compose -f filebrowser/docker-compose.yml config > /dev/null 2>&1 && {
        log_info "✓ FileBrowser compose file is valid"
    } || {
        log_error "✗ FileBrowser compose file has errors"
    }
    
    log_info "Installation verification complete"
}

# Print next steps
print_next_steps() {
    echo
    echo "================================"
    echo "Setup Complete!"
    echo "================================"
    echo
    log_info "VTT Stack has been set up successfully!"
    echo
    echo "Next steps:"
    echo
    echo "1. Edit environment files with your credentials:"
    echo "   nano foundry-vtt/.env"
    echo "   nano monitoring/.env"
    echo "   nano filebrowser/.env"
    echo
    echo "2. Start all services:"
    echo "   ./scripts/start-all.sh"
    echo
    echo "3. Access your services:"
    echo "   Campaign 1:  http://localhost:30000"
    echo "   Campaign 2:  http://localhost:30001"
    echo "   Grafana:     http://localhost:3000"
    echo "   FileBrowser: http://localhost:8080"
    echo
    echo "4. Read the documentation:"
    echo "   cat README.md"
    echo "   cat docs/DEPLOYMENT.md"
    echo
    echo "For help and troubleshooting:"
    echo "   ./scripts/start-all.sh --help"
}

# Main function
main() {
    echo "================================"
    echo "VTT Stack - Setup"
    echo "================================"
    echo
    
    check_os
    check_prerequisites
    create_directories
    setup_env_files
    set_permissions
    pull_images
    verify_installation
    
    print_next_steps
}

# Run main function
main "$@"
