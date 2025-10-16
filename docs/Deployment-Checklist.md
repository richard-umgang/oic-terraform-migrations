# OIC3 Terraform Migration - Deployment Checklist

Use this checklist for each production deployment to ensure nothing is missed.

---

## Pre-Deployment

### Environment Setup

- [ ] JWT certificates generated for all environments (DEV, TEST, PROD)
- [ ] Confidential applications created in IDCS with JWT configuration
- [ ] Certificates uploaded to IDCS applications
- [ ] Applications assigned to OIC instances with ServiceAdministrator role
- [ ] OAuth credentials tested in all environments
- [ ] OCI Object Storage buckets created
- [ ] Terraform state backend configured (if using remote state)

### Code Review

- [ ] `terraform.tfvars` reviewed and validated
- [ ] Integration IDs verified (format: `CODE|VERSION`)
- [ ] Connection properties validated for each environment
- [ ] Credentials removed from code (using environment variables or Vault)
- [ ] All scripts have execute permissions (`chmod +x scripts/*.sh`)
- [ ] Terraform validated (`make validate`)
- [ ] Code committed to version control

### TEST Environment Validation

- [ ] Integrations exported from DEV successfully
- [ ] Integrations imported to TEST successfully
- [ ] All connection tests pass in TEST
- [ ] Integration tests pass in TEST (`make test ENV=test`)
- [ ] Manual end-to-end testing completed in TEST
- [ ] Performance testing completed (if applicable)
- [ ] Security scan completed (if applicable)

---

## Deployment Planning

### Documentation

- [ ] Deployment plan documented
- [ ] Rollback plan documented
- [ ] Known issues/risks documented
- [ ] Dependencies identified
- [ ] Stakeholders identified and notified

### Approvals

- [ ] Change request created and approved
- [ ] Technical lead approval obtained
- [ ] Business owner approval obtained
- [ ] Security team approval obtained (if required)
- [ ] Maintenance window scheduled
- [ ] Stakeholders notified of deployment window

### Prerequisites

- [ ] All dependent systems available
- [ ] Network connectivity verified
- [ ] External API endpoints accessible
- [ ] Credentials for PROD environment validated
- [ ] Backup of current PROD state created

---

## Deployment Execution

### Pre-Deployment Steps

```bash
# 1. Create backup
make backup ENV=prod

# 2. Verify credentials
./scripts/test-jwt-auth.sh prod

# 3. Review plan
make plan ENV=prod
```

- [ ] Backup created successfully
- [ ] Backup location documented: `_____________________`
- [ ] JWT authentication verified for PROD
- [ ] Terraform plan reviewed and approved
- [ ] Plan shows expected changes only

### Deployment Steps

```bash
# 4. Execute deployment
make import-prod

# When prompted, type: PROD
```

- [ ] Import initiated at: `____:____ (time)`
- [ ] Import completed successfully
- [ ] Deployment logs saved
- [ ] No unexpected errors in logs

### Connection Configuration

```bash
# 5. Verify connections
make test-connections ENV=prod
```

- [ ] All connections configured correctly
- [ ] Connection tests pass
- [ ] Connection properties match requirements

---

## Post-Deployment

### Verification

```bash
# 6. Run smoke tests
make smoke-test ENV=prod

# 7. Run full test suite
make test ENV=prod
```

- [ ] Smoke tests pass
- [ ] Full integration tests pass
- [ ] Test report reviewed: `test_report_prod.html`

### Manual Verification

- [ ] Log into OIC PROD console
- [ ] Verify integrations imported correctly
- [ ] Verify connections show as configured
- [ ] Activate integrations (if not auto-activated)
- [ ] Verify activation successful

### Integration Testing

- [ ] Test critical integration flows manually
- [ ] Verify data flows correctly
- [ ] Check integration monitoring/tracking
- [ ] Verify error handling works
- [ ] Check audit logs

### System Checks

- [ ] OIC instance health checked
- [ ] No errors in OIC logs
- [ ] Connection pool status normal
- [ ] Agent status normal (if using agents)
- [ ] No alerts triggered

---

## Monitoring

### Initial Monitoring (First Hour)

- [ ] Monitor integration executions
- [ ] Check for any errors
- [ ] Review success/failure rates
- [ ] Check response times
- [ ] Verify data throughput

### Extended Monitoring (First 24 Hours)

- [ ] Set up monitoring alerts
- [ ] Review periodic reports
- [ ] Check for any anomalies
- [ ] Verify batch jobs complete
- [ ] Monitor resource utilization

### Monitoring Tools

- [ ] OIC built-in monitoring enabled
- [ ] OCI Monitoring/Logging configured
- [ ] Custom dashboards updated (if any)
- [ ] Alert recipients notified

---

## Documentation

### Deployment Documentation

- [ ] Deployment start time documented: `____:____`
- [ ] Deployment end time documented: `____:____`
- [ ] Deployment duration: `_______ minutes`
- [ ] Integrations deployed (list):
  - [ ] `_________________________`
  - [ ] `_________________________`
  - [ ] `_________________________`

### Issues & Resolutions

- [ ] Any issues encountered documented
- [ ] Resolutions documented
- [ ] Lessons learned captured

### Handover

- [ ] Operations team notified
- [ ] Support team notified
- [ ] Documentation updated
- [ ] Runbooks updated (if applicable)
- [ ] Known issues communicated

---

## Rollback (If Required)

### Rollback Decision

- [ ] Rollback decision made by: `_________________________`
- [ ] Rollback reason documented: `_________________________`
- [ ] Rollback approved by: `_________________________`

### Rollback Execution

```bash
# 1. List available backups
make list-backups

# 2. Restore from backup
make restore ENV=prod DATE=YYYYMMDD-HHMMSS

# Or revert to previous integration versions in OIC console
```

- [ ] Rollback initiated at: `____:____`
- [ ] Previous state restored
- [ ] Integrations verified after rollback
- [ ] Connections verified after rollback
- [ ] System functioning normally

### Post-Rollback

- [ ] Root cause analysis initiated
- [ ] Rollback documented
- [ ] Stakeholders notified
- [ ] Next steps planned

---

## Sign-Off

### Deployment Team

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Deployment Lead | | | |
| Technical Lead | | | |
| QA Lead | | | |

### Approvals

| Role | Name | Approval | Date |
|------|------|----------|------|
| Business Owner | | | |
| Technical Manager | | | |
| Security Team | | | |

---

## Notes

### Deployment Notes

```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```

### Issues Encountered

```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```

### Action Items

```
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
```

---

## Appendix

### Quick Reference

**Useful Commands:**
```bash
# Test authentication
./scripts/test-jwt-auth.sh prod

# List integrations
./scripts/list-integrations.sh prod

# Export from DEV
make export-dev

# Import to PROD
make import-prod

# Run tests
make test ENV=prod

# Create backup
make backup ENV=prod

# List backups
make list-backups

# View logs
make logs
```

### Emergency Contacts

| Role | Name | Contact |
|------|------|---------|
| OIC Admin | | |
| Cloud Admin | | |
| Network Team | | |
| Security Team | | |
| On-Call Support | | |

### Key URLs

- **OIC PROD Console:** `https://___________________________`
- **IDCS Console:** `https://___________________________`
- **OCI Console:** `https://cloud.oracle.com`
- **Object Storage:** `https://___________________________`
- **Documentation:** `https://___________________________`

---

**Deployment Checklist Version:** 1.0  
**Last Updated:** 2024  
**Environment:** PRODUCTION
