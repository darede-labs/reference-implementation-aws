# AWS Platform - Clean Foundation

**Branch**: `platform-rebuild-clean`  
**Status**: ✅ Foundation Complete (Phases A, B, C)  
**Date**: 2026-01-23

---

## 📋 What's This?

A **clean, minimal, best-practice** AWS platform foundation built with:
- ✅ **VPC** with 3 AZs, public/private subnets
- ✅ **EKS 1.31** with IRSA
- ✅ **Karpenter** for intelligent node autoscaling
- ✅ **ARM64 Graviton** instances (20% cost savings)
- ✅ **Bootstrap nodes** for platform tools
- ✅ **Full automation** via Makefile + Terraform

**Key Principle**: Simple, reproducible, documented.

---

## 🚀 Quick Start

### Prerequisites
- AWS CLI with profile `darede` configured
- Terraform >= 1.10
- kubectl
- S3 bucket: `poc-idp-tfstate`
- DynamoDB table: `terraform-state-lock`

### Deploy

```bash
# Deploy everything (VPC + EKS + Karpenter)
make install

# Configure kubectl
make configure-kubectl

# Validate
make validate

# Test Karpenter
make test-karpenter
```

**That's it.** You now have a working EKS cluster with intelligent autoscaling.

---

## 📁 Repository Structure

```
.
├── Makefile                 # Deployment automation
├── terraform/
│   ├── vpc/                # VPC module (separate state)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── providers.tf
│   │   └── README.md
│   └── eks/                # EKS + Karpenter module
│       ├── main.tf
│       ├── karpenter.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── karpenter-outputs.tf
│       ├── providers.tf
│       └── README.md
└── docs/
    ├── STATE.md            # Canonical state tracking
    ├── karpenter.md        # Karpenter docs
    └── REBUILD-SUMMARY.md  # What was built
```

---

## 🏗️ Architecture

### VPC
- 3 Availability Zones
- Private subnets (/20) + public subnets (/24)
- Single NAT Gateway (cost-optimized for dev)
- EKS and Karpenter discovery tags

### EKS Cluster
- **Version**: Kubernetes 1.31
- **IRSA**: Enabled (IAM for pods)
- **Endpoint**: Public + Private
- **Logging**: Control plane logs enabled
- **Add-ons**: CoreDNS, VPC-CNI, kube-proxy

### Bootstrap Node Group
- **Purpose**: Hosts Karpenter and core platform tools
- **Instance**: t4g.medium (ARM64 Graviton)
- **Capacity**: 1-2 nodes, on-demand
- **Taint**: `node-role.kubernetes.io/bootstrap=NoSchedule`
- **Why**: Karpenter needs to run IN the cluster to provision nodes (chicken-egg problem)

### Karpenter
- **Version**: 1.0.6
- **Architecture**: ARM64 only (cost optimization)
- **Capacity**: On-demand only (no spot for now)
- **Instance Families**: t, c, m (general purpose + compute)
- **Limits**: Max 100 vCPUs, 200Gi memory
- **Consolidation**: `WhenEmpty` policy (only removes empty nodes)

---

## 🔧 Available Commands

```bash
# Infrastructure
make apply-vpc          # Deploy VPC
make apply-eks          # Deploy EKS + Karpenter
make install            # Deploy everything
make destroy-eks        # Destroy EKS
make destroy-vpc        # Destroy VPC
make destroy            # Destroy everything

# Kubernetes
make configure-kubectl  # Configure kubeconfig
make validate           # Validate cluster
make test-karpenter     # Test Karpenter provisioning
```

---

## 🎯 Design Decisions

### Why ARM64 Graviton?
- 20% better price/performance vs x86
- Good availability
- Supported by all modern platform tools

### Why separate VPC and EKS Terraform?
- Independent lifecycle (VPC can exist without EKS)
- Faster EKS iterations (no VPC recreation)
- Safer destroys (explicit order)

### Why bootstrap node group?
- Karpenter chicken-egg problem: needs to run IN cluster to provision nodes
- Bootstrap provides initial capacity
- Tainted to prevent regular workloads from scheduling here

### Why on-demand only?
- Simpler for dev environment
- No spot interruption handling
- Production can enable spot later

### Why single NAT Gateway?
- Cost optimization for dev
- Production should use `one_nat_gateway_per_az = true`

---

## 📊 Validation

After `make install`, verify:

```bash
# Check nodes (should see 1-2 bootstrap nodes)
kubectl get nodes

# Check Karpenter is running
kubectl get pods -n karpenter
kubectl get nodepool
kubectl get ec2nodeclass

# Test Karpenter provisioning
make test-karpenter
# This creates a test deployment that triggers Karpenter
# Watch Karpenter provision nodes automatically
```

---

## 📚 Documentation

- **[STATE.md](docs/STATE.md)** - Current platform state and progress
- **[REBUILD-SUMMARY.md](docs/REBUILD-SUMMARY.md)** - Complete rebuild summary
- **[karpenter.md](docs/karpenter.md)** - Karpenter deep dive
- **[terraform/vpc/README.md](terraform/vpc/README.md)** - VPC module docs
- **[terraform/eks/README.md](terraform/eks/README.md)** - EKS module docs

---

## 💰 Cost Estimate (Dev Environment)

- **EKS Control Plane**: $73/month
- **Bootstrap Nodes** (1x t4g.medium): ~$25/month
- **Karpenter Nodes**: Variable (only when needed)
- **NAT Gateway**: ~$32/month
- **Total**: ~$130-150/month (base)

**Note**: Karpenter dynamically provisions nodes only when needed, then removes them when empty.

---

## 🔄 What's Next?

Phase C (Karpenter) is complete. Still needed:

- **Phase D**: GitOps base (ArgoCD, ingress-nginx, external-dns, external-secrets)
- **Phase E**: Backstage (developer portal)
- **Phase F**: Cognito authentication
- **Phase G**: Observability (Prometheus, Grafana, Loki)

---

## 🧹 Cleanup

```bash
# Destroy everything (EKS first, then VPC)
make destroy

# Or step by step
make destroy-eks
make destroy-vpc
```

---

## 🤝 Contributing

1. Read [STATE.md](docs/STATE.md) first
2. Create a branch
3. Make changes
4. Test with `make install`
5. Update STATE.md
6. Submit PR

---

## 📝 License

MIT License - see [LICENSE](LICENSE)

---

**Built with best practices, simplicity, and reproducibility in mind.**
