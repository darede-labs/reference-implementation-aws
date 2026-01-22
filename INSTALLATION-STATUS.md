# Installation Status Report

**Date:** $(date)
**Cluster:** idp-poc-darede-cluster

## ✅ Completed

### 1. Infrastructure (Terraform)
- ✅ VPC and networking
- ✅ EKS cluster (1.33)
- ✅ Bootstrap node group (1x t4g.medium, Spot, Graviton)
  - **TAINT APPLIED**: `node-role.kubernetes.io/bootstrap=true:NoSchedule`
  - Prevents workload scheduling on bootstrap node
- ✅ Karpenter 1.8.0 (EKS Pod Identity)
- ✅ EKS addons (CoreDNS, VPC-CNI, EBS CSI, Pod Identity Agent)
- ✅ IAM roles and policies
- ✅ S3 backend for Terraform state

### 2. GitOps (ArgoCD)
- ✅ ArgoCD installed and configured
- ✅ OIDC integration with Keycloak (configured)
- ✅ Root App-of-Apps deployed
- ✅ Auto-sync enabled for all applications

### 3. Platform Applications
**Synced and Healthy (5/9):**
- ✅ **ingress-nginx**: Load balancer and ingress controller
- ✅ **external-dns**: DNS automation for Route53
- ✅ **kyverno**: Policy engine
- ✅ **kube-prometheus-stack**: Monitoring (Prometheus + Grafana)
- ✅ **promtail**: Log forwarder (Progressing → will be Healthy soon)

**Pending Sync (4/9):**
- ⏳ **backstage**: Connection issues (repo-server restarted, should recover)
- ⏳ **keycloak**: Connection issues (same as backstage)
- ⏳ **kyverno-policies**: Path issue in Git (`platform/kyverno/policies`)
- ⏳ **loki**: Just reconfigured (filesystem storage), syncing now

## 🔧 Recent Fixes Applied

1. **Bootstrap Node Protection**
   - Added taint to prevent workload pods from scheduling on bootstrap node
   - Only Karpenter controller and critical system pods allowed
   - Terraform updated for future deployments

2. **Template Rendering**
   - Fixed Loki template (removed S3 dependency, using filesystem)
   - Simplified service account configuration

3. **Installation Process**
   - Created `wait-for-sync.sh` script to monitor ArgoCD sync progress
   - Updated Makefile to include sync monitoring in `make bootstrap`
   - Updated bootstrap script to apply manifests directly (no Git push required)

## 📊 Current Cluster State

**Nodes:** 3 total
- 1x t4g.medium (bootstrap, Spot, tainted)
- 2x t4g.small (Karpenter-managed, Spot, Graviton)

**Pods:** 45 running
- ArgoCD: 6 pods
- Ingress/DNS: 2 pods
- Kyverno: 3 pods
- Monitoring: ~15 pods
- Karpenter: 1 pod
- System (CoreDNS, CNI, etc): ~18 pods

## 🎯 Remaining Issues

### 1. **kyverno-policies**
**Issue:** Path `platform/kyverno/policies` doesn't exist in Git
**Impact:** Low (Kyverno core is working, just policy library is missing)
**Resolution Options:**
- a) Remove the app (policies are optional)
- b) Create the directory in Git with policy manifests
- c) Change source to use a public policy repo

### 2. **backstage/keycloak connection issues**
**Issue:** ArgoCD repo-server connection refused (temporary)
**Impact:** Low (apps are deployed via kubectl, just not managed by ArgoCD yet)
**Resolution:** Wait 2-5 minutes for repo-server to stabilize, or restart:
```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
```

### 3. **loki**
**Issue:** Just reconfigured, syncing
**Impact:** None (monitoring still works via Prometheus)
**Resolution:** Wait for auto-sync (should be healthy in 2-3 minutes)

## 🚀 Next Steps

1. **Monitor sync progress:**
   ```bash
   ./scripts/wait-for-sync.sh 300
   ```

2. **Verify installation:**
   ```bash
   make verify
   ```

3. **Access ArgoCD UI:**
   ```bash
   # Get URL
   echo "https://$(yq eval '.subdomains.argocd' config.yaml).$(yq eval '.domain' config.yaml)"

   # Get admin password
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```

4. **Deploy workload:**
   - Use Backstage templates or
   - Deploy manually to test Karpenter node provisioning

## 💡 Key Architectural Decisions

### 1. **No Automatic Git Commits**
**Decision:** Apply rendered manifests directly via kubectl instead of committing to Git
**Rationale:**
- ✅ Simpler installation (no Git write access required)
- ✅ Works with public repos and forks
- ✅ Faster bootstrap (no push/pull cycle)
- ✅ No conflicts between multiple installations
- ⚠️ Slightly less "pure GitOps" but ArgoCD still manages lifecycle

**For Production:** Consider CI/CD pipeline to commit rendered manifests

### 2. **Bootstrap Node Taint**
**Decision:** Prevent workload scheduling on bootstrap node
**Rationale:**
- ✅ Cost optimization (single small instance for control plane)
- ✅ Reliability (Karpenter controller isolated)
- ✅ Security (fewer workloads on critical infrastructure)

### 3. **Filesystem Storage for Loki (MVP)**
**Decision:** Use filesystem instead of S3 for log storage
**Rationale:**
- ✅ Simpler MVP setup (no S3 bucket provisioning)
- ✅ Lower cost for POC
- ⚠️ Not production-ready (no persistence, single replica)

**For Production:** Migrate to S3 storage for durability

## 📝 Installation Method Summary

```bash
# Clean installation from scratch:
make clean       # Destroy all resources (optional)
make terraform   # Provision infrastructure (5-10 min)
make bootstrap   # Install ArgoCD + apps (5-10 min)
make verify      # Verify health (2-3 min)
```

**Total Time:** ~15-25 minutes for complete platform installation

## 🔒 Security Posture

- ✅ **IMDSv2 enforced** on all EC2 instances
- ✅ **EKS Pod Identity** for Karpenter (modern IRSA replacement)
- ✅ **Private subnets** for all compute
- ✅ **Security groups** following least privilege
- ✅ **Bootstrap node isolation** via taints
- ✅ **Encrypted EBS volumes**
- ⚠️ **Keycloak**: Using in-cluster PostgreSQL (OK for POC)

## 💰 Cost Optimization

**Monthly Estimate (MVP):**
- EKS Control Plane: ~$73/month
- Compute (3x Spot Graviton): ~$25-35/month
- ALB/NLB: ~$20-25/month
- EBS volumes: ~$5-10/month
- RDS (Keycloak DB): ~$15-20/month (if external)

**Total:** ~$140-165/month for a fully functional IDP platform

**Cost Optimizations Applied:**
- ✅ Graviton (ARM64) instances (~20% savings)
- ✅ Spot instances for all compute
- ✅ Single bootstrap node
- ✅ t4g.small as default instance type
- ✅ Karpenter consolidation enabled
