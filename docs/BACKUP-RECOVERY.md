# Backup and Disaster Recovery

## Overview

This document describes backup procedures for the Backstage IDP platform using **AWS Backup** native solution.

## What is Backed Up

### 1. Full EKS Cluster (NEW - Comprehensive DR)
- **Location:** Entire EKS cluster
- **Data:**
  - Cluster configuration and settings
  - All Kubernetes resources (Deployments, StatefulSets, ConfigMaps, Secrets, etc.)
  - Persistent volumes (EBS, EFS, S3)
  - Network policies and RBAC
- **Backup Method:** AWS Backup native EKS support
- **Schedule:** Weekly (Sunday 1 AM UTC)
- **Retention:** 90 days
- **Restore Options:** New cluster or existing cluster

### 2. PostgreSQL Database (Backstage Catalog)
- **Location:** backstage-postgresql StatefulSet
- **Data:** User entities, templates, catalog items, relationships
- **Storage:** 8Gi PVC on EBS gp3
- **Backup Method:** AWS Backup (automated)
- **Retention:**
  - Daily backups: 30 days
  - Weekly backups: 90 days

### 3. Terraform State
- **Location:** S3 bucket (poc-idp-tfstate)
- **Protection:** Versioning enabled, encryption at rest
- **Retention:** All versions retained

### 4. GitHub Repositories
- **Location:** github.com/darede-labs/*
- **Protection:** Git version control
- **Retention:** Infinite (Git history)

## Backup Procedures

### AWS Backup (Automated)

**PostgreSQL EBS volumes are automatically backed up via AWS Backup:**

**Daily Backups:**
- Schedule: 3 AM UTC daily
- Retention: 30 days
- Encryption: KMS encrypted
- Start window: 1 hour
- Completion window: 2 hours

**Weekly Backups:**
- Schedule: 2 AM UTC every Sunday
- Retention: 90 days
- Encryption: KMS encrypted
- Long-term retention for compliance

**Check backup status:**
```bash
export AWS_PROFILE=darede

# List recent backups
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --region us-east-1

# Check backup job status
aws backup list-backup-jobs \
  --by-backup-vault-name idp-poc-darede-cluster-backup-vault \
  --region us-east-1
```

**Backup selection:**
- Targets: EBS volumes with tag `kubernetes.io/created-for/pvc/name=data-backstage-postgresql-0`
- Automatic discovery via tags
- No manual intervention required

## Recovery Procedures

### Restore PostgreSQL from AWS Backup

**1. List available recovery points:**
```bash
export AWS_PROFILE=darede

aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --region us-east-1
```

**2. Restore to new EBS volume:**
```bash
# Get recovery point ARN from previous command
RECOVERY_POINT_ARN="arn:aws:backup:us-east-1:948881762705:recovery-point:xxxxx"

# Start restore job
aws backup start-restore-job \
  --recovery-point-arn $RECOVERY_POINT_ARN \
  --metadata "{\"Encrypted\":\"true\",\"VolumeType\":\"gp3\",\"AvailabilityZone\":\"us-east-1a\"}" \
  --iam-role-arn arn:aws:iam::948881762705:role/idp-poc-darede-cluster-backup-role \
  --region us-east-1

# Monitor restore job
aws backup describe-restore-job \
  --restore-job-id <job-id> \
  --region us-east-1
```

**3. Update PVC to use restored volume:**
```bash
# Scale down StatefulSet
kubectl scale statefulset backstage-postgresql -n backstage --replicas=0

# Delete old PVC (data preserved in restored volume)
kubectl delete pvc data-backstage-postgresql-0 -n backstage

# Create new PVC pointing to restored volume ID
# (Manual PV/PVC creation required)

# Scale up StatefulSet
kubectl scale statefulset backstage-postgresql -n backstage --replicas=1
```

**Recovery Time Objective (RTO):** ~15 minutes
**Recovery Point Objective (RPO):**
- Daily backups: Up to 24 hours
- Weekly backups: Up to 7 days

### Full Disaster Recovery (Complete Cluster Loss)

**Prerequisites:**
- config.yaml file
- AWS credentials (SSO access)
- ACM certificate ARN
- Route53 hosted zone
- AWS Backup recovery point ARN

**Steps:**

1. Clone repository
```bash
git clone https://github.com/darede-labs/reference-implementation-aws
cd reference-implementation-aws
export AWS_PROFILE=darede
```

2. Restore secrets to AWS Secrets Manager
```bash
# GitHub App credentials (from secure backup location)
aws secretsmanager create-secret \
  --name idp-poc-darede-cluster-github-app-credentials \
  --secret-string file://github-app-creds-backup.json \
  --region us-east-1
```

3. Create cluster infrastructure
```bash
./scripts/create-cluster.sh
# Wait for cluster ready (~10 minutes)
```

4. Install platform components
```bash
./scripts/install.sh
# Wait for all pods ready (~5 minutes)
```

5. Restore PostgreSQL data from AWS Backup
```bash
# Get latest recovery point
RECOVERY_POINT=$(aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --region us-east-1 \
  --query 'RecoveryPoints[0].RecoveryPointArn' \
  --output text)

# Restore volume and update PVC (see detailed steps above)
```

6. Verify platform functionality
```bash
./scripts/health-check.sh
```

**Total Recovery Time:** ~30 minutes (cluster) + ~15 minutes (data restore) = **~45 minutes**

## Backup Best Practices

### Daily Operations
- ✅ Monitor AWS Backup job status
- ✅ Verify backup completion via SNS notifications
- ✅ Review backup costs in AWS Cost Explorer

### Weekly
- ✅ Check backup vault has recent recovery points
- ✅ Verify PostgreSQL PVC health
- ✅ Review backup metrics in CloudWatch

### Monthly
- ✅ Test restore procedure (quarterly minimum)
- ✅ Full disaster recovery drill
- ✅ Rotate secrets in Secrets Manager
- ✅ Review backup retention policies

## Backup Storage

### AWS Backup Vault
- **Name:** `idp-poc-darede-cluster-backup-vault`
- **Encryption:** KMS encrypted (key rotation enabled)
- **Location:** us-east-1 (same as cluster)
- **Vault Lock:** 7-365 days retention enforcement
- **Notifications:** SNS topic for job status

### Cost Optimization
```bash
# Estimate backup storage costs
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --query 'RecoveryPoints[*].[BackupSizeInBytes,CreationDate]' \
  --region us-east-1 \
  --profile darede

# Cost: ~$0.05/GB/month for EBS snapshots
# Example: 8GB volume = $0.40/month per backup
# Daily (30 retention) + Weekly (4 retention) ≈ $13.60/month
```

## Monitoring Backup Health

### Check Backup Jobs
```bash
export AWS_PROFILE=darede

# Recent backup jobs
aws backup list-backup-jobs \
  --by-backup-vault-name idp-poc-darede-cluster-backup-vault \
  --max-results 10 \
  --region us-east-1

# Failed jobs (last 7 days)
aws backup list-backup-jobs \
  --by-state FAILED \
  --max-results 50 \
  --region us-east-1
```

### Check Recovery Points
```bash
# List all recovery points
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --region us-east-1

# Check most recent backup
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name idp-poc-darede-cluster-backup-vault \
  --query 'RecoveryPoints[0].[RecoveryPointArn,CreationDate,Status]' \
  --region us-east-1
```

### CloudWatch Metrics
```bash
# Backup job success rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Backup \
  --metric-name NumberOfBackupJobsCompleted \
  --dimensions Name=BackupVaultName,Value=idp-poc-darede-cluster-backup-vault \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum \
  --region us-east-1
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
