# Architecture Decision Records

## ADR-001: Shared Volume Pattern for Asset Deduplication

### Status
Accepted

### Context
Running multiple Foundry VTT campaigns requires significant storage for game assets (maps, tokens, audio). Each campaign instance traditionally maintains its own copy of shared resources.

### Problem
- **Storage waste**: 50GB+ assets × N campaigns = exponential growth
- **Update complexity**: Updating assets requires changes in multiple locations
- **Version drift**: Campaigns may use different asset versions

### Decision
Implement a **Shared Read-Only Volume** pattern:
1. Single `shared_assets` directory on host
2. Mounted read-only (`:ro`) into all campaign containers
3. Campaign-specific data remains isolated

### Consequences
**Positive:**
- 50%+ storage reduction
- Single source of truth
- Instant updates across all campaigns
- Simplified backup strategy

**Negative:**
- Requires careful permission management
- Cannot modify assets from within containers
- All campaigns must be compatible with same asset versions

### Implementation
```yaml
volumes:
  - ./shared_assets:/data/shared_assets:ro
```

---

## ADR-002: Monitoring Stack Selection

### Status
Accepted

### Context
Need to monitor container health, resource usage, and application performance across multiple services.

### Decision
Use **cAdvisor + Prometheus + Grafana** stack:
- cAdvisor: Native Docker metrics collection
- Prometheus: Industry-standard TSDB
- Grafana: Flexible visualization

### Rationale
- **Open source**: No licensing costs
- **Docker-native**: First-class container support
- **Extensible**: Easy to add new metrics sources
- **Proven**: Battle-tested in production environments

### Alternatives Considered
- **Datadog**: Excellent but expensive
- **New Relic**: Good APM but overkill for this scale
- **Netdata**: Used as secondary monitoring (lighter weight)

---

## ADR-003: FileBrowser for Asset Management

### Status
Accepted

### Context
Non-technical users (GMs) need to upload/manage game assets without SSH/CLI access.

### Decision
Deploy FileBrowser as web-based file manager.

### Rationale
- **User-friendly**: Web UI accessible to non-technical users
- **Secure**: Built-in authentication
- **Lightweight**: Single binary, minimal resource usage
- **Compatible**: Works with existing directory structure

### Alternatives Considered
- **Nextcloud**: Too heavy, overkill for simple file management
- **SFTP-only**: Too technical for target users
- **Samba**: Windows-focused, harder to secure

---

## ADR-004: Separate Networks per Service Group

### Status
Accepted

### Context
Need network isolation between different service groups (Foundry, Monitoring, File Management).

### Decision
Create separate Docker networks:
- `foundry-net`: Game server communication
- `monitor-net`: Monitoring stack internal
- Default bridge: FileBrowser (isolated)

### Rationale
- **Security**: Services can't communicate unless explicitly allowed
- **Organization**: Logical separation of concerns
- **Performance**: Reduced broadcast traffic
- **Debugging**: Easier to trace network issues

### Implementation
```yaml
networks:
  foundry-net:
    driver: bridge
    driver_opts:
      com.docker.network.driver.mtu: "1400"
```
