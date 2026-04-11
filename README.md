# multi-tenant-container-stack

Production-ready, security-hardened Docker infrastructure for hosting multiple isolated application instances with shared asset deduplication, comprehensive monitoring, and web-based file management.

## Overview

Multi-tenant container orchestration stack that solves the duplicate storage problem in multi-instance deployments. When running multiple instances of the same application, each typically downloads identical asset libraries (50GB+). This architecture implements a **Read-Once, Write-Many** pattern using Docker bind volumes to deduplicate shared data while maintaining per-tenant isolation.

## Architecture

```
+-----------------------------------------------------------+
|                      Docker Host                          |
|  +-----------------+  +-----------------+                 |
|  |  Tenant 1       |  |  Tenant 2       |                |
|  |  Port: 30000    |  |  Port: 30001    |                |
|  |  Memory: 2GB    |  |  CPU: 1 core    |                |
|  |  /data (isolated)|  |  /data (isolated)|               |
|  +--------+--------+  +--------+--------+                |
|           +--------+----------+                           |
|           |  shared_assets    |                            |
|           |  (read-only)      |                            |
|           +-------------------+                            |
|  +--------------+      +------------------+               |
|  | FileBrowser   |      | Monitoring Stack  |              |
|  | Port: 8080    |      | Prometheus+Grafana|              |
|  +--------------+      +------------------+               |
+-----------------------------------------------------------+
```

## Security Controls

| Feature | Description |
|---------|-------------|
| Resource Limits | CPU and memory constraints on all containers |
| Read-Only Mounts | Shared assets mounted `:ro` to prevent cross-tenant writes |
| Log Rotation | Prevents disk exhaustion from unbounded logging |
| Health Checks | All services monitored for availability |
| Version Pinning | No `latest` tags. Reproducible builds only. |
| Network Isolation | Separate Docker networks per service group |
| No Privileged Mode | cAdvisor uses specific Linux capabilities only |
| Localhost Binding | Prometheus accessible only on localhost |
| Secrets Management | Credentials managed via environment variables |

Full audit: [SECURITY_AUDIT.md](SECURITY_AUDIT.md)

## Monitoring and Alerts

Pre-configured Prometheus + Grafana stack with the following alert rules:

| Alert | Condition | Severity |
|-------|-----------|----------|
| DiskSpaceLow | < 10% free | Warning |
| DiskSpaceCritical | < 5% free | Critical |
| HighMemoryUsage | > 85% | Warning |
| ContainerDown | Unreachable | Critical |
| HighCPUUsage | > 80% | Warning |

## Deployment

```bash
git clone <repo-url>
cd multi-tenant-container-stack

# Configure environment
cp foundry-vtt/.env.example foundry-vtt/.env
cp monitoring/.env.example monitoring/.env
cp filebrowser/.env.example filebrowser/.env

# Set permissions and create tenant directories
mkdir -p foundry-vtt/data/{tenant1,tenant2,shared_assets}
sudo chown -R 1000:1000 foundry-vtt/data/

# Deploy all services
docker compose -f foundry-vtt/docker-compose.yml \
  -f monitoring/docker-compose.yml \
  -f filebrowser/docker-compose.yml up -d
```

## Production Hardening

- **Firewall**: UFW rules restrict access to SSH, HTTP/HTTPS only. Internal service ports sit behind a reverse proxy.
- **SSL/TLS**: Nginx or Traefik reverse proxy with Let's Encrypt certificate automation.
- **Backups**: Automated daily backup script with configurable retention policy.
- **Swarm Mode**: Optional Docker Swarm deployment for high availability.

## Performance (2-CPU, 4GB RAM VPS)

| Metric | Value |
|--------|-------|
| Storage reduction | ~50% via shared asset deduplication |
| Tenant provisioning | 2 minutes per instance |
| Memory usage | ~2GB (all services running) |
| CPU usage | < 25% under load |
| Uptime | 99.9%+ with auto-restart |

## Documentation

- [Architecture Decisions](docs/ARCHITECTURE.md)
- [Deployment Guide](docs/DEPLOYMENT.md)
- [Security Audit](SECURITY_AUDIT.md)
- [Implementation Guide](GLOBAL_IMPLEMENTATION_GUIDE.md)

## License

MIT License. See [LICENSE](LICENSE) for details.

Application software (Foundry VTT) is a trademark of Foundry Gaming LLC. Valid licenses required for the hosted application.
