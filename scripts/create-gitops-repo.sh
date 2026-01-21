#!/bin/bash
################################################################################
# Create GitOps Repository for Applications
################################################################################
# This script creates a separate GitOps repository for an application
# following the "1 app = 1 repo" pattern for better isolation and ownership.
#
# Usage:
#   ./create-gitops-repo.sh <app-name> [github-org] [base-domain]
#
# Example:
#   ./create-gitops-repo.sh hello-world-e2e darede-labs timedevops.click
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Parameters
APP_NAME=${1:-""}
GITHUB_ORG=${2:-"darede-labs"}
BASE_DOMAIN=${3:-"timedevops.click"}

if [ -z "$APP_NAME" ]; then
  error "Usage: $0 <app-name> [github-org] [base-domain]"
fi

REPO_NAME="${APP_NAME}"
NAMESPACE=${NAMESPACE:-"default"}

info "Creating GitOps repository for: $APP_NAME"
info "GitHub Organization: $GITHUB_ORG"
info "Base Domain: $BASE_DOMAIN"
info "Namespace: $NAMESPACE"

################################################################################
# Step 1: Check Prerequisites
################################################################################
info "Step 1: Checking prerequisites..."

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
  error "GitHub CLI (gh) is not installed. Install it from: https://cli.github.com/"
fi

# Check if user is authenticated
if ! gh auth status &> /dev/null; then
  error "Not authenticated with GitHub. Run: gh auth login"
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  error "kubectl is not installed"
fi

# Check if yq is available
if ! command -v yq &> /dev/null; then
  warn "yq is not installed. Some features may not work. Install from: https://github.com/mikefarah/yq"
fi

info "✅ Prerequisites check passed"

################################################################################
# Step 2: Create GitHub Repository
################################################################################
info "Step 2: Creating GitHub repository: $GITHUB_ORG/$REPO_NAME..."

# Check if repository already exists
if gh repo view "$GITHUB_ORG/$REPO_NAME" &> /dev/null; then
  warn "Repository already exists: $GITHUB_ORG/$REPO_NAME"
  read -p "Do you want to continue and update the repository? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Aborted by user"
  fi
else
  # Create repository
  info "Creating repository..."
  gh repo create "$GITHUB_ORG/$REPO_NAME" \
    --public \
    --description "GitOps repository for $APP_NAME - Kubernetes manifests" \
    --clone=false

  info "✅ Repository created: https://github.com/$GITHUB_ORG/$REPO_NAME"
fi

################################################################################
# Step 3: Clone or Initialize Repository
################################################################################
info "Step 3: Cloning repository..."

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

git clone "https://github.com/$GITHUB_ORG/$REPO_NAME.git"
cd "$REPO_NAME"

################################################################################
# Step 4: Create Directory Structure
################################################################################
info "Step 4: Creating directory structure..."

mkdir -p manifests
mkdir -p .github/workflows

################################################################################
# Step 5: Create Kubernetes Manifests
################################################################################
info "Step 5: Creating Kubernetes manifests..."

# Deployment
cat > manifests/deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: platform-services
    app.kubernetes.io/managed-by: argocd
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: ${APP_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${APP_NAME}
        app.kubernetes.io/component: backend
        app.kubernetes.io/part-of: platform-services
        app.kubernetes.io/version: main
    spec:
      containers:
      - name: ${APP_NAME}
        image: <ECR_ACCOUNT_ID>.dkr.ecr.<AWS_REGION>.amazonaws.com/${APP_NAME}:main
        ports:
        - containerPort: 3000
          name: http
          protocol: TCP
        env:
        - name: NODE_ENV
          value: production
        - name: PORT
          value: "3000"
        - name: APP_NAME
          value: "${APP_NAME}"
        - name: APP_DESCRIPTION
          value: "Microservice deployed via GitOps"
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
EOF

# Service
cat > manifests/service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: backend
spec:
  selector:
    app.kubernetes.io/name: ${APP_NAME}
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
    name: http
  type: ClusterIP
EOF

# Ingress
cat > manifests/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: nginx
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
    external-dns.alpha.kubernetes.io/hostname: ${APP_NAME}.${BASE_DOMAIN}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: backend
spec:
  rules:
  - host: ${APP_NAME}.${BASE_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${APP_NAME}
            port:
              number: 80
EOF

info "✅ Kubernetes manifests created"

################################################################################
# Step 6: Create ArgoCD Application Manifest
################################################################################
info "Step 6: Creating ArgoCD Application manifest..."

cat > argocd-application.yaml <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: argocd
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/managed-by: argocd
  finalizers:
  - resources-finalizer.argocd.argoproj.io
spec:
  project: default

  source:
    repoURL: https://github.com/${GITHUB_ORG}/${REPO_NAME}.git
    targetRevision: main
    path: manifests

  destination:
    server: https://kubernetes.default.svc
    namespace: ${NAMESPACE}

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground
    - PruneLast=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m

  ignoreDifferences: []

  revisionHistoryLimit: 10
EOF

info "✅ ArgoCD Application manifest created"

################################################################################
# Step 7: Create README
################################################################################
info "Step 7: Creating README..."

cat > README.md <<EOF
# ${APP_NAME} - GitOps Repository

This repository contains the Kubernetes manifests for the \`${APP_NAME}\` application.

## 📁 Repository Structure

\`\`\`
${REPO_NAME}/
├── manifests/             # Kubernetes manifests
│   ├── deployment.yaml    # Deployment configuration
│   ├── service.yaml       # Service configuration
│   └── ingress.yaml       # Ingress configuration
├── argocd-application.yaml # ArgoCD Application manifest
└── README.md              # This file
\`\`\`

## 🚀 Deployment

This application is deployed using **GitOps** with **ArgoCD**.

### Initial Deployment

Apply the ArgoCD Application manifest to your cluster:

\`\`\`bash
kubectl apply -f argocd-application.yaml
\`\`\`

ArgoCD will automatically sync the manifests from this repository to your cluster.

### Updating the Application

To update the application:

1. Modify the manifests in the \`manifests/\` directory
2. Commit and push your changes:
   \`\`\`bash
   git add manifests/
   git commit -m "feat: update deployment configuration"
   git push origin main
   \`\`\`
3. ArgoCD will automatically detect the changes and sync them to the cluster

### Manual Sync

If you need to manually sync the application:

\`\`\`bash
argocd app sync ${APP_NAME}
\`\`\`

## 🔍 Monitoring

- **Application URL**: https://${APP_NAME}.${BASE_DOMAIN}
- **Health Endpoint**: https://${APP_NAME}.${BASE_DOMAIN}/health
- **Readiness Endpoint**: https://${APP_NAME}.${BASE_DOMAIN}/ready
- **Metrics Endpoint**: https://${APP_NAME}.${BASE_DOMAIN}/metrics

## 📊 Observability

### Logs (Loki)

View logs in Grafana:
\`\`\`
{namespace="${NAMESPACE}", app_kubernetes_io_name="${APP_NAME}"}
\`\`\`

### Metrics (Prometheus)

Metrics are automatically scraped by Prometheus if the pod has the annotation:
\`\`\`yaml
prometheus.io/scrape: "true"
prometheus.io/port: "3000"
prometheus.io/path: "/metrics"
\`\`\`

### Dashboards (Grafana)

- Service Overview: \`https://grafana.${BASE_DOMAIN}/d/service-overview?var-namespace=${NAMESPACE}&var-app=${APP_NAME}\`

## 🔐 Security

- All images should be scanned before deployment
- Secrets should be managed via External Secrets or Sealed Secrets
- RBAC policies should follow the principle of least privilege

## 🛠️ Troubleshooting

### Check Pod Status
\`\`\`bash
kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_NAME}
\`\`\`

### Check Logs
\`\`\`bash
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=${APP_NAME} --tail=100
\`\`\`

### Check ArgoCD Sync Status
\`\`\`bash
argocd app get ${APP_NAME}
\`\`\`

### Force Sync
\`\`\`bash
argocd app sync ${APP_NAME} --force
\`\`\`

## 📝 Notes

- This repository follows GitOps best practices
- All changes should be made through pull requests
- CI/CD pipelines should update the \`image\` field in \`deployment.yaml\` automatically

## 🔗 Links

- **GitHub Org**: https://github.com/${GITHUB_ORG}
- **Application Repo**: (Link to application source code repository)
- **ArgoCD UI**: https://argocd.${BASE_DOMAIN}
- **Grafana**: https://grafana.${BASE_DOMAIN}

---

**Managed by**: Platform Team
**GitOps Tool**: ArgoCD
**Last Updated**: $(date +%Y-%m-%d)
EOF

info "✅ README created"

################################################################################
# Step 8: Create .gitignore
################################################################################
info "Step 8: Creating .gitignore..."

cat > .gitignore <<EOF
# Temporary files
*.tmp
*.bak
.DS_Store

# IDE
.idea/
.vscode/
*.swp
*.swo

# Secrets (should never be committed)
secrets.yaml
*.key
*.pem

# Local testing
.env
.env.local
EOF

################################################################################
# Step 9: Commit and Push
################################################################################
info "Step 9: Committing and pushing to GitHub..."

git add .
git commit -m "feat: initial GitOps repository setup for ${APP_NAME}

- Add Kubernetes manifests (deployment, service, ingress)
- Add ArgoCD Application manifest
- Add README and .gitignore
"

git push origin main

info "✅ Pushed to GitHub: https://github.com/$GITHUB_ORG/$REPO_NAME"

################################################################################
# Step 10: Apply ArgoCD Application (Optional)
################################################################################
echo ""
read -p "Do you want to apply the ArgoCD Application to the cluster now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  info "Applying ArgoCD Application..."
  kubectl apply -f argocd-application.yaml

  info "✅ ArgoCD Application created"
  info "Monitor sync status with: argocd app get ${APP_NAME}"
fi

################################################################################
# Summary
################################################################################
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    🎉 SUCCESS!                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "GitOps repository created for: ${APP_NAME}"
echo ""
echo "📦 Repository: https://github.com/${GITHUB_ORG}/${REPO_NAME}"
echo "🌐 Application URL: https://${APP_NAME}.${BASE_DOMAIN}"
echo "📊 ArgoCD: https://argocd.${BASE_DOMAIN}/applications/${APP_NAME}"
echo ""
echo "Next steps:"
echo "  1. Update <ECR_ACCOUNT_ID> and <AWS_REGION> in deployment.yaml"
echo "  2. Ensure your CI/CD pipeline updates the image tag in deployment.yaml"
echo "  3. Monitor ArgoCD sync status: argocd app get ${APP_NAME}"
echo ""

# Cleanup
cd ..
rm -rf "$TEMP_DIR"

info "Temporary directory cleaned up"
