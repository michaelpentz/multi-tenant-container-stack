#!/bin/bash

# VTT Stack - Automated Backup Script
# Backs up all campaign data, shared assets, and configurations
# Version: 2.0.0

set -euo pipefail

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="vtt-stack-backup-${TIMESTAMP}"
CURRENT_BACKUP_DIR="${BACKUP_DIR}/${BACKUP_NAME}"

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

# Check if running as root (not recommended)
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "Running as root. This is not recommended for security reasons."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory: ${CURRENT_BACKUP_DIR}"
    mkdir -p "${CURRENT_BACKUP_DIR}"
    
    # Create subdirectories
    mkdir -p "${CURRENT_BACKUP_DIR}"/{campaigns,configs,databases,logs}
}

# Backup campaign data
backup_campaigns() {
    log_info "Backing up campaign data..."
    
    # Campaign 1
    if docker ps | grep -q "foundry-campaign1"; then
        log_info "Backing up Campaign 1..."
        docker exec foundry-campaign1 tar czf - -C /data . > "${CURRENT_BACKUP_DIR}/campaigns/campaign1.tar.gz" || {
            log_error "Failed to backup Campaign 1"
            return 1
        }
    else
        log_warn "Campaign 1 container not running, skipping..."
    fi
    
    # Campaign 2
    if docker ps | grep -q "foundry-campaign2"; then
        log_info "Backing up Campaign 2..."
        docker exec foundry-campaign2 tar czf - -C /data . > "${CURRENT_BACKUP_DIR}/campaigns/campaign2.tar.gz" || {
            log_error "Failed to backup Campaign 2"
            return 1
        }
    else
        log_warn "Campaign 2 container not running, skipping..."
    fi
    
    # Shared assets
    if [[ -d "../foundry-vtt/shared_assets" ]]; then
        log_info "Backing up shared assets..."
        tar czf "${CURRENT_BACKUP_DIR}/campaigns/shared_assets.tar.gz" -C ../foundry-vtt/shared_assets . || {
            log_warn "Failed to backup shared assets"
        }
    fi
}

# Backup configurations
backup_configs() {
    log_info "Backing up configuration files..."
    
    # Docker Compose files
    cp ../foundry-vtt/docker-compose.yml "${CURRENT_BACKUP_DIR}/configs/" 2>/dev/null || true
    cp ../monitoring/docker-compose.yml "${CURRENT_BACKUP_DIR}/configs/" 2>/dev/null || true
    cp ../filebrowser/docker-compose.yml "${CURRENT_BACKUP_DIR}/configs/" 2>/dev/null || true
    
    # Environment files (with warning)
    if [[ -f "../foundry-vtt/.env" ]]; then
        log_warn "Backing up .env files - ensure they are stored securely!"
        cp ../foundry-vtt/.env "${CURRENT_BACKUP_DIR}/configs/foundry-vtt.env"
        cp ../monitoring/.env "${CURRENT_BACKUP_DIR}/configs/monitoring.env"
        cp ../filebrowser/.env "${CURRENT_BACKUP_DIR}/configs/filebrowser.env"
    fi
    
    # Prometheus config
    cp ../monitoring/prometheus.yml "${CURRENT_BACKUP_DIR}/configs/" 2>/dev/null || true
    cp ../monitoring/alert-rules.yml "${CURRENT_BACKUP_DIR}/configs/" 2>/dev/null || true
}

# Backup databases
backup_databases() {
    log_info "Backing up databases..."
    
    # FileBrowser database
    if [[ -f "../filebrowser/filebrowser.db" ]]; then
        cp ../filebrowser/filebrowser.db "${CURRENT_BACKUP_DIR}/databases/"
    fi
    
    # Grafana database (from volume)
    if docker volume ls | grep -q "monitoring_grafana_data"; then
        log_info "Backing up Grafana database..."
        docker run --rm -v monitoring_grafana_data:/data -v "${CURRENT_BACKUP_DIR}/databases":/backup alpine tar czf /backup/grafana-data.tar.gz -C /data . || {
            log_warn "Failed to backup Grafana data"
        }
    fi
}

# Create backup manifest
create_manifest() {
    log_info "Creating backup manifest..."
    
    cat > "${CURRENT_BACKUP_DIR}/MANIFEST.txt" << EOF
VTT Stack Backup Manifest
========================
Backup Name: ${BACKUP_NAME}
Created: $(date)
Hostname: $(hostname)
Docker Version: $(docker --version)

Contents:
---------
EOF
    
    find "${CURRENT_BACKUP_DIR}" -type f -exec ls -lh {} \; >> "${CURRENT_BACKUP_DIR}/MANIFEST.txt"
    
    # Calculate checksums
    log_info "Calculating checksums..."
    find "${CURRENT_BACKUP_DIR}" -type f -exec sha256sum {} \; > "${CURRENT_BACKUP_DIR}/CHECKSUMS.sha256"
}

# Clean old backups
cleanup_old_backups() {
    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."
    
    find "${BACKUP_DIR}" -type d -name "vtt-stack-backup-*" -mtime +${RETENTION_DAYS} -print0 | while IFS= read -r -d '' backup; do
        log_info "Removing old backup: ${backup}"
        rm -rf "${backup}"
    done
}

# Verify backup integrity
verify_backup() {
    log_info "Verifying backup integrity..."
    
    # Check if backup directory exists and has content
    if [[ ! -d "${CURRENT_BACKUP_DIR}" ]]; then
        log_error "Backup directory not found!"
        return 1
    fi
    
    # Verify checksums
    if [[ -f "${CURRENT_BACKUP_DIR}/CHECKSUMS.sha256" ]]; then
        cd "${CURRENT_BACKUP_DIR}"
        if sha256sum -c CHECKSUMS.sha256 > /dev/null 2>&1; then
            log_info "Checksum verification passed"
        else
            log_error "Checksum verification failed!"
            return 1
        fi
        cd - > /dev/null
    fi
    
    # Check manifest exists
    if [[ ! -f "${CURRENT_BACKUP_DIR}/MANIFEST.txt" ]]; then
        log_warn "Manifest file not found"
    fi
}

# Upload to remote storage (optional)
upload_backup() {
    # Example: AWS S3
    if command -v aws &> /dev/null; then
        if [[ -n "${S3_BUCKET:-}" ]]; then
            log_info "Uploading to S3..."
            aws s3 sync "${CURRENT_BACKUP_DIR}" "s3://${S3_BUCKET}/vtt-stack-backups/${BACKUP_NAME}/" || {
                log_warn "Failed to upload to S3"
            }
        fi
    fi
    
    # Example: rclone
    if command -v rclone &> /dev/null; then
        if [[ -n "${RCLONE_REMOTE:-}" ]]; then
            log_info "Uploading via rclone..."
            rclone copy "${CURRENT_BACKUP_DIR}" "${RCLONE_REMOTE}:vtt-stack-backups/${BACKUP_NAME}/" || {
                log_warn "Failed to upload via rclone"
            }
        fi
    fi
}

# Main backup process
main() {
    log_info "Starting VTT Stack backup..."
    log_info "Backup directory: ${CURRENT_BACKUP_DIR}"
    
    check_root
    create_backup_dir
    backup_campaigns
    backup_configs
    backup_databases
    create_manifest
    verify_backup
    upload_backup
    cleanup_old_backups
    
    log_info "Backup completed successfully!"
    log_info "Backup location: ${CURRENT_BACKUP_DIR}"
    log_info "Size: $(du -sh ${CURRENT_BACKUP_DIR} | cut -f1)"
}

# Handle script interruption
cleanup() {
    log_error "Backup interrupted!"
    if [[ -d "${CURRENT_BACKUP_DIR}" ]]; then
        log_info "Cleaning up partial backup..."
        rm -rf "${CURRENT_BACKUP_DIR}"
    fi
    exit 1
}

trap cleanup INT TERM

# Run main function
main "$@"
