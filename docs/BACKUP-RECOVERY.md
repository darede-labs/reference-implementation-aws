# Backup and Disaster Recovery

## Overview

This document describes backup procedures for the Backstage IDP platform.

## What is Backed Up

### 1. PostgreSQL Database (Backstage Catalog)
- **Location:** backstage-postgresql StatefulSet
- **Data:** User entities, templates, catalog items, relationships
- **Storage:** 8Gi PVC on EBS gp3 (with EBS snapshots)
- **Retention:** Manual backups via scripts

### 2. Terraform State
- **Location:** S3 bucket (poc-idp-tfstate)
- **Protection:** Versioning enabled, encryption at rest
- **Retention:** All versions retained

### 3. GitHub Repositories
- **Location:** github.com/darede-labs/*
- **Protection:** Git version control
- **Retention:** Infinite (Git history)

## Backup Procedures

### Manual PostgreSQL Backup

```bash
# Create backup
./scripts/backup-catalog.sh ./backups

# Output: backups/backstage-catalog-YYYYMMDD_HHMMSS.sql.gz
```

**Backup includes:**
- All catalog entities (users, groups, components, systems, APIs)
- Entity relationships and metadata
- Templates and locations

**Requirements:**
- kubectl access to cluster
- `pg_dump` installed locally
- Network connectivity to cluster

### Automated EBS Snapshots

PostgreSQL data is stored on EBS volume. Configure AWS Backup or DLM for automated snapshots:

```bash
# Create snapshot policy via AWS Console or CLI
aws dlm create-lifecycle-policy \
  --execution-role-arn arn:aws:iam::948881762705:role/AWSDataLifecycleManagerDefaultRole \
  --description "Daily Backstage PostgreSQL snapshots" \
  --state ENABLED \
  --policy-details file://dlm-policy.json \
  --profile darede
```

## Recovery Procedures

### Restore PostgreSQL from Backup

```bash
# Restore from backup file
./scripts/restore-catalog.sh backups/backstage-catalog-YYYYMMDD_HHMMSS.sql.gz

# Restart Backstage
kubectl rollout restart deployment/backstage -n backstage
```

**Recovery Time Objective (RTO):** ~5 minutes
**Recovery Point Objective (RPO):** Time of last backup

### Restore from EBS Snapshot

1. Identify snapshot in AWS Console or CLI
2. Create new volume from snapshot
3. Update PVC to use new volume
4. Restart PostgreSQL StatefulSet

```bash
# List snapshots
aws ec2 describe-snapshots \
  --owner-ids self \
  --filters "Name=tag:Name,Values=*backstage*" \
  --profile darede

# Create volume from snapshot
aws ec2 create-volume \
  --snapshot-id snap-xxxxx \
  --availability-zone us-east-1a \
  --volume-type gp3 \
  --profile darede
```

### Full Disaster Recovery (Complete Cluster Loss)

**Prerequisites:**
- config.yaml file
- AWS credentials (SSO access)
- ACM certificate ARN
- Route53 hosted zone

**Steps:**

1. Clone repository
```bash
git clone https://github.com/darede-labs/reference-implementation-aws
cd reference-implementation-aws
```

2. Restore secrets to AWS Secrets Manager
```bash
# GitHub App credentials (from secure backup)
aws secretsmanager create-secret \
  --name idp-poc-darede-cluster-github-app-credentials \
  --secret-string file://github-app-creds-backup.json \
  --profile darede
```

3. Create cluster
```bash
export AWS_PROFILE=darede
./scripts/create-cluster.sh
```

4. Install platform
```bash
./scripts/install.sh
```

5. Restore catalog
```bash
./scripts/restore-catalog.sh backups/latest-backup.sql.gz
```

**Total Recovery Time:** ~45 minutes

## Backup Best Practices

### Daily Operations
- ✅ Manual backup before major changes
- ✅ Test restore procedure quarterly
- ✅ Store backups in separate AWS region (optional)

### Weekly
- ✅ Verify PostgreSQL PVC health
- ✅ Review backup file sizes for anomalies

### Monthly
- ✅ Full disaster recovery drill
- ✅ Rotate secrets in Secrets Manager
- ✅ Review and cleanup old backups

## Backup Storage

### Local Backups
- **Location:** `./backups/` directory
- **Retention:** Manual cleanup
- **Security:** Do not commit to Git

### S3 Backups (Optional)
```bash
# Upload to S3
aws s3 cp backups/backstage-catalog-*.sql.gz \
  s3://your-backup-bucket/backstage/ \
  --profile darede

# Enable lifecycle policy for retention
```

## Monitoring Backup Health

### Check PostgreSQL PVC
```bash
kubectl get pvc -n backstage
# Verify PVC is Bound and has sufficient space
```

### Check Last Backup Age
```bash
ls -lht backups/ | head -5
# Review last backup timestamp
```

### Validate Backup Integrity
```bash
# Test backup file is readable
gunzip -t backups/backstage-catalog-*.sql.gz
```

## Critical Items NOT Backed Up

⚠️ **The following require manual backup/documentation:**

1. **AWS Resources**
   - Cognito user pool users (backed up via Terraform state)
   - ACM certificates (one-time setup)
   - Route53 hosted zone (DNS delegation)

2. **Kubernetes Secrets**
   - backstage-env-vars secret (reconstructed from config.yaml)
   - GitHub credentials (in AWS Secrets Manager)

3. **External Services**
   - GitHub App configuration (document App ID, permissions)
   - AWS SSO configuration

## Disaster Scenarios and Responses

| Scenario | Detection | Response | RTO |
|----------|-----------|----------|-----|
| Pod crash | Pod not ready | Auto-restart via K8s | < 1 min |
| Database corruption | Query failures | Restore from backup | 5 min |
| PVC failure | Volume errors | Restore from EBS snapshot | 15 min |
| Node failure | Node NotReady | Auto-replace via ASG | 5 min |
| AZ outage | Multi-AZ deployment | Traffic shifts automatically | < 1 min |
| Region outage | Manual detection | Full DR in new region | 45 min |
| Accidental deletion | User report | Restore from backup | 10 min |

## Contact and Escalation

**Platform Team:** DevOps
**Backup Storage:** S3 (future), Local (current)
**Runbook Location:** This document
