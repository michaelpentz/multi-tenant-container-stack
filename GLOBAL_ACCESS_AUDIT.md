# Global Access Performance Audit

**Date:** 2026-02-13  
**Scope:** Network performance, latency, buffering, and global accessibility  
**Issue:** Users experiencing action registration delays, potential buffering/DNS issues

---

## 🎯 Executive Summary

Global users experiencing delayed or failed action registration in Foundry VTT. Potential causes include:
- Network latency from geographic distance
- WebSocket buffering/connection instability
- DNS resolution issues
- Insufficient server resources under load
- Module-induced latency
- Lack of CDN for static assets

---

## 🔍 DIAGNOSTIC CHECKLIST

### 1. Network Latency Analysis

**Check current latency from multiple locations:**

```bash
# From the server, check latency to major regions
# Install mtr or use online tools
curl -s https://ipinfo.io/$(curl -s https://ipinfo.io/ip)/json

# Check current connections
ss -tin | grep -E "(30000|30001)" | head -20

# Monitor network performance
docker exec foundry-campaign1 netstat -tin
```

**Expected vs Actual:**
- Local users (same region): < 50ms latency ✅
- Same continent: 50-150ms latency ⚠️
- International: 150-300ms latency ❌
- Trans-oceanic: > 300ms latency 🔴

### 2. WebSocket Connection Health

**Foundry VTT relies heavily on WebSocket connections. Check stability:**

```bash
# Check WebSocket connection count
docker logs foundry-campaign1 --tail 100 | grep -i websocket

# Monitor connection drops
watch -n 5 'docker logs foundry-campaign1 --tail 20 | grep -E "(disconnect|connect|error)"'

# Check for WebSocket ping/pong timeouts
docker logs foundry-campaign1 2>&1 | grep -i "ping\|pong\|timeout"
```

**Common WebSocket Issues:**
- Connection timeouts (default: 30s)
- Buffer overflows during asset sync
- MTU mismatches causing packet fragmentation
- Proxy/firewall WebSocket blocking

### 3. DNS Resolution Performance

**Check DNS resolution times:**

```bash
# Test DNS resolution speed
dig +stats your-domain.com

# Check if using anycast DNS
nslookup -type=ns your-domain.com

# Test from multiple locations using online tools
# https://dnscheck.pingdom.com/
# https://www.whatsmydns.net/
```

**DNS Issues:**
- Slow TTL (Time To Live) settings
- Single point of failure (one DNS server)
- No geographic DNS routing
- DNSSEC overhead

### 4. Bandwidth and Throughput

**Monitor actual bandwidth usage:**

```bash
# Check current bandwidth usage
iftop -i eth0 -f "port 30000 or port 30001"

# Monitor container network stats
docker stats --format "table {{.Name}}\t{{.NetIO}}"

# Check for throttling
dmesg | grep -i throttle
```

**Bandwidth Requirements:**
- Per user (idle): ~10-50 kbps
- Per user (active): ~100-500 kbps
- Per user (asset sync): ~1-5 Mbps
- **Total for 10 users:** 10-50 Mbps recommended

### 5. Server Resource Under Load

**Check if server struggles with concurrent users:**

```bash
# Monitor real-time resource usage
htop

# Check CPU steal (VPS environments)
iostat -x 1 10

# Check memory pressure
free -h && cat /proc/meminfo | grep -i "memavailable\|memfree"

# Check disk I/O (can cause lag)
iotop -o
```

**Resource Bottlenecks:**
- CPU: >80% sustained usage
- Memory: <20% available
- Disk I/O: High await times (>20ms)
- Network: Packet loss >1%

---

## 🛠️ OPTIMIZATION RECOMMENDATIONS

### Immediate Fixes (High Impact)

#### 1. **WebSocket Configuration Optimization**

Update Foundry VTT configuration to handle unstable connections:

```yaml
# Add to foundry-vtt/docker-compose.yml
environment:
  # Increase WebSocket timeout
  - FOUNDRY_WEBSOCKET_PING_INTERVAL=25000
  - FOUNDRY_WEBSOCKET_PONG_TIMEOUT=10000
  
  # Enable compression
  - FOUNDRY_COMPRESS_WEBSOCKET=true
  
  # Increase buffer sizes
  - NODE_OPTIONS="--max-old-space-size=4096"
```

#### 2. **Implement Reverse Proxy with Optimization**

Create `nginx/docker-compose.yml`:

```yaml
version: '3.8'

services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./cache:/var/cache/nginx
    networks:
      - foundry-net
      - monitor-net
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'

networks:
  foundry-net:
    external: true
  monitor-net:
    external: true
```

Create `nginx/nginx.conf`:

```nginx
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging format
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time uct="$upstream_connect_time" '
                    'uht="$upstream_header_time" urt="$upstream_response_time"';

    access_log /var/log/nginx/access.log main;

    # Performance tuning
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=foundry:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=addr:10m;

    # WebSocket optimization
    map $http_upgrade $connection_upgrade {
        default upgrade;
        '' close;
    }

    # Upstream definitions
    upstream foundry_campaign1 {
        server foundry-campaign1:30000;
        keepalive 32;
    }

    upstream foundry_campaign2 {
        server foundry-campaign2:30000;
        keepalive 32;
    }

    # Campaign 1 server
    server {
        listen 80;
        server_name campaign1.yourdomain.com;

        location / {
            limit_req zone=foundry burst=20 nodelay;
            limit_conn addr 10;

            proxy_pass http://foundry_campaign1;
            proxy_http_version 1.1;
            
            # WebSocket support
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            
            # Buffer settings for WebSocket
            proxy_buffering off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            
            # Headers
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Timeouts
            proxy_connect_timeout 60s;
            proxy_buffer_size 4k;
            proxy_buffers 8 4k;
        }

        # Cache static assets
        location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2)$ {
            proxy_pass http://foundry_campaign1;
            expires 1d;
            add_header Cache-Control "public, immutable";
            access_log off;
        }
    }

    # Campaign 2 server
    server {
        listen 80;
        server_name campaign2.yourdomain.com;

        location / {
            limit_req zone=foundry burst=20 nodelay;
            limit_conn addr 10;

            proxy_pass http://foundry_campaign2;
            proxy_http_version 1.1;
            
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            
            proxy_buffering off;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
            
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

#### 3. **MTU Optimization for Global Users**

Update network configuration to handle fragmentation:

```yaml
# In foundry-vtt/docker-compose.yml
networks:
  foundry-net:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: "1400"  # Lower MTU for VPN/tunnel users
    ipam:
      config:
        - subnet: 172.21.0.0/16
```

**Why 1400 MTU?**
- Standard MTU: 1500 bytes
- VPN overhead: ~50-100 bytes
- PPPoE overhead: ~8 bytes
- **Safe global MTU: 1400 bytes** (accommodates most VPNs/tunnels)

#### 4. **Implement TCP Optimization**

Create `scripts/optimize-network.sh`:

```bash
#!/bin/bash
# Network optimization for Foundry VTT global access

# Increase TCP buffer sizes
echo '# Foundry VTT TCP Optimization' >> /etc/sysctl.conf
echo 'net.core.rmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 16777216' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf
echo 'net.core.netdev_max_backlog = 65536' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_notsent_lowat = 16384' >> /etc/sysctl.conf

# Apply settings
sysctl -p

# Verify
sysctl net.ipv4.tcp_congestion_control
```

**BBR (Bottleneck Bandwidth and RRT)** - Google's TCP congestion control algorithm:
- Better performance on high-latency links
- Improved throughput for international users
- Reduced bufferbloat

#### 5. **Module Impact Assessment**

Create monitoring for module-induced lag:

```javascript
// Add to Foundry VTT world script (if accessible)
// Or document for users to add

// Monitor action latency
Hooks.on('preCreateChatMessage', (message, data, options, userId) => {
    console.log(`[LATENCY] Chat message initiated at ${Date.now()}`);
});

Hooks.on('createChatMessage', (message, options, userId) => {
    console.log(`[LATENCY] Chat message completed at ${Date.now()}`);
});

// Monitor dice rolls
Hooks.on('preCreateRoll', (roll, options, userId) => {
    console.log(`[LATENCY] Roll initiated at ${Date.now()}`);
});
```

**Common Module Culprits:**
- **Dice So Nice!** - High GPU usage, network sync issues
- **JitsiRTC** or **LiveKit** - WebRTC overhead
- **Large compendium modules** - Sync delays
- **Automated animation modules** - Client-side lag

**Diagnostic Steps:**
1. Ask users to disable all modules → Test
2. Enable modules one-by-one → Identify culprit
3. Check module configuration for sync settings

### Medium-Term Solutions (Strategic)

#### 6. **Implement CDN for Static Assets**

For shared_assets (maps, tokens, audio), use a CDN:

**Option A: Cloudflare (Free)**
1. Sign up at cloudflare.com
2. Add your domain
3. Enable CDN caching
4. Create Page Rules for static assets:
   - `yourdomain.com/shared_assets/*` → Cache Level: Cache Everything

**Option B: AWS CloudFront**
```bash
# Create S3 bucket for assets
aws s3 mb s3://your-foundry-assets

# Sync assets to S3
aws s3 sync /home/foundry/foundry_docker/shared_assets/ s3://your-foundry-assets/ --acl public-read

# Create CloudFront distribution pointing to S3
# Update Foundry VTT to use CloudFront URLs for assets
```

**Benefits:**
- 50-200ms latency reduction for international users
- Reduced server bandwidth
- Better caching
- DDoS protection

#### 7. **Geographic Load Balancing**

If users are truly global (US, EU, Asia), consider multiple servers:

```
US Server (your current): us.yourdomain.com
EU Server: eu.yourdomain.com  
Asia Server: asia.yourdomain.com
```

**Implementation with GeoDNS:**
- Cloudflare Load Balancer
- AWS Route 53 Geolocation routing
- NS1 or similar DNS services

**Cost:** $50-200/month per additional region

#### 8. **Advanced Monitoring for Global Users**

Add Pingdom or UptimeRobot for global monitoring:

```yaml
# Add to monitoring/docker-compose.yml
services:
  blackbox-exporter:
    image: prom/blackbox-exporter:v0.24.0
    container_name: blackbox-exporter
    restart: unless-stopped
    volumes:
      - ./blackbox.yml:/etc/blackbox_exporter/config.yml:ro
    ports:
      - "9115:9115"
    networks:
      - monitor-net
```

Create `monitoring/blackbox.yml`:

```yaml
modules:
  http_websocket:
    prober: http
    timeout: 10s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: [200, 101]
      method: GET
      headers:
        Upgrade: websocket
        Connection: Upgrade
      fail_if_ssl: false
```

#### 9. **Implement QoS (Quality of Service)**

Prioritize Foundry VTT traffic:

```bash
# Install tc (traffic control)
apt-get install iproute2

# Create QoS rules for Foundry ports
tc qdisc add dev eth0 root handle 1: htb default 12

# Foundry VTT high priority (ports 30000, 30001)
tc class add dev eth0 parent 1: classid 1:1 htb rate 100mbit
tc class add dev eth0 parent 1:1 classid 1:10 htb rate 50mbit ceil 100mbit prio 1
tc filter add dev eth0 protocol ip parent 1:0 prio 1 u32 \
    match ip dport 30000 0xffff flowid 1:10
tc filter add dev eth0 protocol ip parent 1:0 prio 1 u32 \
    match ip dport 30001 0xffff flowid 1:10

# Default lower priority
tc class add dev eth0 parent 1:1 classid 1:12 htb rate 30mbit ceil 100mbit prio 2
```

---

## 📊 MONITORING FOR GLOBAL ACCESS

### Real-Time Latency Dashboard

Create `monitoring/grafana/dashboards/network-latency.json`:

```json
{
  "dashboard": {
    "title": "Global Network Latency",
    "panels": [
      {
        "title": "WebSocket Connection Latency",
        "type": "graph",
        "targets": [
          {
            "expr": "foundry_websocket_latency_seconds",
            "legendFormat": "{{instance}}"
          }
        ]
      },
      {
        "title": "Active Connections by Region",
        "type": "table",
        "targets": [
          {
            "expr": "sum by (country) (foundry_active_connections)",
            "format": "table"
          }
        ]
      }
    ]
  }
}
```

### Alert Rules for Global Performance

Add to `monitoring/alert-rules.yml`:

```yaml
groups:
  - name: global-performance
    interval: 30s
    rules:
      - alert: HighWebSocketLatency
        expr: foundry_websocket_latency_seconds > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High WebSocket latency detected"
          description: "WebSocket latency is {{ $value }}s for {{ $labels.instance }}"
          
      - alert: WebSocketDisconnections
        expr: rate(foundry_websocket_disconnections_total[5m]) > 0.1
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "WebSocket disconnection rate is high"
          description: "{{ $value }} disconnections per second"
          
      - alert: SlowAssetLoading
        expr: foundry_asset_load_time_seconds > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Assets loading slowly"
          description: "Asset load time is {{ $value }}s"
```

---

## 🧪 TESTING PROCEDURES

### Test 1: WebSocket Stability Test

```bash
# Install wscat
npm install -g wscat

# Test WebSocket connection
wscat -c ws://yourserver:30000/socket.io/?EIO=3&transport=websocket

# Send test messages and measure response time
```

### Test 2: Global Latency Test

Use online tools:
- https://www.pingdom.com/ (test from multiple locations)
- https://gtmetrix.com/ (page load performance)
- https://www.webpagetest.org/ (detailed waterfall)

### Test 3: Module Performance Test

```bash
# Create benchmark world with no modules
# Invite 5+ users from different regions
# Monitor:
# - Action response time
# - Dice roll latency
# - Asset loading time
# - WebSocket disconnection rate

# Compare with modules enabled/disabled
```

---

## 💡 IMMEDIATE ACTION PLAN

### Today (15 minutes)
1. ✅ Check current WebSocket logs for errors
2. ✅ Verify server isn't resource-constrained
3. ✅ Test latency from problem user locations

### This Week (2-4 hours)
1. ✅ Implement nginx reverse proxy with WebSocket optimization
2. ✅ Lower MTU to 1400 for VPN compatibility
3. ✅ Apply TCP optimization (BBR)
4. ✅ Set up better monitoring

### This Month (8-16 hours)
1. ✅ Implement CDN for static assets
2. ✅ Document module troubleshooting for users
3. ✅ Set up geographic monitoring
4. ✅ Consider regional servers if user base justifies it

---

## 📋 USER TROUBLESHOOTING GUIDE

### For Players Experencing Lag

**Step 1: Check Their Connection**
```
1. Run speed test: https://www.speedtest.net/
2. Minimum: 5 Mbps down, 1 Mbps up
3. Latency to server: < 300ms acceptable
```

**Step 2: Disable Modules**
```
1. Disable all modules
2. Test basic functionality
3. Enable modules one-by-one
4. Report problematic module
```

**Step 3: Browser Optimization**
```
1. Use Chrome or Firefox (not Safari/Edge)
2. Disable browser extensions
3. Clear cache and cookies
4. Try Incognito/Private mode
```

**Step 4: Network Optimization**
```
1. Use wired connection (not WiFi)
2. Close other bandwidth-heavy apps
3. Disable VPN if possible
4. Try different DNS (8.8.8.8, 1.1.1.1)
```

---

## 🎯 SUCCESS METRICS

After implementing fixes, monitor for:

| Metric | Before | Target | Status |
|--------|--------|--------|--------|
| WebSocket disconnections/hour | ? | < 5 | ⬜ |
| Average action latency | ? | < 200ms | ⬜ |
| Asset load time | ? | < 5s | ⬜ |
| User complaints/week | ? | < 2 | ⬜ |
| Global availability | ? | > 99% | ⬜ |

---

## 📞 SUPPORT ESCALATION

**Level 1 - Basic**
- Check server resources
- Review recent logs
- Verify network connectivity

**Level 2 - Advanced**
- WebSocket debugging
- Module isolation testing
- Network optimization

**Level 3 - Infrastructure**
- CDN implementation
- Regional server deployment
- Advanced load balancing

---

## 🔮 FUTURE CONSIDERATIONS

- **HTTP/3 (QUIC)** - Better performance over high-latency links
- **Edge Computing** - Deploy Foundry instances closer to users
- **AI-Powered Optimization** - Predict and pre-cache assets
- **WebTransport** - Next-gen replacement for WebSocket

---

**Next Step:** Start with **nginx reverse proxy** and **MTU optimization** - these provide the highest impact for global users.
