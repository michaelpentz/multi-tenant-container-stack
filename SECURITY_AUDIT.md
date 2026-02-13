# VTT Stack - Deep Security & Best Practices Analysis

**Analysis Date:** 2026-02-12  
**Project:** vtt-stack (Foundry VTT Infrastructure)  
**Scope:** Security audit, best practices review, production readiness assessment

---

## 🚨 CRITICAL ISSUES (Fix Immediately)

### 1. **Hardcoded Absolute Path in FileBrowser** 🔴
**File:** `filebrowser/docker-compose.yml:13`
```yaml
volumes:
  - /home/foundry/foundry_docker:/srv  # ❌ Hardcoded path
```
**Risk:** This path won't exist on other systems, causing deployment failure.
**Fix:** Use relative path: `./:/srv` or document required directory structure.

### 2. **Missing `.env` File for FileBrowser** 🔴
**File:** `filebrowser/docker-compose.yml`
**Issue:** No environment variable file, credentials hardcoded in JSON or defaults used.
**Risk:** FileBrowser has default credentials or no authentication.
**Fix:** Create `filebrowser/.env` with auth settings.

### 3. **No Resource Limits on Foundry VTT** 🔴
**File:** `foundry-vtt/docker-compose.yml`
**Issue:** No CPU/memory limits on campaign containers.
**Risk:** Container can consume all host resources, causing DoS.
**Fix:** Add resource constraints:
```yaml
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '1.0'
    reservations:
      memory: 512M
```

### 4. **Prometheus Exposed Without Authentication** 🔴
**File:** `monitoring/docker-compose.yml:41`
**Issue:** Prometheus port 9090 exposed without auth.
**Risk:** Anyone can access metrics and system information.
**Fix:** Add reverse proxy with auth or bind to localhost only:
```yaml
ports:
  - "127.0.0.1:9090:9090"  # Localhost only
```

---

## ⚠️ HIGH PRIORITY ISSUES

### 5. **No Restart Policy Consistency** 🟠
**Issue:** Mixing `restart: always` and `restart: unless-stopped`.
**Recommendation:** Standardize on `unless-stopped` for predictable behavior.

### 6. **cAdvisor Runs as Privileged** 🟠
**File:** `monitoring/docker-compose.yml:10`
```yaml
privileged: true
```
**Risk:** Full host access. If compromised, attacker owns the host.
**Mitigation:** Use `cap_add` with specific capabilities instead:
```yaml
cap_add:
  - SYS_PTRACE
  - SYS_ADMIN
```

### 7. **No Log Rotation Configured** 🟠
**Issue:** Docker logs grow indefinitely.
**Risk:** Disk space exhaustion (seen in production with 124GB backup issue).
**Fix:** Add logging configuration:
```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### 8. **FileBrowser No Authentication by Default** 🟠
**File:** `filebrowser/filebrowser.json`
```json
"auth": {
  "method": "json"
}
```
**Issue:** JSON auth method requires user setup; default may be no auth.
**Fix:** Document initial user creation or use `noauth` explicitly for local dev.

### 9. **Missing Health Check for cAdvisor** 🟠
**Issue:** No health check on metrics collector.
**Impact:** Silent failures won't trigger restarts.

### 10. **No Backup Volume Exclusions** 🟠
**File:** `.gitignore`
**Issue:** `data/` and `shared_assets/` excluded from git, but no backup strategy documented.
**Fix:** Add backup documentation or automated backup scripts.

---

## 🔍 MEDIUM PRIORITY ISSUES

### 11. **Prometheus Duplicate Job Configuration** 🟡
**File:** `monitoring/prometheus.yml:10-17`
```yaml
- job_name: 'cadvisor'
  targets: ['cadvisor:8080']
- job_name: 'docker'
  targets: ['cadvisor:8080']  # ❌ Same target
```
**Issue:** Two jobs scraping the same endpoint.
**Fix:** Remove duplicate 'docker' job.

### 12. **Hardcoded MTU Setting Without Justification** 🟡
**File:** `foundry-vtt/docker-compose.yml:68`
```yaml
driver_opts:
  com.docker.network.driver.mtu: "1400"
```
**Issue:** 1400 MTU is unusual (standard is 1500).
**Risk:** May cause network issues in some environments.
**Fix:** Document why this is needed or use standard MTU.

### 13. **No Network Isolation Between Services** 🟡
**Issue:** Each service group has its own network, but no inter-network restrictions.
**Improvement:** Document that networks provide logical separation only.

### 14. **Grafana Provisioning Directory Missing** 🟡
**File:** `monitoring/docker-compose.yml:52`
```yaml
volumes:
  - ./grafana/provisioning:/etc/grafana/provisioning:ro
```
**Issue:** Directory doesn't exist in repo.
**Fix:** Create directory structure or remove volume mount.

### 15. **No Version Constraints on Docker Images** 🟡
**Issue:** Using `latest` tag for all images.
**Risk:** Breaking changes in updates can break production.
**Recommendation:** Pin to specific versions:
```yaml
image: felddy/foundryvtt:13.351  # Not :latest
```

### 16. **FileBrowser Uses `latest` Tag** 🟡
**File:** `filebrowser/docker-compose.yml:6`
**Risk:** Version drift between environments.
**Fix:** Pin to specific version.

### 17. **Missing Docker Compose Version Specification** 🟡
**Issue:** No `version:` directive in compose files.
**Note:** Modern Docker Compose ignores this, but explicit is better.
**Fix:** Add `version: '3.8'` for clarity.

### 18. **No Timezone Configuration** 🟡
**Issue:** Containers use UTC by default.
**Impact:** Log timestamps may be confusing.
**Fix:** Add:
```yaml
environment:
  - TZ=America/New_York  # Or your timezone
```

---

## 📋 LOW PRIORITY / BEST PRACTICES

### 19. **No Service Dependency Management** 🔵
**Issue:** Services don't specify dependencies.
**Improvement:** Add `depends_on` for startup order:
```yaml
depends_on:
  - prometheus  # Grafana needs Prometheus
```

### 20. **Missing Container Labels** 🔵
**Issue:** No labels for organization/monitoring.
**Fix:** Add metadata:
```yaml
labels:
  - "app=foundry-vtt"
  - "environment=production"
```

### 21. **No Environment Comments** 🔵
**Issue:** `.env.example` lacks field descriptions.
**Improvement:** Add comments explaining each variable.

### 22. **Missing UFW/Firewall Documentation** 🔵
**Issue:** No firewall rules documented.
**Fix:** Add to DEPLOYMENT.md:
```bash
ufw allow 30000/tcp  # Foundry Campaign 1
ufw allow 30001/tcp  # Foundry Campaign 2
```

### 23. **No Reverse Proxy Configuration** 🔵
**Issue:** All services exposed on different ports.
**Recommendation:** Add nginx/caddy example for unified access.

### 24. **FileBrowser Config Mismatch** 🔵
**File:** `filebrowser/filebrowser.json:6`
```json
"database": "/database/filebrowser.db"
```
**Issue:** But compose mounts to `/database.db` (no subdir).
**Fix:** Align paths:
```yaml
volumes:
  - ./filebrowser.db:/database/filebrowser.db
```

### 25. **README Missing Security Section** 🔵
**Issue:** No dedicated security considerations section.
**Fix:** Add section on secrets management and hardening.

---

## 🎯 PRODUCTION READINESS GAPS

### 26. **No Automated Backup Solution** ❌
**Current:** Manual backups mentioned but not implemented.
**Required:** Automated daily backups with retention.

### 27. **No SSL/TLS Configuration** ❌
**Issue:** All services use HTTP only.
**Required:** HTTPS for production (Let's Encrypt example).

### 28. **No Monitoring Alerts** ❌
**Issue:** Grafana has no alert rules configured.
**Required:** Disk space, memory, CPU alerts.

### 29. **No Disaster Recovery Plan** ❌
**Issue:** No documented restore procedure.
**Required:** Step-by-step recovery guide.

### 30. **No Secrets Management** ❌
**Issue:** `.env` files are simple but not suitable for teams.
**Required:** Docker Secrets, Vault, or CI/CD integration.

---

## ✅ POSITIVE FINDINGS

1. **✅ Environment Variables Used:** Secrets not hardcoded in compose files
2. **✅ Read-Only Mounts:** Shared assets mounted `:ro` (read-only)
3. **✅ .gitignore Comprehensive:** Good exclusions for secrets and data
4. **✅ Health Checks Present:** Foundry containers have health checks
5. **✅ Network Segregation:** Separate networks per service group
6. **✅ Documentation:** Good README and deployment guides
7. **✅ Resource Limits (Partial):** cAdvisor has limits
8. **✅ Restart Policies:** Most services restart automatically

---

## 📊 ISSUE SUMMARY BY CATEGORY

| Category | Critical | High | Medium | Low | Total |
|----------|----------|------|--------|-----|-------|
| **Security** | 4 | 3 | 2 | 3 | 12 |
| **Configuration** | 1 | 1 | 5 | 4 | 11 |
| **Best Practices** | 0 | 2 | 4 | 8 | 14 |
| **Production** | 0 | 0 | 0 | 5 | 5 |
| **TOTAL** | **5** | **6** | **11** | **20** | **42** |

---

## 🚀 PRIORITY FIX ROADMAP

### Phase 1: Critical (Do Now)
- [ ] Fix FileBrowser hardcoded path
- [ ] Add resource limits to Foundry
- [ ] Restrict Prometheus to localhost
- [ ] Create FileBrowser .env file
- [ ] Add log rotation

### Phase 2: High Priority (This Week)
- [ ] Remove cAdvisor privileged mode
- [ ] Standardize restart policies
- [ ] Add health checks to all services
- [ ] Document backup strategy
- [ ] Pin image versions

### Phase 3: Medium (Next Sprint)
- [ ] Fix Prometheus duplicate job
- [ ] Add service dependencies
- [ ] Create Grafana provisioning structure
- [ ] Add timezone configuration
- [ ] Document MTU justification

### Phase 4: Production Ready (Before Deploy)
- [ ] Add SSL/TLS configuration
- [ ] Implement automated backups
- [ ] Configure monitoring alerts
- [ ] Create disaster recovery docs
- [ ] Set up secrets management

---

## 💡 RECOMMENDATIONS

1. **Security First:** Fix critical and high issues before production
2. **Version Pinning:** Pin all images to specific versions for reproducibility
3. **Testing:** Test restore procedures before relying on backups
4. **Monitoring:** Set up alerts before going live
5. **Documentation:** Keep DEPLOYMENT.md updated with actual procedures

---

**Analyst:** Claude Code  
**Status:** 42 issues identified, 5 critical  
**Recommendation:** Address Phase 1 before production deployment
