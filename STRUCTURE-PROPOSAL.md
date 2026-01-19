# Proposed Directory Structure

## Overview
Clean, organized structure for easy deployment and maintenance.

```
reference-implementation-aws/
├── config.yaml                         # 🔧 Single source of truth
├── install.sh                          # 🚀 One-shot installer
├── destroy.sh                          # 🗑️ Clean teardown
│
├── docs/                               # 📚 Documentation
│   ├── INSTALLATION.md                 # Step-by-step guide
│   ├── ARCHITECTURE.md                 # Architecture diagrams
│   ├── TROUBLESHOOTING.md              # Common issues
│   └── CUSTOMIZATION.md                # How to customize
│
├── cluster/                            # ☁️ Infrastructure layer
│   ├── terraform/                      # AWS resources (IaC)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── ...
│   └── bootstrap/                      # Post-Terraform setup
│       ├── install.sh                  # Bootstrap script
│       └── healthcheck.sh              # Cluster readiness check
│
├── platform/                           # 🎯 Platform layer (core apps)
│   ├── karpenter/                      # Node autoscaler
│   │   ├── helm-values.yaml.tpl       # Helm values template
│   │   ├── nodepool.yaml.tpl          # NodePool template
│   │   └── ec2nodeclass.yaml.tpl      # EC2NodeClass template
│   │
│   ├── argocd/                         # GitOps operator
│   │   ├── helm-values.yaml.tpl
│   │   ├── application.yaml.tpl       # ArgoCD App CRDs
│   │   └── bootstrap-apps.yaml        # Initial apps to sync
│   │
│   ├── keycloak/                       # Identity provider
│   │   ├── helm-values.yaml.tpl
│   │   ├── realm.json.tpl             # Realm config template
│   │   └── clients/                   # OIDC clients
│   │       ├── backstage.json.tpl
│   │       └── argocd.json.tpl
│   │
│   └── ingress-nginx/                  # Already managed by Terraform
│       └── ...
│
├── apps/                               # 🎨 Application layer (user-facing)
│   ├── backstage/                      # Developer portal
│   │   ├── helm-values.yaml.tpl
│   │   ├── app-config.yaml.tpl        # Backstage config
│   │   └── catalog/                   # Software catalog
│   │       ├── templates/
│   │       └── components/
│   │
│   └── crossplane/                     # Future: Infrastructure APIs
│       └── ...
│
├── scripts/                            # 🛠️ Utility scripts
│   ├── render-templates.sh             # Generate manifests from .tpl
│   ├── validate-config.sh              # Validate config.yaml
│   └── generate-credentials.sh         # Generate secrets
│
└── manifests/                          # 📦 Generated manifests (gitignored)
    ├── karpenter/
    ├── argocd/
    ├── keycloak/
    └── backstage/
```

## Installation Flow

### Phase 1: Infrastructure (Terraform)
```bash
./install.sh
  ├─> scripts/validate-config.sh           # Validate config.yaml
  ├─> cluster/terraform/
  │     └─> terraform apply                # Provision AWS resources
  └─> cluster/bootstrap/healthcheck.sh     # Wait for cluster ready
```

### Phase 2: Platform (Core Components)
```bash
  ├─> scripts/render-templates.sh         # Generate manifests from templates
  │     ├─> platform/karpenter/*.tpl → manifests/karpenter/
  │     ├─> platform/argocd/*.tpl → manifests/argocd/
  │     └─> platform/keycloak/*.tpl → manifests/keycloak/
  │
  ├─> Install Karpenter
  │     ├─> helm install karpenter (using helm-values.yaml)
  │     └─> kubectl apply -f manifests/karpenter/
  │
  ├─> Install ArgoCD
  │     ├─> helm install argocd (using helm-values.yaml)
  │     └─> kubectl apply -f manifests/argocd/bootstrap-apps.yaml
  │
  └─> Install Keycloak
        ├─> helm install keycloak (using helm-values.yaml)
        └─> Configure realm + clients
```

### Phase 3: Applications (User-Facing)
```bash
  └─> Install Backstage
        ├─> kubectl apply -f manifests/backstage/
        └─> Wait for ArgoCD to sync remaining apps
```

## Key Benefits

1. **Single Command Install**: `./install.sh` does everything
2. **Template-Based**: All values from `config.yaml` (zero hardcoding)
3. **GitOps Ready**: ArgoCD manages apps automatically
4. **Organized**: Clear separation (infra → platform → apps)
5. **Idempotent**: Can re-run safely
6. **Documented**: Each component has README
7. **Testable**: Each phase can be tested independently

## For New Clients

```bash
# 1. Clone repo
git clone <repo-url>
cd reference-implementation-aws

# 2. Configure (5 minutes)
cp config.yaml.example config.yaml
vim config.yaml  # Adjust: cluster_name, domain, AWS profile, etc.

# 3. Install (15-20 minutes automated)
./install.sh

# 4. Access
# - Backstage: https://backstage.yourdomain.com
# - ArgoCD: https://argocd.yourdomain.com
# - Keycloak: https://keycloak.yourdomain.com
```

## Comparison

| Approach | Steps | Manual Work | Friendly? | GitOps? |
|----------|-------|-------------|-----------|---------|
| **Current** | 5+ manual | High | ❌ | ❌ |
| **Proposed** | 1 command | Low | ✅ | ✅ |
