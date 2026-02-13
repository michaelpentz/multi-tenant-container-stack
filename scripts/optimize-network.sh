#!/bin/bash

# Network Optimization Script for Foundry VTT Global Access
# Improves TCP performance for high-latency international connections
# Version: 1.0.0

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Run with: sudo $0"
        exit 1
    fi
}

# Backup current sysctl configuration
backup_sysctl() {
    log_step "Backing up current sysctl configuration..."
    
    BACKUP_FILE="/etc/sysctl.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp /etc/sysctl.conf "$BACKUP_FILE"
    log_info "Backup saved to: $BACKUP_FILE"
}

# Apply BBR congestion control
apply_bbr() {
    log_step "Applying BBR congestion control algorithm..."
    
    # Check if BBR is available
    if ! grep -q "tcp_bbr" /proc/modules 2>/dev/null; then
        modprobe tcp_bbr 2>/dev/null || {
            log_warn "BBR module not available, trying to load..."
            echo "tcp_bbr" >> /etc/modules-load.d/bbr.conf
        }
    fi
    
    # Apply BBR settings
    cat >> /etc/sysctl.conf << 'EOF'

# BBR (Bottleneck Bandwidth and RRT) - Google's congestion control
# Better performance on high-latency links
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF
    
    log_info "BBR configuration added"
}

# Optimize TCP settings for WebSocket/long-lived connections
optimize_tcp() {
    log_step "Optimizing TCP settings for Foundry VTT..."
    
    cat >> /etc/sysctl.conf << 'EOF'

# Foundry VTT TCP Optimization for Global Access
# Increase TCP buffer sizes for high-latency connections
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Increase connection tracking for high concurrent users
net.netfilter.nf_conntrack_max = 2000000
net.ipv4.netfilter.ip_conntrack_max = 2000000

# Reduce TCP FIN timeout
net.ipv4.tcp_fin_timeout = 15

# Enable TCP Fast Open
net.ipv4.tcp_fastopen = 3

# Increase local port range
net.ipv4.ip_local_port_range = 1024 65535

# Reduce TIME_WAIT socket duration
net.ipv4.tcp_tw_reuse = 1

# Optimize for high-throughput networks
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_notsent_lowat = 16384

# Disable TCP slow start after idle
net.ipv4.tcp_slow_start_after_idle = 0

# Increase maximum orphan sockets
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_orphan_retries = 1
EOF
    
    log_info "TCP optimization settings applied"
}

# Optimize network interface
optimize_interface() {
    log_step "Optimizing network interface..."
    
    # Find primary network interface
    INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [[ -z "$INTERFACE" ]]; then
        log_warn "Could not detect primary network interface"
        return 1
    fi
    
    log_info "Detected interface: $INTERFACE"
    
    # Increase ring buffer sizes
    ethtool -G "$INTERFACE" rx 4096 tx 4096 2>/dev/null || {
        log_warn "Could not adjust ring buffer sizes (ethtool not available or not supported)"
    }
    
    # Enable offloading features
    ethtool -K "$INTERFACE" tso on gso on gro on 2>/dev/null || {
        log_warn "Could not enable offloading features"
    }
    
    log_info "Network interface optimization completed"
}

# Optimize for Docker networking
optimize_docker_network() {
    log_step "Optimizing Docker networking..."
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found, skipping Docker network optimization"
        return 1
    fi
    
    # Create or update daemon.json
    DAEMON_CONFIG="/etc/docker/daemon.json"
    
    if [[ -f "$DAEMON_CONFIG" ]]; then
        log_info "Backing up existing Docker daemon config..."
        cp "$DAEMON_CONFIG" "${DAEMON_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    cat > "$DAEMON_CONFIG" << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false,
  "experimental": false,
  "mtu": 1400
}
EOF
    
    log_info "Docker daemon configuration updated"
    log_warn "You need to restart Docker for changes to take effect:"
    log_warn "  systemctl restart docker"
}

# Disable IPv6 if not needed (optional)
disable_ipv6() {
    log_step "Configuring IPv6..."
    
    read -p "Disable IPv6? (Not needed for most Foundry setups) [y/N]: " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat >> /etc/sysctl.conf << 'EOF'

# Disable IPv6 (optional)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        log_info "IPv6 disabled"
    else
        log_info "IPv6 left enabled"
    fi
}

# Apply all settings
apply_settings() {
    log_step "Applying all sysctl settings..."
    
    if sysctl -p; then
        log_info "Settings applied successfully"
    else
        log_error "Failed to apply some settings"
        return 1
    fi
}

# Verify optimizations
verify_optimizations() {
    log_step "Verifying optimizations..."
    
    echo
    echo "=== Current Settings ==="
    echo
    
    echo "TCP Congestion Control:"
    sysctl net.ipv4.tcp_congestion_control
    
    echo
    echo "TCP Buffer Sizes:"
    sysctl net.ipv4.tcp_rmem
    sysctl net.ipv4.tcp_wmem
    
    echo
    echo "Core Buffer Sizes:"
    sysctl net.core.rmem_max
    sysctl net.core.wmem_max
    
    echo
    echo "Connection Tracking:"
    sysctl net.netfilter.nf_conntrack_max 2>/dev/null || echo "Not available"
    
    echo
    log_info "Verification complete"
}

# Create monitoring script
create_monitoring_script() {
    log_step "Creating network monitoring script..."
    
    cat > /usr/local/bin/vtt-network-stats.sh << 'EOF'
#!/bin/bash
# Quick network stats for Foundry VTT

echo "=== Foundry VTT Network Stats ==="
echo "Date: $(date)"
echo

echo "=== Active Connections ==="
ss -tin | grep -E ":30000|:30001" | wc -l
echo

echo "=== TCP Connection States ==="
ss -tin | grep -E ":30000|:30001" | awk '{print $1}' | sort | uniq -c | sort -rn
echo

echo "=== Bandwidth Usage (per second) ==="
iftop -t -s 5 2>/dev/null | grep -E "Total|Cumulative" || echo "iftop not installed"
echo

echo "=== Connection Latency (sample) ==="
ss -tin | grep -E ":30000|:30001" | head -5
echo

echo "=== SYN Cookies (DDoS protection) ==="
sysctl net.ipv4.tcp_syncookies
echo
EOF

    chmod +x /usr/local/bin/vtt-network-stats.sh
    log_info "Monitoring script created: /usr/local/bin/vtt-network-stats.sh"
}

# Main function
main() {
    echo "=========================================="
    echo "Foundry VTT Network Optimization"
    echo "=========================================="
    echo
    
    check_root
    backup_sysctl
    apply_bbr
    optimize_tcp
    optimize_interface
    optimize_docker_network
    disable_ipv6
    apply_settings
    verify_optimizations
    create_monitoring_script
    
    echo
    echo "=========================================="
    echo "Optimization Complete!"
    echo "=========================================="
    echo
    log_info "Network optimizations have been applied"
    echo
    echo "Next steps:"
    echo "1. Restart Docker if you changed daemon.json:"
    echo "   sudo systemctl restart docker"
    echo
    echo "2. Monitor network performance:"
    echo "   sudo /usr/local/bin/vtt-network-stats.sh"
    echo
    echo "3. Test with international users"
    echo
    echo "To revert changes:"
    echo "   sudo cp /etc/sysctl.conf.backup.* /etc/sysctl.conf"
    echo "   sudo sysctl -p"
    echo
}

# Run main function
main "$@"
