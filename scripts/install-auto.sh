#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

################################################################################
# Load ALL configuration from config.yaml
################################################################################
CONFIG_FILE=${REPO_ROOT}/config.yaml

# Identity Provider (cognito or keycloak)
IDENTITY_PROVIDER=$(yq eval '.identity_provider // "cognito"' $CONFIG_FILE)
echo -e "${CYAN}🔐 Identity Provider: ${IDENTITY_PROVIDER}${NC}"

# Domain configuration
DOMAIN_NAME=$(yq eval '.domain' $CONFIG_FILE)
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd // "argocd"' $CONFIG_FILE)
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage // "backstage"' $CONFIG_FILE)
ARGOCD_HOST="${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}"
BACKSTAGE_HOST="${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"

# Cluster configuration
PATH_ROUTING=$(yq eval '.path_routing // "false"' $CONFIG_FILE)
AUTO_MODE=$(yq eval '.auto_mode // "false"' $CONFIG_FILE)

# GitHub configuration
GITHUB_ORG=$(yq eval '.github_org' $CONFIG_FILE)
GITHUB_TOKEN=$(yq eval '.github_token' $CONFIG_FILE)
INFRA_REPO=$(yq eval '.infrastructure_repo' $CONFIG_FILE)

# Terraform backend
TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' $CONFIG_FILE)
TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' $CONFIG_FILE)

# Cognito configuration (from Terraform outputs)
TERRAFORM_DIR=${REPO_ROOT}/cluster/terraform
if [[ "$IDENTITY_PROVIDER" == "cognito" ]]; then
  echo -e "${CYAN}📦 Loading Cognito configuration from Terraform...${NC}"
  cd $TERRAFORM_DIR
  COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null || echo "")
  COGNITO_ISSUER_URL=$(terraform output -raw cognito_issuer_url 2>/dev/null || echo "")
  COGNITO_ARGOCD_CLIENT_ID=$(terraform output -raw cognito_argocd_client_id 2>/dev/null || echo "")
  COGNITO_ARGOCD_CLIENT_SECRET=$(terraform output -raw cognito_argocd_client_secret 2>/dev/null || echo "")
  COGNITO_BACKSTAGE_CLIENT_ID=$(terraform output -raw cognito_backstage_client_id 2>/dev/null || echo "")
  COGNITO_BACKSTAGE_CLIENT_SECRET=$(terraform output -raw cognito_backstage_client_secret 2>/dev/null || echo "")
  cd $REPO_ROOT

  if [[ -z "$COGNITO_USER_POOL_ID" ]]; then
    echo -e "${RED}❌ Cognito not found in Terraform outputs. Run 'terraform apply' first.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ Cognito User Pool: ${COGNITO_USER_POOL_ID}${NC}"
fi

# ACM Certificate ARN from config.yaml
ACM_CERTIFICATE_ARN=$(yq eval '.acm_certificate_arn // ""' $CONFIG_FILE)
if [[ -z "$ACM_CERTIFICATE_ARN" ]]; then
  # Try to get from Terraform output if not in config
  ACM_CERTIFICATE_ARN=$(cd $TERRAFORM_DIR && terraform output -raw acm_certificate_arn 2>/dev/null || echo "")
fi
echo -e "${CYAN}🔒 ACM Certificate: ${ACM_CERTIFICATE_ARN}${NC}"

# Static helm values files
ARGOCD_STATIC_VALUES_FILE=${REPO_ROOT}/packages/argo-cd/values.yaml
EXTERNAL_SECRETS_STATIC_VALUES_FILE=${REPO_ROOT}/packages/external-secrets/values.yaml
ADDONS_APPSET_STATIC_VALUES_FILE=${REPO_ROOT}/packages/bootstrap/values.yaml

# Chart versions
ARGOCD_CHART_VERSION=$(yq '.argocd.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
EXTERNAL_SECRETS_CHART_VERSION=$(yq '.external-secrets.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)

# Custom Manifests Paths
ARGOCD_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/argo-cd/manifests
EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/external-secrets/manifests

################################################################################
# Build ArgoCD dynamic values based on Identity Provider
################################################################################
ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)

if [[ "$IDENTITY_PROVIDER" == "cognito" ]]; then
  # ArgoCD with Cognito OIDC
  cat << EOF > "$ARGOCD_DYNAMIC_VALUES_FILE"
cnoe_ref_impl:
  auto_mode: $([[ "${AUTO_MODE}" == "true" ]] && echo '"true"' || echo '"false"')
global:
  domain: ${ARGOCD_HOST}
server:
  ingress:
    annotations: {}
    path: /
configs:
  cm:
    url: https://${ARGOCD_HOST}
    oidc.config: |
      name: AWS Cognito
      issuer: ${COGNITO_ISSUER_URL}
      clientID: ${COGNITO_ARGOCD_CLIENT_ID}
      clientSecret: ${COGNITO_ARGOCD_CLIENT_SECRET}
      requestedScopes:
        - openid
        - email
        - profile
  params:
    server.insecure: "true"
EOF
else
  # ArgoCD with Keycloak OIDC (legacy)
  KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak // "keycloak"' $CONFIG_FILE)
  KEYCLOAK_HOST="${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"
  cat << EOF > "$ARGOCD_DYNAMIC_VALUES_FILE"
cnoe_ref_impl:
  auto_mode: $([[ "${AUTO_MODE}" == "true" ]] && echo '"true"' || echo '"false"')
global:
  domain: ${ARGOCD_HOST}
server:
  ingress:
    annotations: {}
    path: /
configs:
  cm:
    url: https://${ARGOCD_HOST}
    oidc.config: |
      name: Keycloak
      issuer: https://${KEYCLOAK_HOST}/realms/cnoe
      clientID: argocd
      clientSecret: argocd-secret-2024
      requestedScopes:
        - openid
        - profile
        - email
  params:
    server.insecure: "true"
EOF
fi

echo -e "${BOLD}${GREEN}🔄 Adding Helm repositories...${NC}"
# Add all required helm repos with retry logic
add_helm_repo_with_retry() {
  local name=$1
  local url=$2
  local max_attempts=3
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if helm repo add "$name" "$url" > /dev/null 2>&1; then
      echo -e "${GREEN}✅ Added helm repo: $name${NC}"
      return 0
    else
      echo -e "${YELLOW}⚠️  Attempt $attempt/$max_attempts failed for $name, retrying...${NC}"
      sleep 5
      attempt=$((attempt + 1))
    fi
  done
  echo -e "${RED}❌ Failed to add helm repo $name after $max_attempts attempts${NC}"
  return 1
}

add_helm_repo_with_retry "argo" "https://argoproj.github.io/argo-helm"
add_helm_repo_with_retry "external-secrets" "https://charts.external-secrets.io"
add_helm_repo_with_retry "backstage" "https://backstage.github.io/charts"
add_helm_repo_with_retry "codecentric" "https://codecentric.github.io/helm-charts"
add_helm_repo_with_retry "ingress-nginx" "https://kubernetes.github.io/ingress-nginx"
add_helm_repo_with_retry "runatlantis" "https://runatlantis.github.io/helm-charts"
add_helm_repo_with_retry "bitnami" "https://charts.bitnami.com/bitnami"
add_helm_repo_with_retry "crossplane-stable" "https://charts.crossplane.io/stable"

echo -e "${YELLOW}⏳ Updating helm repos...${NC}"
helm repo update > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Argo CD...${NC}"
helm upgrade --install --wait argocd argo/argo-cd \
  --namespace argocd --version $ARGOCD_CHART_VERSION \
  --create-namespace \
  --values "$ARGOCD_STATIC_VALUES_FILE" \
  --values "$ARGOCD_DYNAMIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${YELLOW}⏳ Waiting for Argo CD to be healthy...${NC}"
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null


echo -e "${BOLD}${GREEN}🔄 Installing External Secrets...${NC}"

# Get External Secrets IRSA role ARN from Terraform output
EXTERNAL_SECRETS_ROLE_ARN=$(cd ${REPO_ROOT}/cluster/terraform && terraform output -raw external_secrets_role_arn 2>/dev/null || echo "")

if [ -z "$EXTERNAL_SECRETS_ROLE_ARN" ]; then
  echo -e "${RED}❌ Could not get External Secrets role ARN from Terraform. Using default...${NC}"
  EXTERNAL_SECRETS_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/external-secrets-irsa"
fi

echo -e "${CYAN}🔐 Using IRSA role: $EXTERNAL_SECRETS_ROLE_ARN${NC}"

# Create dynamic values file with IRSA role
EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE=$(mktemp)
cat "$EXTERNAL_SECRETS_STATIC_VALUES_FILE" | \
  sed "s|\${EXTERNAL_SECRETS_ROLE_ARN}|${EXTERNAL_SECRETS_ROLE_ARN}|g" \
  > "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"

helm upgrade --install --wait external-secrets external-secrets/external-secrets \
  --namespace external-secrets --version $EXTERNAL_SECRETS_CHART_VERSION \
  --create-namespace \
  --values "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

rm -f "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"

echo -e "${YELLOW}⏳ Waiting for External Secrets to be healthy...${NC}"
kubectl wait --for=condition=available deployment/external-secrets -n external-secrets --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Atlantis (GitOps for Terraform)...${NC}"

# Read Atlantis configuration from config.yaml
ATLANTIS_SUBDOMAIN=$(yq eval '.atlantis.subdomain // "atlantis"' ${CONFIG_FILE})
ATLANTIS_WEBHOOK_SECRET=$(yq eval '.atlantis.webhook_secret // "atlantis-webhook-secret"' ${CONFIG_FILE})
ATLANTIS_AUTOMERGE=$(yq eval '.atlantis.automerge // true' ${CONFIG_FILE})

# Build Atlantis extraArgs based on config
ATLANTIS_EXTRA_ARGS=""
if [ "$ATLANTIS_AUTOMERGE" == "true" ]; then
  ATLANTIS_EXTRA_ARGS="--set extraArgs[0]=--automerge --set extraArgs[1]=--autoplan-modules"
fi

helm upgrade --install --wait atlantis runatlantis/atlantis \
  --namespace atlantis \
  --create-namespace \
  --set github.user="${GITHUB_ORG}" \
  --set github.token="${GITHUB_TOKEN}" \
  --set github.secret="${ATLANTIS_WEBHOOK_SECRET}" \
  --set orgAllowlist="github.com/${GITHUB_ORG}/*" \
  --set ingress.enabled=true \
  --set ingress.host="${ATLANTIS_SUBDOMAIN}.${DOMAIN_NAME}" \
  --set ingress.ingressClassName=nginx \
  --set ingress.path=/ \
  --set serviceAccount.create=true \
  --set serviceAccount.name=atlantis \
  ${ATLANTIS_EXTRA_ARGS} \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${YELLOW}⏳ Waiting for Atlantis to be healthy...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=atlantis -n atlantis --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${BOLD}${GREEN}🔄 Applying custom manifests...${NC}"

# Create hub-cluster-secret directly (workaround for SCP restrictions on Secrets Manager)
echo -e "${CYAN}🔐 Creating hub-cluster-secret with configuration from config.yaml...${NC}"
HUB_CLUSTER_SECRET_MANIFEST=$(mktemp)
cat ${REPO_ROOT}/packages/argo-cd/manifests/hub-cluster-secret-direct.yaml | \
  sed "s|\${CLUSTER_NAME}|${CLUSTER_NAME}|g" | \
  sed "s|\${DOMAIN_NAME}|${DOMAIN_NAME}|g" | \
  sed "s|\${DOMAIN}|${DOMAIN_NAME}|g" | \
  sed "s|\${AWS_REGION}|${AWS_REGION}|g" | \
  sed "s|\${AWS_ACCOUNT_ID}|${AWS_ACCOUNT_ID}|g" | \
  sed "s|\${ROUTE53_HOSTED_ZONE_ID}|$(yq '.route53_hosted_zone_id' ${CONFIG_FILE})|g" | \
  sed "s|\${PATH_ROUTING}|${PATH_ROUTING}|g" | \
  sed "s|\${REPO_URL}|$(yq '.repo.url' ${CONFIG_FILE})|g" | \
  sed "s|\${REPO_REVISION}|$(yq '.repo.revision' ${CONFIG_FILE})|g" | \
  sed "s|\${REPO_BASEPATH}|$(yq '.repo.basepath' ${CONFIG_FILE})|g" | \
  sed "s|\${AUTO_MODE}|${AUTO_MODE}|g" \
  > "$HUB_CLUSTER_SECRET_MANIFEST"

kubectl apply -f "$HUB_CLUSTER_SECRET_MANIFEST" --kubeconfig $KUBECONFIG_FILE > /dev/null
rm "$HUB_CLUSTER_SECRET_MANIFEST"

################################################################################
# Configure Identity Provider (Cognito or Keycloak)
################################################################################

if [[ "$IDENTITY_PROVIDER" == "cognito" ]]; then
  echo -e "${BOLD}${GREEN}🔐 Configuring AWS Cognito...${NC}"

  # Create admin user in Cognito
  COGNITO_ADMIN_EMAIL=$(yq eval '.cognito.admin_email // "admin@example.com"' $CONFIG_FILE)
  COGNITO_ADMIN_PASSWORD=$(yq eval '.cognito.admin_password // "Admin123!"' $CONFIG_FILE)
  AWS_REGION=$(yq eval '.region // "us-east-1"' $CONFIG_FILE)

  echo -e "${CYAN}👤 Creating Cognito admin user: ${COGNITO_ADMIN_EMAIL}${NC}"

  # Check if user exists, create if not
  if ! aws cognito-idp admin-get-user \
      --user-pool-id "$COGNITO_USER_POOL_ID" \
      --username "$COGNITO_ADMIN_EMAIL" \
      --region "$AWS_REGION" > /dev/null 2>&1; then

    aws cognito-idp admin-create-user \
      --user-pool-id "$COGNITO_USER_POOL_ID" \
      --username "$COGNITO_ADMIN_EMAIL" \
      --user-attributes Name=email,Value="$COGNITO_ADMIN_EMAIL" Name=email_verified,Value=true \
      --temporary-password "$COGNITO_ADMIN_PASSWORD" \
      --message-action SUPPRESS \
      --region "$AWS_REGION" > /dev/null

    aws cognito-idp admin-set-user-password \
      --user-pool-id "$COGNITO_USER_POOL_ID" \
      --username "$COGNITO_ADMIN_EMAIL" \
      --password "$COGNITO_ADMIN_PASSWORD" \
      --permanent \
      --region "$AWS_REGION" > /dev/null

    echo -e "${GREEN}✅ Admin user created${NC}"
  else
    echo -e "${YELLOW}⚠️  Admin user already exists${NC}"
  fi

  # Set OIDC variables for Backstage
  OIDC_CLIENT_ID="$COGNITO_BACKSTAGE_CLIENT_ID"
  OIDC_CLIENT_SECRET="$COGNITO_BACKSTAGE_CLIENT_SECRET"
  OIDC_ISSUER_URL="$COGNITO_ISSUER_URL"

else
  echo -e "${BOLD}${GREEN}🔐 Configuring Keycloak...${NC}"

  # Create Keycloak namespace and secret
  kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
  kubectl create secret generic keycloak \
    --namespace keycloak \
    --from-literal=admin-password=admin \
    --from-literal=management-password=manager123 \
    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak // "keycloak"' $CONFIG_FILE)
  KEYCLOAK_HOST="${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"

  # Set OIDC variables for Backstage
  OIDC_CLIENT_ID="backstage"
  OIDC_CLIENT_SECRET="backstage-secret-2024"
  OIDC_ISSUER_URL="https://${KEYCLOAK_HOST}/realms/cnoe"
fi

################################################################################
# Create Backstage secrets
################################################################################
echo -e "${CYAN}🔐 Creating Backstage environment variables secret...${NC}"

# Create namespace
kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create service account for Backstage Kubernetes plugin
kubectl create serviceaccount backstage-k8s -n backstage --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl create clusterrolebinding backstage-k8s --clusterrole=view --serviceaccount=backstage:backstage-k8s --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create secret with K8s token and other env vars
K8S_TOKEN=$(kubectl -n backstage create token backstage-k8s --duration=87600h 2>/dev/null || kubectl -n backstage create token backstage-k8s --duration=24h || echo "")
# Generate secrets for Backstage
BACKEND_SECRET=$(openssl rand -base64 32)
AUTH_SESSION_SECRET=$(openssl rand -base64 32)
kubectl create secret generic backstage-env-vars \
  -n backstage \
  --from-literal=POSTGRES_HOST=backstage-postgresql \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_USER=backstage \
  --from-literal=POSTGRES_PASSWORD=backstage123 \
  --from-literal=GITHUB_TOKEN="$GITHUB_TOKEN" \
  --from-literal=ARGOCD_ADMIN_PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' --kubeconfig $KUBECONFIG_FILE 2>/dev/null | base64 -d || echo 'admin')" \
  --from-literal=OIDC_CLIENT_ID="$OIDC_CLIENT_ID" \
  --from-literal=OIDC_CLIENT_SECRET="$OIDC_CLIENT_SECRET" \
  --from-literal=OIDC_ISSUER_URL="$OIDC_ISSUER_URL" \
  --from-literal=K8S_SA_TOKEN="$K8S_TOKEN" \
  --from-literal=GITHUB_ORG="$GITHUB_ORG" \
  --from-literal=INFRA_REPO="$INFRA_REPO" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$TF_BACKEND_BUCKET" \
  --from-literal=TERRAFORM_BACKEND_REGION="$TF_BACKEND_REGION" \
  --from-literal=BACKSTAGE_FRONTEND_URL="https://${BACKSTAGE_HOST}" \
  --from-literal=BACKSTAGE_BACKEND_URL="https://${BACKSTAGE_HOST}" \
  --from-literal=BACKEND_SECRET="$BACKEND_SECRET" \
  --from-literal=AUTH_SESSION_SECRET="$AUTH_SESSION_SECRET" \
  --from-literal=GITHUB_ORG_URL="https://github.com/${GITHUB_ORG}" \
  --from-literal=ARGOCD_URL="https://${ARGOCD_HOST}" \
  --from-literal=ARGOCD_USERNAME="admin" \
  --from-literal=ARGO_WORKFLOWS_URL="https://argo-workflows.${DOMAIN_NAME}" \
  --from-literal=ARGO_CD_URL="https://${ARGOCD_HOST}" \
  --from-literal=ARGO_WORKFLOWS_AUTH_TOKEN="placeholder" \
  --from-literal=ARGOCD_AUTH_TOKEN="placeholder" \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# ArgoCD repository credential for private infrastructure repo
# Using GitHub OAuth format: token as username, x-oauth-basic as password
echo -e "${CYAN}🔐 Creating ArgoCD repository credentials for private repo...${NC}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
apiVersion: v1
kind: Secret
metadata:
  name: repo-${INFRA_REPO}-credentials
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
type: Opaque
stringData:
  type: git
  url: https://github.com/${GITHUB_ORG}/${INFRA_REPO}
  username: ${GITHUB_TOKEN}
  password: x-oauth-basic
EOF

# Configure ArgoCD RBAC (works for both Cognito and Keycloak)
echo -e "${CYAN}🔧 Configuring ArgoCD RBAC...${NC}"
kubectl -n argocd patch cm argocd-rbac-cm --type merge --kubeconfig $KUBECONFIG_FILE -p '{
  "data": {
    "policy.csv": "g, admin, role:admin\np, role:readonly, applications, get, *, allow\np, role:readonly, clusters, get, *, allow\np, role:readonly, repositories, get, *, allow",
    "policy.default": "role:readonly"
  }
}' > /dev/null 2>&1 || true

# Only configure Keycloak if using Keycloak as identity provider
if [[ "$IDENTITY_PROVIDER" == "keycloak" ]]; then
  echo "👥 Configuring Keycloak (will be done by ArgoCD ApplicationSet)..."
  # Keycloak configuration is handled by the addons ApplicationSet
fi

echo -e "${CYAN}🔄 Restarting ArgoCD server to apply configuration...${NC}"
kubectl rollout restart -n argocd deployment/argocd-server --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Apply Crossplane Compositions (S3, VPC, SecurityGroup, EC2, RDS, EKS)
echo -e "${CYAN}🔧 Creating Crossplane Compositions...${NC}"
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/s3-bucket-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/s3-bucket-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/vpc-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/vpc-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/securitygroup-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/securitygroup-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/ec2-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/ec2-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/rds-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/rds-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/eks-definition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
kubectl apply -f ${REPO_ROOT}/packages/crossplane-compositions/eks-composition.yaml --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create ArgoCD Application for infrastructure repo
echo -e "${CYAN}📦 Creating ArgoCD Application for infrastructure resources...${NC}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: infrastructure
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/${GITHUB_ORG}/${INFRA_REPO}
    targetRevision: main
    path: s3-buckets
    directory:
      recurse: false
      exclude: 'catalog-info.yaml'
  destination:
    server: https://kubernetes.default.svc
    namespace: crossplane-system
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
  ignoreDifferences:
  - group: "*"
    kind: "*"
    managedFieldsManagers:
    - kube-controller-manager
EOF

# Apply other custom manifests (skip hub-cluster-secret files as we created it directly)
for manifest in "$ARGOCD_CUSTOM_MANIFESTS_PATH"/*.yaml; do
  if [[ ! "$manifest" =~ hub-cluster-secret ]]; then
    kubectl apply -f "$manifest" --kubeconfig $KUBECONFIG_FILE > /dev/null
  fi
done

kubectl apply -f "$EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH" --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Infrastructure ArgoCD Application...${NC}"
kubectl apply -f "$ARGOCD_CUSTOM_MANIFESTS_PATH/infrastructure-app.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

################################################################################
# Install Core Components via Helm (simplified - no ApplicationSet)
################################################################################

echo -e "${BOLD}${GREEN}🔄 Installing Ingress NGINX...${NC}"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"=internet-facing \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="${ACM_CERTIFICATE_ARN}" \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-ports"=https \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-backend-protocol"=tcp \
  --set controller.service.targetPorts.https=http \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${YELLOW}⏳ Waiting for Ingress NGINX to be ready...${NC}"
kubectl wait --for=condition=available deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${BOLD}${GREEN}🔄 Installing External DNS...${NC}"
helm upgrade --install external-dns bitnami/external-dns \
  --namespace external-dns --create-namespace \
  --set image.registry=registry.k8s.io \
  --set image.repository=external-dns/external-dns \
  --set image.tag=v0.14.0 \
  --set provider=aws \
  --set aws.region=${AWS_REGION} \
  --set txtOwnerId=${CLUSTER_NAME} \
  --set domainFilters[0]=${DOMAIN_NAME} \
  --set policy=sync \
  --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${BOLD}${GREEN}🔄 Installing Crossplane...${NC}"
helm upgrade --install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system --create-namespace \
  --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${YELLOW}⏳ Waiting for Crossplane to be ready...${NC}"
kubectl wait --for=condition=available deployment/crossplane -n crossplane-system --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${BOLD}${GREEN}🔄 Installing Backstage...${NC}"
helm upgrade --install backstage backstage/backstage \
  --namespace backstage --create-namespace \
  --values ${REPO_ROOT}/packages/backstage/values.yaml \
  --set ingress.enabled=true \
  --set ingress.host=${BACKSTAGE_HOST} \
  --set ingress.className=nginx \
  --set backstage.extraEnvVarsSecrets[0]=backstage-env-vars \
  --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${YELLOW}⏳ Waiting for components to stabilize...${NC}"
sleep 30

################################################################################
# Final Configuration based on Identity Provider
################################################################################

if [[ "$IDENTITY_PROVIDER" == "cognito" ]]; then
  echo -e "\n${BOLD}${GREEN}🔐 Finalizing Cognito configuration...${NC}"

  # Apply Backstage Ingress
  echo -e "${CYAN}🌐 Creating Backstage Ingress...${NC}"
  kubectl apply -f "$REPO_ROOT/packages/backstage/backstage-ingress.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  echo -e "${GREEN}✅ Cognito OIDC configured for ArgoCD and Backstage${NC}"

else
  # Keycloak configuration
  echo -e "\n${BOLD}${GREEN}🔐 Configuring Keycloak and Backstage integration...${NC}"

  # Wait for Keycloak to be ready
  echo -e "${CYAN}⏳ Waiting for Keycloak to be ready...${NC}"
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Apply Keycloak Ingress
  echo -e "${CYAN}🌐 Creating Keycloak Ingress...${NC}"
  kubectl apply -f "$REPO_ROOT/packages/keycloak/keycloak-ingress.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Apply Backstage Ingress
  echo -e "${CYAN}🌐 Creating Backstage Ingress...${NC}"
  kubectl apply -f "$REPO_ROOT/packages/backstage/backstage-ingress.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Apply Keycloak bootstrap Job
  echo -e "${CYAN}🔧 Running Keycloak bootstrap Job...${NC}"
  kubectl apply -f "$REPO_ROOT/packages/keycloak/keycloak-bootstrap-job.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Wait for Job to complete
  echo -e "${CYAN}⏳ Waiting for Keycloak configuration to complete...${NC}"
  kubectl wait --for=condition=complete --timeout=300s job/keycloak-bootstrap -n keycloak --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  echo -e "${GREEN}✅ Keycloak configured${NC}"
fi

################################################################################
# Print Summary
################################################################################
echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Identity Provider: ${IDENTITY_PROVIDER}${NC}"
echo -e ""
echo -e "${CYAN}URLs:${NC}"
echo -e "  ArgoCD:    https://${ARGOCD_HOST}"
echo -e "  Backstage: https://${BACKSTAGE_HOST}"
echo -e "  Atlantis:  https://$(yq eval '.atlantis.subdomain // "atlantis"' $CONFIG_FILE).${DOMAIN_NAME}"

if [[ "$IDENTITY_PROVIDER" == "cognito" ]]; then
  echo -e ""
  echo -e "${CYAN}Cognito Login:${NC}"
  echo -e "  Email:    $(yq eval '.cognito.admin_email' $CONFIG_FILE)"
  echo -e "  Password: $(yq eval '.cognito.admin_password' $CONFIG_FILE)"
  echo -e ""
  echo -e "${YELLOW}⚠️  Note: Backstage uses guest login (signInPage: guest)${NC}"
  echo -e "${YELLOW}   The cnoe-io/backstage-app image requires 'groups' scope${NC}"
  echo -e "${YELLOW}   which Cognito does not support. ArgoCD OIDC works normally.${NC}"
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
