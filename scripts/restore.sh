#!/bin/bash

# VTT Stack - Restore Script
# Restores campaign data, shared assets, and configurations from backup
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

# Usage information
usage() {
    cat << EOF
Usage: $0 <backup-file-or-directory> [options]

Restore VTT Stack from backup

Options:
    -h, --help          Show this help message
    -y, --yes           Skip confirmation prompts
    -c, --campaigns     Restore only campaign data
    -f, --configs       Restore only configuration files
    --dry-run          Show what would be restored without doing it

Examples:
    $0 /backups/vtt-stack-backup-2024-01-15_02-30-00
    $0 /backups/vtt-stack-backup-2024-01-15.tar.gz -y
    $0 /path/to/backup.tar.gz --dry-run

EOF
    exit 1
}

# Parse arguments
BACKUP_SOURCE=""
SKIP_CONFIRM=false
RESTORE_CAMPAIGNS=false
RESTORE_CONFIGS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            ;;
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        -c|--campaigns)
            RESTORE_CAMPAIGNS=true
            shift
            ;;
        -f|--configs)
            RESTORE_CONFIGS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$BACKUP_SOURCE" ]]; then
                BACKUP_SOURCE="$1"
            else
                log_error "Multiple backup sources specified"
                usage
            fi
            shift
            ;;
    esac
done

# Validate backup source
if [[ -z "$BACKUP_SOURCE" ]]; then
    log_error "No backup source specified"
    usage
fi

if [[ ! -e "$BACKUP_SOURCE" ]]; then
    log_error "Backup source not found: $BACKUP_SOURCE"
    exit 1
fi

# If no specific restore type specified, restore everything
if [[ "$RESTORE_CAMPAIGNS" == false && "$RESTORE_CONFIGS" == false ]]; then
    RESTORE_CAMPAIGNS=true
    RESTORE_CONFIGS=true
fi

# Extract backup if it's a tar.gz file
extract_backup() {
    local source="$1"
    local extract_dir="/tmp/vtt-stack-restore-$$"
    
    if [[ -f "$source" ]]; then
        log_info "Extracting backup archive..."
        mkdir -p "$extract_dir"
        tar xzf "$source" -C "$extract_dir"
        
        # Find the actual backup directory inside
        BACKUP_DIR=$(find "$extract_dir" -type d -name "vtt-stack-backup-*" | head -1)
        if [[ -z "$BACKUP_DIR" ]]; then
            log_error "Could not find backup directory in archive"
            rm -rf "$extract_dir"
            exit 1
        fi
    elif [[ -d "$source" ]]; then
        BACKUP_DIR="$source"
    else
        log_error "Invalid backup source type"
        exit 1
    fi
    
    echo "$BACKUP_DIR"
}

# Verify backup integrity
verify_backup() {
    local backup_dir="$1"
    
    log_info "Verifying backup integrity..."
    
    # Check manifest
    if [[ ! -f "$backup_dir/MANIFEST.txt" ]]; then
        log_warn "Manifest file not found - backup may be incomplete"
    fi
    
    # Check checksums if available
    if [[ -f "$backup_dir/CHECKSUMS.sha256" ]]; then
        cd "$backup_dir"
        if sha256sum -c CHECKSUMS.sha256 > /dev/null 2>&1; then
            log_info "Checksum verification passed"
        else
            log_error "Checksum verification failed! Backup may be corrupted."
            return 1
        fi
        cd - > /dev/null
    fi
}

# Stop running containers
stop_containers() {
    log_info "Stopping containers..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would stop containers: foundry-campaign1, foundry-campaign2, filebrowser"
        return
    fi
    
    docker stop foundry-campaign1 foundry-campaign2 filebrowser 2>/dev/null || true
}

# Start containers
start_containers() {
    log_info "Starting containers..."
    
    if $DRY_RUN; then
        log_info "[DRY RUN] Would start containers"
        return
    fi
    
    cd ..
    docker compose -f foundry-vtt/docker-compose.yml up -d
    docker compose -f filebrowser/docker-compose.yml up -d
}

# Restore campaign data
restore_campaigns() {
    local backup_dir="$1"
    
    if [[ "$RESTORE_CAMPAIGNS" == false ]]; then
        return
    fi
    
    log_info "Restoring campaign data..."
    
    # Campaign 1
    if [[ -f "$backup_dir/campaigns/campaign1.tar.gz" ]]; then
        log_info "Restoring Campaign 1..."
        if $DRY_RUN; then
            log_info "[DRY RUN] Would restore Campaign 1 from $backup_dir/campaigns/campaign1.tar.gz"
        else
            # Clear existing data
            rm -rf ../foundry-vtt/data/campaign1/*
            # Restore
            tar xzf "$backup_dir/campaigns/campaign1.tar.gz" -C ../foundry-vtt/data/campaign1
            # Fix permissions
            chown -R 1000:1000 ../foundry-vtt/data/campaign1 || true
        fi
    else
        log_warn "Campaign 1 backup not found"
    fi
    
    # Campaign 2
    if [[ -f "$backup_dir/campaigns/campaign2.tar.gz" ]]; then
        log_info "Restoring Campaign 2..."
        if $DRY_RUN; then
            log_info "[DRY RUN] Would restore Campaign 2 from $backup_dir/campaigns/campaign2.tar.gz"
        else
            rm -rf ../foundry-vtt/data/campaign2/*
            tar xzf "$backup_dir/campaigns/campaign2.tar.gz" -C ../foundry-vtt/data/campaign2
            chown -R 1000:1000 ../foundry-vtt/data/campaign2 || true
        fi
    else
        log_warn "Campaign 2 backup not found"
    fi
    
    # Shared assets
    if [[ -f "$backup_dir/campaigns/shared_assets.tar.gz" ]]; then
        log_info "Restoring shared assets..."
        if $DRY_RUN; then
            log_info "[DRY RUN] Would restore shared assets from $backup_dir/campaigns/shared_assets.tar.gz"
        else
            rm -rf ../foundry-vtt/shared_assets/*
            tar xzf "$backup_dir/campaigns/shared_assets.tar.gz" -C ../foundry-vtt/shared_assets
            chown -R 1000:1000 ../foundry-vtt/shared_assets || true
        fi
    fi
}

# Restore configurations
restore_configs() {
    local backup_dir="$1"
    
    if [[ "$RESTORE_CONFIGS" == false ]]; then
        return
    fi
    
    log_info "Restoring configuration files..."
    
    # Docker Compose files
    if [[ -f "$backup_dir/configs/docker-compose.yml" ]]; then
        if $DRY_RUN; then
            log_info "[DRY RUN] Would restore docker-compose.yml files"
        else
            cp "$backup_dir/configs/foundry-vtt-docker-compose.yml" ../foundry-vtt/docker-compose.yml 2>/dev/null || true
            cp "$backup_dir/configs/monitoring-docker-compose.yml" ../monitoring/docker-compose.yml 2>/dev/null || true
            cp "$backup_dir/configs/filebrowser-docker-compose.yml" ../filebrowser/docker-compose.yml 2>/dev/null || true
        fi
    fi
    
    # Environment files (with warning)
    if [[ -f "$backup_dir/configs/foundry-vtt.env" ]]; then
        log_warn "Environment files found in backup"
        log_warn "These may contain outdated credentials"
        
        if ! $SKIP_CONFIRM; then
            read -p "Restore .env files? This will overwrite current configs! (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if ! $DRY_RUN; then
                    cp "$backup_dir/configs/foundry-vtt.env" ../foundry-vtt/.env
                    cp "$backup_dir/configs/monitoring.env" ../monitoring/.env
                    cp "$backup_dir/configs/filebrowser.env" ../filebrowser/.env
                fi
            fi
        fi
    fi
}

# Restore databases
restore_databases() {
    local backup_dir="$1"
    
    log_info "Restoring databases..."
    
    # FileBrowser database
    if [[ -f "$backup_dir/databases/filebrowser.db" ]]; then
        log_info "Restoring FileBrowser database..."
        if $DRY_RUN; then
            log_info "[DRY RUN] Would restore FileBrowser database"
        else
            cp "$backup_dir/databases/filebrowser.db" ../filebrowser/filebrowser.db
        fi
    fi
}

# Cleanup temporary files
cleanup() {
    local extract_dir="/tmp/vtt-stack-restore-$$"
    if [[ -d "$extract_dir" ]]; then
        log_info "Cleaning up temporary files..."
        rm -rf "$extract_dir"
    fi
}

# Main restore process
main() {
    log_info "Starting VTT Stack restore..."
    log_info "Backup source: $BACKUP_SOURCE"
    
    if $DRY_RUN; then
        log_warn "DRY RUN MODE - No changes will be made"
    fi
    
    # Confirmation
    if ! $SKIP_CONFIRM && ! $DRY_RUN; then
        echo
        log_warn "This will OVERWRITE existing data!"
        read -p "Are you sure you want to continue? (yes/no): " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            log_info "Restore cancelled"
            exit 0
        fi
    fi
    
    # Extract and verify backup
    BACKUP_DIR=$(extract_backup "$BACKUP_SOURCE")
    verify_backup "$BACKUP_DIR"
    
    # Stop containers
    stop_containers
    
    # Restore data
    restore_campaigns "$BACKUP_DIR"
    restore_configs "$BACKUP_DIR"
    restore_databases "$BACKUP_DIR"
    
    # Start containers
    start_containers
    
    # Cleanup
    cleanup
    
    log_info "Restore completed successfully!"
    
    if ! $DRY_RUN; then
        log_info "Please verify your data and check container logs:"
        log_info "  docker logs foundry-campaign1"
        log_info "  docker logs foundry-campaign2"
    fi
}

# Handle script interruption
trap cleanup EXIT

# Run main function
main "$@"
