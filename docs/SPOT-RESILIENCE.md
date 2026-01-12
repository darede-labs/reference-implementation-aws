# SPOT Instance Resilience

## Overview

This platform supports AWS EC2 SPOT instances for cost optimization (~70% savings vs On-Demand).

## Current Configuration

**Node Group Settings:**
- Instance types: Configurable via `config.yaml` (node_groups.instance_types)
- Capacity type: `SPOT` or `ON_DEMAND` (config.yaml: node_groups.capacity_type)
- Min/Max/Desired: Configurable scaling (config.yaml: node_groups.min/max/desired)

**To enable SPOT:**
```yaml
node_groups:
  capacity_type: "SPOT"  # Change from ON_DEMAND
  instance_types:
    - "t3.medium"
    - "t3a.medium"  # Add multiple types for diversification
```

## How SPOT Works

### SPOT Interruptions
- AWS can reclaim SPOT instances with 2-minute warning
- Interruption rate: ~5% (varies by instance type and AZ)
- Notification: EC2 Instance Metadata Service (IMDS)

### Kubernetes Response
When AWS sends interruption notice:
1. Node marked as `Unschedulable` (cordoned)
2. Pods receive SIGTERM (30s grace period)
3. Pods rescheduled to healthy nodes
4. Node terminated after drain completes

## Resilience Best Practices

### ✅ Already Implemented

1. **Multiple Replicas**
   - Backstage: 2 replicas
   - Resource API: 2 replicas
   - Ensures service continuity during interruptions

2. **PodDisruptionBudgets**
   - Backstage PDB: minAvailable=1
   - Resource API PDB: minAvailable=1
   - Ingress controller PDB: minAvailable=1
   - Prevents all replicas being evicted simultaneously

3. **Resource Limits**
   - All pods have requests/limits defined
   - Enables proper bin-packing and fast rescheduling

4. **Multi-AZ Deployment**
   - Cluster spans 3 availability zones
   - Reduces correlated interruptions

### ⚠️ Recommended Additions

1. **Cluster Autoscaler**
   - Automatically adjusts node count based on demand
   - Already tagged in Terraform (k8s.io/cluster-autoscaler)

   ```bash
   helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
     --namespace kube-system \
     --set autoDiscovery.clusterName=idp-poc-darede-cluster \
     --set awsRegion=us-east-1 \
     --timeout 120s
   ```

2. **AWS Node Termination Handler**
   - Gracefully handles SPOT interruptions
   - Drains nodes before termination

   ```bash
   helm upgrade --install aws-node-termination-handler \
     eks/aws-node-termination-handler \
     --namespace kube-system \
     --set enableSpotInterruptionDraining=true \
     --set enableScheduledEventDraining=true \
     --timeout 120s
   ```

3. **SPOT Instance Diversification**
   - Use multiple instance types to reduce interruption correlation
   - Example: `["t3.medium", "t3a.medium", "t2.medium"]`

## Testing SPOT Resilience

### Simulate Interruption
```bash
# Cordon node (simulate interruption warning)
kubectl cordon <node-name>

# Drain node (simulate graceful shutdown)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Verify pods rescheduled
kubectl get pods -n backstage -o wide

# Verify no service disruption
./scripts/health-check.sh
```

### Expected Behavior
- ✅ Pods rescheduled to other nodes within 30 seconds
- ✅ No HTTP 503 errors (PDB ensures availability)
- ✅ Backstage remains accessible throughout
- ✅ New node joins cluster automatically (if Cluster Autoscaler enabled)

## Cost Optimization Strategy

### Hybrid Approach (Recommended)
```yaml
# Production workloads: ON_DEMAND
node_groups:
  production:
    capacity_type: "ON_DEMAND"
    min_size: 2
    max_size: 4
    labels:
      workload: "production"
    taints:
      - key: "production"
        value: "true"
        effect: "NoSchedule"

  # Burst capacity: SPOT
  spot:
    capacity_type: "SPOT"
    min_size: 0
    max_size: 10
    labels:
      workload: "burst"
```

### Current Cost (All ON_DEMAND)
- 2x t3.medium: ~$60/month
- EKS control plane: $73/month
- **Total compute:** $133/month

### Optimized Cost (SPOT)
- 2x t3.medium SPOT: ~$18/month (70% savings)
- EKS control plane: $73/month
- **Total compute:** $91/month
- **Savings:** $42/month (32% total cost reduction)

## Monitoring SPOT Events

### Check Interruption Rate
```bash
# List recent interruptions
aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=closed" \
  --query 'SpotInstanceRequests[*].[InstanceId,Status.Message,CreateTime]' \
  --profile darede
```

### Watch Node Drains
```bash
# Monitor events
kubectl get events -n kube-system --watch | grep -i "drain\|evict\|spot"
```

### Alert on High Interruption Rate
**Metric:** Node replacements > 2 per hour
**Action:** Consider switching to ON_DEMAND or diversifying instance types

## StatefulSet Considerations

### PostgreSQL on SPOT (Current)
- ⚠️ **Risk:** Data volume attached to specific node
- **Current state:** 8Gi PVC on EBS (node-affinity bound)
- **Impact if interrupted:** Pod cannot reschedule until volume detaches

### Mitigation Options

**Option 1: Keep PostgreSQL on ON_DEMAND (Recommended)**
```yaml
# Add node selector to PostgreSQL
nodeSelector:
  workload: production

# Or use taints/tolerations
tolerations:
  - key: "production"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

**Option 2: Use RDS instead**
- Managed PostgreSQL (no SPOT interruption risk)
- Automated backups and high availability
- ~$30-50/month additional cost

**Option 3: Accept Brief Downtime**
- Current setup already has persistent data (PVC)
- Interruption causes ~2-5 minute pod reschedule delay
- Acceptable for development/staging environments

## Runbook: SPOT Interruption Response

### Detection
```bash
# Node becomes NotReady
kubectl get nodes | grep NotReady

# Or via events
kubectl get events --all-namespaces | grep -i spot
```

### Validation
```bash
# Check if pods rescheduled
kubectl get pods -n backstage -o wide

# Check service availability
./scripts/health-check.sh

# Check for stuck pods
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

### Recovery (Automatic)
- Kubernetes automatically reschedules pods
- Cluster Autoscaler provisions new node if needed
- No manual intervention required

### Recovery (Manual - if stuck)
```bash
# Force delete stuck pod
kubectl delete pod <pod-name> -n backstage --force --grace-period=0

# Scale up nodes if autoscaler not installed
aws eks update-nodegroup-config \
  --cluster-name idp-poc-darede-cluster \
  --nodegroup-name <nodegroup-name> \
  --scaling-config desiredSize=4 \
  --profile darede
```

## Best Practices Summary

| Practice | Status | Impact |
|----------|--------|--------|
| Multiple replicas | ✅ Implemented | High |
| PodDisruptionBudgets | ✅ Implemented | High |
| Resource limits | ✅ Implemented | Medium |
| Multi-AZ deployment | ✅ Implemented | High |
| Cluster Autoscaler | ⏳ Recommended | Medium |
| Node Termination Handler | ⏳ Recommended | Medium |
| Instance diversification | ⏳ Optional | Low |
| StatefulSet on ON_DEMAND | ⏳ Recommended | High |

## References

- [AWS SPOT Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [EKS SPOT Workshop](https://ec2spotworkshops.com/using_ec2_spot_instances_with_eks.html)
- [Cluster Autoscaler on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md)
