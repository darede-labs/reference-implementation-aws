# Terraform Configuration via config.yaml

## 📋 Overview

All Terraform infrastructure configuration is now **centralized in `config.yaml`** at the repository root.

**No more Terraform variables or CLI arguments needed!** Just edit `config.yaml` and run `terraform apply`.

---

## 🎯 What's Configurable

### 1. **EKS Cluster**
```yaml
cluster_name: "idp-poc-cluster"
region: "us-east-1"
auto_mode: "false"  # true = EKS Auto Mode, false = Standard Mode
```

### 2. **Node Groups** (only when `auto_mode: false`)
```yaml
node_groups:
  # SPOT = 70% cheaper, ON_DEMAND = more reliable
  capacity_type: "SPOT"

  # Multiple types improve Spot availability
  instance_types:
    - "t3.medium"
    - "t3a.medium"
    - "t2.medium"

  # Auto Scaling
  scaling:
    min_size: 2
    max_size: 6
    desired_size: 2

  # Disk size per node (GB)
  disk_size: 50

  # Labels for pod scheduling
  labels:
    pool: "spot"
    workload: "general"
```

**Recommended instance types by use case:**

| Use Case | Instance Families | Sizes |
|----------|------------------|-------|
| **General workloads** | t3, t3a, t2, m5, m6i | medium, large |
| **Compute intensive** | c5, c6i | large, xlarge |
| **Memory intensive** | r5, r6i | large, xlarge |
| **Dev/Staging (cost-optimized)** | t3a, t2 | medium, large |
| **Production (balanced)** | m5, m6i | large, xlarge |

### 3. **VPC Configuration**

#### Option A: Create New VPC
```yaml
vpc:
  mode: "create"
  cidr: "10.0.0.0/16"
  availability_zones: 3  # 2 for dev, 3 for prod

  # NAT Gateway cost: single = $32/month, one_per_az = $96/month (3 AZs)
  nat_gateway_mode: "single"  # or "one_per_az" for HA
```

#### Option B: Use Existing VPC
```yaml
vpc:
  mode: "existing"
  vpc_id: "vpc-0abc123def456"
  private_subnet_ids:
    - "subnet-0abc111"
    - "subnet-0abc222"
    - "subnet-0abc333"
  public_subnet_ids:
    - "subnet-0def111"
    - "subnet-0def222"
    - "subnet-0def333"
```

### 4. **Domain and DNS**
```yaml
domain: "timedevops.click"
route53_hosted_zone_id: "Z09212782MXWNY5EYNICO"

# Subdomain routing: argocd.timedevops.click
subdomains:
  argocd: "argocd"
  backstage: "backstage"
  keycloak: "keycloak"

# Path routing: timedevops.click/argocd
path_routing: "false"  # Set to "true" for path-based routing
```

### 5. **Tags**
```yaml
tags:
  githubRepo: "github.com/darede-labs/reference-implementation-aws"
  env: "poc"
  project: "idp"
  owner: "platform-team"
  cost-center: "engineering"
```

---

## 🚀 Usage

### 1. Edit Configuration
```bash
# Edit the config file
nano ../../config.yaml
```

### 2. Initialize Terraform
```bash
cd cluster/terraform
terraform init
```

### 3. Plan Changes
```bash
# No variables needed!
terraform plan
```

### 4. Apply Infrastructure
```bash
terraform apply
```

### 5. Destroy (when done)
```bash
terraform destroy
```

---

## 💡 Examples

### Example 1: Dev Cluster (Cost-Optimized)
```yaml
cluster_name: "dev-cluster"
region: "us-east-1"
auto_mode: "false"

node_groups:
  capacity_type: "SPOT"
  instance_types: ["t3a.medium", "t2.medium"]
  scaling:
    min_size: 2
    max_size: 4
    desired_size: 2
  disk_size: 50

vpc:
  mode: "create"
  cidr: "10.0.0.0/16"
  availability_zones: 2
  nat_gateway_mode: "single"  # Save $64/month vs 2 NAT Gateways
```

**Monthly cost:** ~$91 (EKS $73 + Spot $18)

---

### Example 2: Production Cluster (HA)
```yaml
cluster_name: "prod-cluster"
region: "us-east-1"
auto_mode: "false"

node_groups:
  capacity_type: "ON_DEMAND"  # More reliable
  instance_types: ["m5.large", "m6i.large"]
  scaling:
    min_size: 3
    max_size: 10
    desired_size: 3
  disk_size: 100

vpc:
  mode: "create"
  cidr: "10.0.0.0/16"
  availability_zones: 3
  nat_gateway_mode: "one_per_az"  # High availability
```

**Monthly cost:** ~$343 (EKS $73 + 3× m5.large $168 + 3× NAT $96 + misc $6)

---

### Example 3: Use Existing VPC
```yaml
cluster_name: "shared-cluster"
region: "us-east-1"
auto_mode: "false"

vpc:
  mode: "existing"
  vpc_id: "vpc-0abc123def456"
  private_subnet_ids: ["subnet-111", "subnet-222", "subnet-333"]
  public_subnet_ids: ["subnet-aaa", "subnet-bbb", "subnet-ccc"]

node_groups:
  capacity_type: "SPOT"
  instance_types: ["t3.medium", "t3a.medium"]
  scaling:
    min_size: 2
    max_size: 6
    desired_size: 2
  disk_size: 50
```

**Benefit:** No NAT Gateway cost if VPC already has one

---

## 📊 Cost Optimization Tips

### 1. **Use SPOT Instances**
- **Savings:** 70% vs On-Demand
- **Best for:** Dev, staging, stateless workloads
- **Config:** `capacity_type: "SPOT"`

### 2. **Right-size Instances**
- Start with `t3.medium` (2 vCPU, 4GB RAM)
- Scale up only if needed
- Use multiple types for better Spot availability

### 3. **Optimize NAT Gateway**
- **Single NAT:** $32/month (dev/staging)
- **One per AZ:** $96/month for 3 AZs (production HA)
- **Config:** `nat_gateway_mode: "single"`

### 4. **Reduce AZs for Dev**
- **2 AZs:** Enough for dev/staging
- **3 AZs:** Recommended for production
- **Config:** `availability_zones: 2`

### 5. **Smaller Disk for Dev**
- **50 GB:** Sufficient for most workloads
- **100 GB:** For data-heavy applications
- **Config:** `disk_size: 50`

---

## 🔧 Migration from Old Variables

### Before (Terraform Variables)
```bash
terraform apply \
  -var="cluster_name=my-cluster" \
  -var="region=us-east-1" \
  -var="auto_mode=false"
```

### After (config.yaml)
```yaml
cluster_name: "my-cluster"
region: "us-east-1"
auto_mode: "false"
```

```bash
terraform apply  # That's it!
```

---

## ⚠️ Important Notes

1. **config.yaml is the source of truth** - Don't use `-var` flags
2. **Commit config.yaml** to Git (except sensitive data)
3. **Use different configs** for different environments (dev/staging/prod)
4. **Terraform reads config on every run** - No need to re-init after config changes
5. **Existing VPC mode** requires all 6 subnets (3 private + 3 public)

---

## 🐛 Troubleshooting

### Error: "Failed to read config.yaml"
```bash
# Make sure you're in cluster/terraform directory
cd cluster/terraform

# Check if config.yaml exists
ls -la ../../config.yaml
```

### Error: "Invalid YAML syntax"
```bash
# Validate YAML
cat ../../config.yaml | yq .
```

### Error: "Insufficient subnet IDs"
```bash
# For existing VPC mode, you need 3 private + 3 public subnets
# OR adjust availability_zones to match your subnets count
```

---

## 📚 Related Documentation

- [Spot Instances Guide](./SPOT-INSTANCES-GUIDE.md)
- [Main README](../../README.md)
- [Quick Start Guide](../../docs/02-GUIA-RAPIDO-POC.md)
