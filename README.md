# 🎲 Foundry VTT Infrastructure Stack

> **Professional-grade Docker infrastructure for hosting multiple Foundry VTT game servers with shared asset deduplication, comprehensive monitoring, and web-based file management.**

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Key Features](#key-features)
- [Quick Start](#quick-start)
- [Services](#services)
- [Shared Volume Pattern](#shared-volume-pattern)
- [Monitoring & Observability](#monitoring--observability)
- [Troubleshooting](#troubleshooting)
- [Security Considerations](#security-considerations)
- [Technologies Used](#technologies-used)

---

## 🏗️ Architecture Overview

This infrastructure solves a common problem in game server hosting: **duplicate asset storage**. When running multiple TTRPG campaigns, each typically downloads the same 50GB+ asset library. This architecture implements a **Read-Once, Write-Many** pattern using Docker bind volumes.

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Host                              │
│  ┌─────────────────┐  ┌─────────────────┐                   │
│  │  Campaign 1     │  │  Campaign 2     │                   │
│  │  Port: 30000    │  │  Port: 30001    │                   │
│  │                 │  │                 │                   │
│  │  /data          │  │  /data          │                   │
│  │  (isolated)     │  │  (isolated)     │                   │
│  └────────┬────────┘  └────────┬────────┘                   │
│           │                    │                            │
│           └────────┬───────────┘                            │
│                    │                                         │
│           ┌────────▼────────┐                                │
│           │ shared_assets   │                                │
│           │  /data/shared   │                                │
│           │   (read-only)   │                                │
│           └─────────────────┘                                │
└─────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Features

### 1. **Shared Asset Deduplication** 💾
- **Problem**: Each campaign downloading 50GB+ assets = 100GB+ total
- **Solution**: Single shared volume mounted read-only across all instances
- **Result**: Reduced storage from 100GB to 50GB+minimal overhead

### 2. **Complete Monitoring Stack** 📊
- **cAdvisor**: Real-time container metrics
- **Prometheus**: Time-series data storage
- **Grafana**: Beautiful dashboards and alerts
- **Beszel**: System resource monitoring

### 3. **Web-Based File Management** 📁
- FileBrowser for easy asset upload/download
- No SSH/SCP required for GMs
- Role-based access control

### 4. **Production-Ready Configuration** 🔧
- Health checks on all services
- Automatic restart policies
- Resource limits (CPU/memory)
- Network isolation

---

## 🚀 Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+
- 4GB+ RAM
- 100GB+ free disk space

### 1. Clone and Configure
```bash
git clone <your-repo-url>
cd foundry-vtt-infrastructure

# Copy example configs
cp foundry-vtt/.env.example foundry-vtt/.env
cp monitoring/.env.example monitoring/.env

# Edit with your credentials
nano foundry-vtt/.env
nano monitoring/.env
```

### 2. Start Services
```bash
# Start monitoring stack
cd monitoring && docker compose up -d

# Start Foundry VTT campaigns
cd ../foundry-vtt && docker compose up -d

# Start file manager
cd ../filebrowser && docker compose up -d
```

### 3. Access Services
| Service | URL | Description |
|---------|-----|-------------|
| Campaign 1 | http://localhost:30000 | First game instance |
| Campaign 2 | http://localhost:30001 | Second game instance |
| Grafana | http://localhost:3000 | Metrics dashboards |
| Prometheus | http://localhost:9090 | Raw metrics data |
| FileBrowser | http://localhost:8080 | Asset file manager |

---

## 🔧 Services

### Foundry VTT
Multi-instance game server setup with shared assets.

**Key Configuration:**
- Each campaign has isolated data directory
- Shared assets mounted read-only (`:ro`)
- Separate license keys per instance
- Health checks ensure availability

**Volumes:**
```yaml
volumes:
  - ./data/campaign1:/data           # Isolated campaign data
  - ./shared_assets:/data/shared_assets:ro  # Shared read-only assets
```

### Monitoring Stack

#### cAdvisor
Collects container metrics (CPU, memory, network, disk I/O)
- Resource limits: 128MB RAM, 0.25 CPU
- No exposed ports (internal only)

#### Prometheus
Time-series database for metrics storage
- 15-day retention period
- Scrapes cAdvisor every 15 seconds
- Web UI on port 9090

#### Grafana
Visualization and alerting platform
- Pre-configured dashboards
- Persistent storage for dashboards
- Authentication required

### FileBrowser
Web-based file manager for non-technical users
- Upload/download assets via browser
- No command line required
- User authentication

---

## 💡 Shared Volume Pattern

### The Problem
Running multiple Foundry instances traditionally means:
```
Campaign 1: 50GB assets
Campaign 2: 50GB assets
Total: 100GB+
```

### The Solution
```
Shared Assets: 50GB (one copy)
Campaign 1 Data: ~500MB (world-specific)
Campaign 2 Data: ~500MB (world-specific)
Total: ~51GB
```

### Implementation
```yaml
# All campaigns mount shared assets read-only
volumes:
  - ./shared_assets:/data/shared_assets:ro
```

**Benefits:**
- ✅ 50%+ storage savings
- ✅ Single source of truth for assets
- ✅ Updates apply to all campaigns instantly
- ✅ Prevents version conflicts

---

## 📊 Monitoring & Observability

### Metrics Collected
- **Container Resource Usage**: CPU, memory, network, disk I/O
- **System Metrics**: Load average, disk usage, memory pressure
- **Application Metrics**: Response times, error rates (via Beszel)

### Alerting Rules (Example)
```yaml
# Disk space alert
- alert: DiskSpaceWarning
  expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Disk space is running low"
```

### Dashboards Included
- Container Overview
- Resource Utilization
- Network Traffic
- Disk I/O

---

## 🔍 Troubleshooting

### Issue: "No space left on device"
**Symptoms:**
```
ENOSPC: no space left on device, write
```

**Diagnosis:**
```bash
df -h  # Check disk usage
du -sh /* | sort -h | tail -10  # Find large directories
```

**Solution:**
```bash
# Clean old backups
rm -rf /root/server_backup_*/

# Prune Docker system
docker system prune -a

# Remove unused volumes
docker volume prune
```

**Prevention:**
- Set up automated cleanup jobs
- Monitor disk usage with alerts
- Use log rotation

### Issue: Containers Won't Start
**Check logs:**
```bash
docker logs foundry-campaign1
docker logs foundry-campaign2
```

**Common causes:**
- Port conflicts
- Missing environment variables
- Permission issues on volumes

### Issue: Shared Assets Not Visible
**Check:**
```bash
ls -la /home/foundry/foundry_docker/shared_assets/
docker exec foundry-campaign1 ls -la /data/shared_assets
```

**Fix permissions:**
```bash
sudo chown -R 1000:1000 /path/to/shared_assets
```

---

## 🔐 Security Considerations

### ✅ Implemented
- Environment variables for secrets (not hardcoded)
- Read-only mounts where possible
- Network isolation between services
- Non-root container execution

### ⚠️ TODO / Improvements
- [ ] Use Docker Secrets or external vault
- [ ] Enable HTTPS/TLS for all services
- [ ] Implement fail2ban for SSH
- [ ] Regular security updates
- [ ] Backup encryption

### 🔑 Secrets Management
**Current**: `.env` files
**Recommended**: 
- Docker Secrets (Swarm mode)
- HashiCorp Vault
- AWS Secrets Manager
- 1Password Secrets Automation

---

## 🛠️ Technologies Used

| Technology | Purpose | Version |
|------------|---------|---------|
| Docker | Containerization | 20.10+ |
| Docker Compose | Orchestration | 2.0+ |
| Foundry VTT | Game platform | 13.351 |
| cAdvisor | Container metrics | latest |
| Prometheus | Time-series DB | latest |
| Grafana | Visualization | latest |
| Beszel | System monitoring | latest |
| FileBrowser | File management | latest |

---

## 📈 Performance Metrics

**Real-world usage on 2-CPU, 4GB RAM VPS:**

| Metric | Value |
|--------|-------|
| Storage Saved | ~50GB (50% reduction) |
| Setup Time | 2 minutes vs 2 hours |
| Memory Usage | ~2GB (all services) |
| CPU Usage | <25% during gameplay |
| Uptime | 99.9%+ (auto-restart) |

---

## 🤝 Contributing

This is a showcase project. For production use:
1. Implement proper secrets management
2. Add HTTPS/TLS termination
3. Set up automated backups
4. Configure monitoring alerts
5. Document disaster recovery procedures

---

## 📄 License

This infrastructure setup is provided as-is for educational and showcase purposes.

Foundry VTT is a trademark of Foundry Gaming LLC. You must have valid licenses to use this software.

---

## 🙏 Acknowledgments

- Foundry VTT Community for excellent documentation
- Felddy for the official Docker image
- Grafana Labs for monitoring tools
- Beszel for simple system monitoring

---

**Built with ❤️ for the TTRPG community**
