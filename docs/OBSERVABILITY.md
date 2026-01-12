# Platform Observability

## Overview

This document describes observability, monitoring, and alerting for the Backstage IDP platform.

## Health Check

### Quick Health Check
```bash
./scripts/health-check.sh
```

Validates:
- ✅ Cluster connectivity
- ✅ Core namespaces exist
- ✅ Critical pods running
- ✅ PVCs bound
- ✅ Services available
- ✅ Ingress configured
- ✅ HTTPS endpoint responding
- ✅ Resource limits configured
- ✅ PodDisruptionBudgets present

**Run frequency:** Daily or before/after changes

## Key Metrics to Monitor

### 1. Application Availability
```bash
# Check all pods are running
kubectl get pods -n backstage

# Expected: All pods STATUS=Running, READY=1/1 or 2/2
```

**Alerting threshold:** Any pod not Running for > 5 minutes

### 2. Resource Utilization
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -n backstage
```

**Alerting thresholds:**
- Node CPU > 80% for 15 minutes
- Node Memory > 85% for 15 minutes
- Pod memory approaching limits

### 3. Storage Health
```bash
# PVC status and capacity
kubectl get pvc -n backstage

# Check PVC usage (requires metrics-server)
kubectl exec -n backstage backstage-postgresql-0 -- df -h /bitnami/postgresql
```

**Alerting thresholds:**
- PVC usage > 80%
- PVC not Bound

### 4. Endpoint Health
```bash
# Test Backstage HTTPS
curl -I https://backstage.timedevops.click

# Test Resource API (requires auth)
curl -I -H "X-Backstage-User: user:default/admin" \
  https://backstage.timedevops.click/api/resources/resources
```

**Alerting thresholds:**
- HTTP 5xx errors
- Response time > 5 seconds
- Certificate expiring < 30 days

### 5. Database Connectivity
```bash
# PostgreSQL pod logs
kubectl logs -n backstage backstage-postgresql-0 --tail=50

# Connection test from Backstage
kubectl exec -n backstage deployment/backstage -- \
  pg_isready -h backstage-postgresql -U postgres
```

**Alerting thresholds:**
- Connection failures
- Replication lag (if HA PostgreSQL)
- Slow queries > 10 seconds

## Logging

### Application Logs
```bash
# Backstage logs
kubectl logs -n backstage deployment/backstage -f

# Resource API logs
kubectl logs -n backstage deployment/resource-api -f

# PostgreSQL logs
kubectl logs -n backstage statefulset/backstage-postgresql -f
```

### Log Aggregation
Currently: `kubectl logs` (ephemeral)
Recommended: EFK stack (Elasticsearch, Fluentd, Kibana) or CloudWatch Container Insights

### Critical Log Patterns to Alert On
- `ERROR` - Application errors
- `FATAL` - Application crashes
- `authentication failed` - Security events
- `connection refused` - Connectivity issues
- `out of memory` - Resource exhaustion

## Metrics Collection

### Current State
- ✅ Basic health checks via script
- ✅ Kubernetes native metrics (kubectl top)
- ⚠️ No metrics aggregation
- ⚠️ No historical data

### Recommended: Prometheus + Grafana

#### Install Prometheus
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --timeout 120s
```

#### Key Dashboards to Create
1. **Cluster Overview**
   - Node CPU/Memory
   - Pod count by namespace
   - PVC usage

2. **Backstage Application**
   - Request rate and latency
   - Error rate
   - Active users

3. **PostgreSQL**
   - Connection count
   - Query performance
   - Replication lag

## Alerting

### Current State
- ⚠️ No automated alerting
- ✅ Manual health checks

### Recommended Alerts

#### Critical (Page immediately)
1. **Backstage Down**
   - Condition: All Backstage pods not Ready for > 5 minutes
   - Action: Check pod logs, restart deployment

2. **Database Down**
   - Condition: PostgreSQL pod not Ready
   - Action: Check PVC, node status, restore from backup

3. **Certificate Expiring**
   - Condition: ACM certificate expires < 7 days
   - Action: Renew certificate

4. **Disk Full**
   - Condition: PVC usage > 90%
   - Action: Expand PVC or cleanup data

#### Warning (Investigate during business hours)
1. **High Error Rate**
   - Condition: HTTP 5xx > 5% of requests for 15 minutes
   - Action: Check logs, recent deployments

2. **High Resource Usage**
   - Condition: Pod CPU/Memory > 80% of limits for 30 minutes
   - Action: Consider scaling or increasing limits

3. **Pod Restarts**
   - Condition: Pod restart count > 5 in 1 hour
   - Action: Check for OOMKilled, CrashLoopBackOff

4. **Backup Age**
   - Condition: Last backup > 24 hours old
   - Action: Run manual backup

### Alerting Channels
- **Email:** DevOps team distribution list
- **Slack:** #platform-alerts channel
- **PagerDuty:** For critical alerts (recommended)

## Incident Response

### Backstage Not Responding
```bash
# 1. Check pods
kubectl get pods -n backstage

# 2. Check logs
kubectl logs -n backstage deployment/backstage --tail=100

# 3. Check recent events
kubectl get events -n backstage --sort-by='.lastTimestamp' | tail -20

# 4. Restart if needed
kubectl rollout restart deployment/backstage -n backstage
```

### Database Issues
```bash
# 1. Check PostgreSQL pod
kubectl get pods -n backstage -l app.kubernetes.io/name=postgresql

# 2. Check PVC
kubectl get pvc -n backstage

# 3. Check logs
kubectl logs -n backstage backstage-postgresql-0

# 4. Restore from backup if corrupted
./scripts/restore-catalog.sh backups/latest.sql.gz
```

### Certificate Issues
```bash
# Check certificate in AWS
aws acm describe-certificate \
  --certificate-arn $(kubectl get ingress -n backstage backstage -o jsonpath='{.metadata.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert}') \
  --profile darede
```

### Node Issues
```bash
# Check nodes
kubectl get nodes

# Check node events
kubectl describe node <node-name>

# Drain and replace if unhealthy
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

## Performance Tuning

### Backstage Response Time
**Target:** < 2 seconds for catalog queries

**Optimization:**
1. Increase replica count if CPU-bound
2. Add caching layer (Redis)
3. Optimize database queries
4. Enable CDN for static assets

### Database Performance
**Target:** < 100ms for simple queries

**Optimization:**
1. Add indexes on frequently queried fields
2. Enable query analysis with `pg_stat_statements`
3. Tune PostgreSQL configuration (shared_buffers, work_mem)
4. Consider read replicas for high traffic

## Cost Monitoring

### Current Costs (Approximate)
- EKS cluster: ~$73/month
- EC2 nodes (2x t3.medium): ~$60/month
- EBS volumes: ~$8/month
- NLB: ~$22/month
- Cognito: ~$0-50/month (usage-based)
- **Total:** ~$163-213/month

### Cost Optimization
1. ✅ Use SPOT instances for non-critical workloads
2. ✅ Right-size node types (t3.medium appropriate)
3. ⚠️ Consider Fargate for burstable workloads
4. ⚠️ Enable Compute Savings Plans

### Cost Alerts
```bash
# Set up AWS Budget
aws budgets create-budget \
  --account-id 948881762705 \
  --budget file://budget.json \
  --profile darede
```

## Observability Roadmap

### Phase 1: Baseline (Current)
- ✅ Health check script
- ✅ Manual monitoring via kubectl
- ✅ Basic documentation

### Phase 2: Metrics (Recommended)
- ⏳ Prometheus + Grafana installation
- ⏳ Custom dashboards
- ⏳ Basic alerting

### Phase 3: Advanced (Future)
- ⏳ Distributed tracing (Jaeger/Tempo)
- ⏳ Log aggregation (EFK/CloudWatch)
- ⏳ SLO/SLI tracking
- ⏳ Chaos engineering

## Key Performance Indicators (KPIs)

### Service Level Objectives (SLOs)
| Metric | Target | Measurement |
|--------|--------|-------------|
| Availability | 99.5% | Uptime monitoring |
| Latency (p95) | < 2s | Application metrics |
| Error rate | < 1% | HTTP 5xx / total requests |
| Backup success | 100% | Backup script exit code |

### Business Metrics
- Active users per day
- Templates created per week
- Resources provisioned per month
- Time to provision infrastructure (minutes)

## Troubleshooting Commands

```bash
# Quick diagnostics
kubectl get all -n backstage
kubectl top pods -n backstage
kubectl get events -n backstage --sort-by='.lastTimestamp' | tail -20

# Deep dive
kubectl describe pod <pod-name> -n backstage
kubectl logs <pod-name> -n backstage --previous
kubectl exec -it <pod-name> -n backstage -- /bin/bash

# Network debugging
kubectl run debug --rm -it --image=nicolaka/netshoot -- /bin/bash
```

## Contact Information

**Platform Team:** DevOps
**On-Call Rotation:** See PagerDuty schedule
**Escalation:** CTO
**Runbooks:** This document + BACKUP-RECOVERY.md
