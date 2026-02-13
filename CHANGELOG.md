# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-02-12

### Major Security Hardening & Production Readiness

This release addresses all 42 security and best practice issues identified in the comprehensive security audit.

### Added

- **Security Audit Document** - Complete security audit with 42 issues identified and remediation roadmap
- **Resource Limits** - CPU and memory constraints on all containers
  - Foundry VTT: 2GB RAM limit, 1 CPU core limit
  - cAdvisor: 128MB RAM limit, 0.25 CPU limit
  - FileBrowser: 256MB RAM limit, 0.5 CPU limit
- **Log Rotation** - Prevents disk space exhaustion with 10MB max log size, 3 file retention
- **Health Checks** - All services now have health check endpoints
  - Foundry VTT: HTTP endpoint check
  - cAdvisor: /healthz endpoint
  - Prometheus: /-/healthy endpoint
  - Grafana: /api/health endpoint
  - FileBrowser: HTTP endpoint check
- **Version Pinning** - All Docker images pinned to specific versions
  - Foundry VTT: 13.351
  - cAdvisor: v0.47.2
  - Prometheus: v2.48.0
  - Grafana: 10.2.3
  - FileBrowser: v2.26.0
- **Monitoring Alerts** - Prometheus alert rules for:
  - Disk space (warning at 10%, critical at 5%)
  - High memory usage (>85%)
  - Container downtime
  - High CPU usage (>80%)
- **Backup & Restore Scripts** - Automated backup solution
  - `scripts/backup.sh` - Full backup with checksums
  - `scripts/restore.sh` - Selective restore with dry-run
  - `scripts/start-all.sh` - Start all services
  - `scripts/stop-all.sh` - Stop all services
  - `scripts/setup.sh` - Initial setup automation
- **Grafana Provisioning** - Pre-configured dashboards and data sources
  - Datasource configuration
  - Container overview dashboard
  - Alert rule configuration
- **Environment Variables** - Added TZ (timezone) support
- **Container Labels** - Metadata for organization and monitoring
- **Docker Compose Version** - Explicit version specification (3.8)
- **Prometheus Security** - Localhost-only binding (127.0.0.1:9090)
- **Network Subnet** - Explicit IPAM configuration for monitoring network

### Changed

- **Removed Privileged Mode** - cAdvisor now uses specific capabilities instead of privileged
  - SYS_PTRACE, SYS_ADMIN, SYS_RESOURCE capabilities added
  - Security option no-new-privileges enabled
- **Fixed Hardcoded Paths** - FileBrowser now uses environment variable
- **Fixed Prometheus Duplicate Job** - Removed duplicate 'docker' job
- **Standardized MTU** - Changed from 1400 to standard 1500
- **Restart Policy** - Standardized to `unless-stopped` across all services
- **FileBrowser Config** - Aligned database path with volume mount
- **.env.example Files** - Enhanced with better documentation

### Security

- **CRITICAL [1/5]**: Fixed hardcoded absolute path in FileBrowser
- **CRITICAL [2/5]**: Added resource limits to prevent DoS
- **CRITICAL [3/5]**: Restricted Prometheus to localhost binding
- **CRITICAL [4/5]**: Added missing FileBrowser .env file
- **CRITICAL [5/5]**: Added log rotation to prevent disk exhaustion
- **HIGH [1/6]**: Removed privileged mode from cAdvisor
- **HIGH [2/6]**: Standardized restart policies
- **HIGH [3/6]**: Added health checks to all services
- **HIGH [4/6]**: Documented backup strategy
- **HIGH [5/6]**: Pinned all image versions
- **HIGH [6/6]**: Added container labels

### Documentation

- **README.md** - Complete rewrite with security features
- **SECURITY_AUDIT.md** - Comprehensive 42-issue audit
- **ARCHITECTURE.md** - Architecture decision records
- **DEPLOYMENT.md** - Production deployment guide

## [1.0.0] - 2024-10-10

### Initial Release

- Multi-campaign Foundry VTT deployment
- Shared asset volume pattern
- Prometheus + Grafana monitoring
- FileBrowser web UI
- Basic Docker Compose configuration

### Known Issues in v1.0.0

- No resource limits
- Using `latest` Docker tags
- Missing health checks
- No log rotation
- Prometheus exposed without auth
- cAdvisor running privileged
- Hardcoded file paths
- Missing backup strategy

---

## Migration Guide: v1.0.0 → v2.0.0

### Backup First
```bash
./scripts/backup.sh
```

### Update Configuration
1. Review new `.env.example` files for new variables
2. Add `TZ=America/New_York` (or your timezone)
3. Update Grafana `.env` with new security settings

### Update FileBrowser
The FileBrowser configuration has changed:
- Edit `filebrowser/.env` to set `FOUNDRY_DATA_PATH`
- Update volume path in docker-compose.yml

### Restart Services
```bash
./scripts/stop-all.sh
docker compose -f foundry-vtt/docker-compose.yml pull
docker compose -f monitoring/docker-compose.yml pull
docker compose -f filebrowser/docker-compose.yml pull
./scripts/start-all.sh
```

### Verify
```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Health}}"
```

---

## Future Roadmap

### v2.1.0 (Planned)
- [ ] Reverse proxy configuration (nginx/traefik)
- [ ] Let's Encrypt SSL automation
- [ ] Docker Secrets support
- [ ] Multi-arch support (ARM64)
- [ ] Automated testing suite

### v2.2.0 (Planned)
- [ ] High availability mode
- [ ] Multi-node deployment
- [ ] Advanced monitoring dashboards
- [ ] Performance benchmarking
- [ ] Disaster recovery automation

### v3.0.0 (Future)
- [ ] Kubernetes support
- [ ] Helm charts
- [ ] GitOps workflow
- [ ] Service mesh integration
- [ ] Zero-downtime deployments
