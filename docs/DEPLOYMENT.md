# Deployment Guide

## Production Deployment Checklist

### Pre-Deployment

- [ ] Server specifications verified (CPU/RAM/Disk)
- [ ] Domain names registered and DNS configured
- [ ] SSL certificates obtained (Let's Encrypt recommended)
- [ ] Firewall rules configured (ports 30000, 30001, 3000, 9090, 8080, 22)
- [ ] Backup strategy defined

### Security Setup

#### 1. Create Non-Root User
```bash
useradd -m -s /bin/bash foundryadmin
usermod -aG docker foundryadmin
```

#### 2. Configure SSH
```bash
# Disable root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

systemctl restart sshd
```

#### 3. Set Up Firewall
```bash
# UFW example
ufw default deny incoming
ufw allow 22/tcp    # SSH
ufw allow 30000/tcp # Foundry Campaign 1
ufw allow 30001/tcp # Foundry Campaign 2
ufw allow 3000/tcp  # Grafana
ufw allow 8080/tcp  # FileBrowser
ufw enable
```

### Installation Steps

#### Step 1: Install Docker
```bash
# Update system
apt-get update && apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Add user to docker group
usermod -aG docker $USER
newgrp docker
```

#### Step 2: Create Directory Structure
```bash
mkdir -p /opt/foundry-infrastructure/{foundry-vtt,monitoring,filebrowser}
mkdir -p /opt/foundry-infrastructure/foundry-vtt/{data/campaign1,data/campaign2,shared_assets}
```

#### Step 3: Set Permissions
```bash
# Create foundry user (UID 1000 matches container)
useradd -u 1000 -m foundry

# Set ownership
chown -R 1000:1000 /opt/foundry-infrastructure/foundry-vtt/
```

#### Step 4: Configure Environment
```bash
cd /opt/foundry-infrastructure

# Create .env files
cp foundry-vtt/.env.example foundry-vtt/.env
cp monitoring/.env.example monitoring/.env

# Edit configurations
nano foundry-vtt/.env
nano monitoring/.env
```

#### Step 5: Deploy Services
```bash
# Start monitoring first (dependency for metrics)
cd /opt/foundry-infrastructure/monitoring
docker compose up -d

# Start Foundry campaigns
cd /opt/foundry-infrastructure/foundry-vtt
docker compose up -d

# Start file manager
cd /opt/foundry-infrastructure/filebrowser
docker compose up -d
```

#### Step 6: Verify Deployment
```bash
# Check all containers are running
docker ps

# Check logs for errors
docker logs foundry-campaign1
docker logs foundry-campaign2

# Test endpoints
curl http://localhost:30000
curl http://localhost:30001
```

### Post-Deployment

#### Initial Setup
1. **Access Foundry VTT**
   - Navigate to http://your-server:30000
   - Enter admin key from .env file
   - Set up world and configure modules

2. **Configure Grafana**
   - Navigate to http://your-server:3000
   - Login with credentials from .env
   - Import dashboards from ./grafana/dashboards

3. **Upload Assets**
   - Access FileBrowser at http://your-server:8080
   - Login and navigate to shared_assets
   - Upload maps, tokens, audio files

#### Monitoring Setup
```bash
# Set up cron job for disk monitoring
echo "0 */6 * * * /opt/foundry-infrastructure/scripts/check-disk-space.sh" | crontab -

# Enable Docker auto-restart
systemctl enable docker
```

### Backup Strategy

#### Automated Daily Backup
```bash
# Create backup script
cat > /opt/backup/backup-foundry.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/$(date +%Y-%m-%d)"
mkdir -p "$BACKUP_DIR"

# Backup data directories
tar czf "$BACKUP_DIR/campaign1.tar.gz" -C /opt/foundry-infrastructure/foundry-vtt/data/campaign1 .
tar czf "$BACKUP_DIR/campaign2.tar.gz" -C /opt/foundry-infrastructure/foundry-vtt/data/campaign2 .
tar czf "$BACKUP_DIR/shared_assets.tar.gz" -C /opt/foundry-infrastructure/foundry-vtt/shared_assets .

# Backup configs
cp /opt/foundry-infrastructure/*/.env "$BACKUP_DIR/"
cp /opt/foundry-infrastructure/*/docker-compose.yml "$BACKUP_DIR/"

# Upload to remote storage (AWS S3 example)
# aws s3 sync "$BACKUP_DIR" s3://your-backup-bucket/foundry-backups/

# Clean old backups (keep 7 days)
find /backups -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod +x /opt/backup/backup-foundry.sh

# Add to cron (daily at 2 AM)
echo "0 2 * * * /opt/backup/backup-foundry.sh" | crontab -
```

### SSL/TLS Setup (Recommended)

#### Using Nginx Reverse Proxy + Let's Encrypt
```yaml
# docker-compose.yml addition
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    depends_on:
      - campaign1
      - campaign2
      - grafana
```

```nginx
# nginx.conf snippet
server {
    listen 443 ssl;
    server_name foundry1.yourdomain.com;
    
    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;
    
    location / {
        proxy_pass http://campaign1:30000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

### Troubleshooting Production Issues

#### High Memory Usage
```bash
# Check memory usage by container
docker stats --no-stream

# Set memory limits in docker-compose.yml
deploy:
  resources:
    limits:
      memory: 1G
```

#### Disk Space Issues
```bash
# Monitor disk usage
df -h

# Find large files
du -sh /* 2>/dev/null | sort -h | tail -20

# Clean Docker
docker system prune -a --volumes
```

#### Network Issues
```bash
# Check container connectivity
docker network inspect foundry-net

# Test port binding
netstat -tlnp | grep 30000
```

### Rollback Procedure

If deployment fails:
```bash
# Stop all containers
docker compose down

# Restore from backup
cd /opt/foundry-infrastructure
tar xzf /backups/2024-01-01/campaign1.tar.gz -C foundry-vtt/data/campaign1

# Restart
docker compose up -d
```
