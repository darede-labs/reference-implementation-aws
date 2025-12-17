#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

# Static helm values files
ARGOCD_STATIC_VALUES_FILE=${REPO_ROOT}/packages/argo-cd/values.yaml
EXTERNAL_SECRETS_STATIC_VALUES_FILE=${REPO_ROOT}/packages/external-secrets/values.yaml
ADDONS_APPSET_STATIC_VALUES_FILE=${REPO_ROOT}/packages/bootstrap/values.yaml

# Chart versions for Argo CD and ESO
ARGOCD_CHART_VERSION=$(yq '.argocd.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
EXTERNAL_SECRETS_CHART_VERSION=$(yq '.external-secrets.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)

# Custom Manifests Paths
ARGOCD_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/argo-cd/manifests
EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH=${REPO_ROOT}/packages/external-secrets/manifests

# Build Argo CD dynamic values
# Read secrets and config from config.yaml
ARGOCD_OIDC_SECRET=$(yq eval '.secrets.argocd.oidc_client_secret' ${CONFIG_FILE})
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' ${CONFIG_FILE})
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' ${CONFIG_FILE})
GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})

ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)
ISSUER_URL=$([[ "${PATH_ROUTING}" == "false" ]] && echo "${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}" || echo "${DOMAIN_NAME}/keycloak")
cat << EOF > "$ARGOCD_DYNAMIC_VALUES_FILE"
cnoe_ref_impl: # Specific values for reference CNOE implementation to control extraObjects.
  auto_mode: $([[ "${AUTO_MODE}" == "true" ]] && echo '"true"' || echo '"false"')
global:
  domain: $([[ "${PATH_ROUTING}" == "true" ]] && echo "${DOMAIN_NAME}" || echo "${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}")
server:
  ingress:
    annotations: {}
    path: /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    tls: false
configs:
  cm:
    oidc.config: |
      name: Keycloak
      issuer: https://$ISSUER_URL/realms/cnoe
      clientID: argocd
      clientSecret: ${ARGOCD_OIDC_SECRET}
      requestedScopes:
        - openid
        - profile
        - email
        - groups
      requestedIDTokenClaims:
        groups:
          essential: true
  params:
    'server.basehref': /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.rootpath': $([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.insecure': 'true'
EOF

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

# Optional: auto-apply after plan via server-side repoConfig + post_workflow_hook.
# To enable, export ATLANTIS_AUTO_APPLY_TOKEN before running this script.
ATLANTIS_REPO_CONFIG_FILE=$(mktemp)
cat > "$ATLANTIS_REPO_CONFIG_FILE" <<'EOF'
---
repos:
- id: /.*/
  apply_requirements: []
  import_requirements: []
  allowed_overrides: [workflow, delete_source_branch_on_merge]
  allow_custom_workflows: true
  post_workflow_hooks:
    - run: |
        if [ "$COMMAND_NAME" = "plan" ] && [ "$PULL_NUM" != "" ]; then
          curl -s -X POST \
            -H "Authorization: token $AUTO_APPLY_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            "https://api.github.com/repos/$BASE_REPO_OWNER/$BASE_REPO_NAME/issues/$PULL_NUM/comments" \
            -d '{"body":"atlantis apply"}' || true
        fi
EOF

ATLANTIS_AUTO_APPLY_ARGS=""
if [ -n "${ATLANTIS_AUTO_APPLY_TOKEN:-}" ]; then
  echo -e "${CYAN}🔐 Configuring Atlantis auto-apply token secret...${NC}"
  kubectl create secret generic atlantis-auto-apply-token \
    --namespace atlantis \
    --from-literal=token="${ATLANTIS_AUTO_APPLY_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  ATLANTIS_AUTO_APPLY_ARGS="--set environmentSecrets[0].name=AUTO_APPLY_TOKEN --set environmentSecrets[0].secretKeyRef.name=atlantis-auto-apply-token --set environmentSecrets[0].secretKeyRef.key=token"
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
  --set-file repoConfig="$ATLANTIS_REPO_CONFIG_FILE" \
  ${ATLANTIS_EXTRA_ARGS} \
  ${ATLANTIS_AUTO_APPLY_ARGS} \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

rm -f "$ATLANTIS_REPO_CONFIG_FILE"

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

# Create application secrets (workaround for SCP restrictions on Secrets Manager)
echo -e "${CYAN}🔐 Creating application secrets for Keycloak, Backstage, Argo Workflows...${NC}"

# Read Keycloak secrets from config.yaml
KEYCLOAK_ADMIN_USER=$(yq eval '.secrets.keycloak.admin_user // "admin"' ${CONFIG_FILE})
KEYCLOAK_ADMIN_PASSWORD=$(yq eval '.secrets.keycloak.admin_password // "admin"' ${CONFIG_FILE})
KEYCLOAK_MGMT_PASSWORD=$(yq eval '.secrets.keycloak.management_password // "manager123"' ${CONFIG_FILE})

# Keycloak secret
kubectl create secret generic keycloak \
  --namespace keycloak \
  --from-literal=admin-password=${KEYCLOAK_ADMIN_PASSWORD} \
  --from-literal=management-password=${KEYCLOAK_MGMT_PASSWORD} \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create ConfigMap with domain configuration for Keycloak bootstrap
# Note: ARGOCD_SUBDOMAIN and KEYCLOAK_SUBDOMAIN already set above
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
INFRA_REPO=$(yq eval '.infrastructure_repo' ${CONFIG_FILE})
TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' ${CONFIG_FILE})
BACKSTAGE_OIDC_SECRET=$(yq eval '.secrets.backstage.oidc_client_secret // "backstage-secret-2024"' ${CONFIG_FILE})
POSTGRES_HOST=$(yq eval '.secrets.backstage.postgres_host // "backstage-postgresql"' ${CONFIG_FILE})
POSTGRES_PORT=$(yq eval '.secrets.backstage.postgres_port // "5432"' ${CONFIG_FILE})
POSTGRES_USER=$(yq eval '.secrets.backstage.postgres_user // "backstage"' ${CONFIG_FILE})
POSTGRES_PASSWORD=$(yq eval '.secrets.backstage.postgres_password // "backstage123"' ${CONFIG_FILE})

kubectl create configmap domain-config \
  --namespace keycloak \
  --from-literal=DOMAIN=${DOMAIN_NAME} \
  --from-literal=ARGOCD_SUBDOMAIN=${ARGOCD_SUBDOMAIN} \
  --from-literal=BACKSTAGE_SUBDOMAIN=${BACKSTAGE_SUBDOMAIN} \
  --from-literal=KEYCLOAK_SUBDOMAIN=${KEYCLOAK_SUBDOMAIN} \
  --from-literal=GITHUB_ORG=${GITHUB_ORG} \
  --from-literal=INFRA_REPO=${INFRA_REPO} \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Backstage secret com configuração OIDC para Keycloak
# Client secret fixo deve corresponder ao configurado no keycloak-bootstrap-job
# Read GitHub token from config.yaml
GITHUB_TOKEN=$(yq eval '.github_token' ${REPO_ROOT}/config.yaml)

echo -e "${CYAN}🔐 Creating Backstage environment variables secret..."
# Create service account for Backstage Kubernetes plugin
kubectl create serviceaccount backstage-k8s -n backstage --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding backstage-k8s --clusterrole=view --serviceaccount=backstage:backstage-k8s --dry-run=client -o yaml | kubectl apply -f -

# Create secret with K8s token and other env vars
K8S_TOKEN=$(kubectl -n backstage create token backstage-k8s --duration=87600h 2>/dev/null || kubectl -n backstage create token backstage-k8s --duration=24h)
kubectl create secret generic backstage-env-vars \
  -n backstage \
  --from-literal=POSTGRES_HOST=${POSTGRES_HOST} \
  --from-literal=POSTGRES_PORT=${POSTGRES_PORT} \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  --from-literal=GITHUB_TOKEN=$GITHUB_TOKEN \
  --from-literal=ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --from-literal=BACKSTAGE_CLIENT_SECRET=${BACKSTAGE_OIDC_SECRET} \
  --from-literal=K8S_SA_TOKEN="$K8S_TOKEN" \
  --from-literal=GITHUB_ORG="$GITHUB_ORG" \
  --from-literal=INFRA_REPO="$INFRA_REPO" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$TF_BACKEND_BUCKET" \
  --from-literal=TERRAFORM_BACKEND_REGION="$TF_BACKEND_REGION" \
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

echo " Configuring ArgoCD with Keycloak SSO..."
# Create secret for ArgoCD Keycloak client
kubectl create secret generic argocd-keycloak-secret -n argocd \
  --from-literal=secret=${ARGOCD_OIDC_SECRET} \
  --dry-run=client -o yaml | kubectl apply -f -

# Configure ArgoCD OIDC with Keycloak (using dynamic domain)
KEYCLOAK_ISSUER_URL="https://${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}/auth/realms/cnoe"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  oidc.config: |
    name: Keycloak
    issuer: ${KEYCLOAK_ISSUER_URL}
    clientID: argocd
    clientSecret: \$argocd-keycloak-secret:secret
    requestedScopes:
      - openid
      - profile
      - email
      - groups
EOF

# Configure ArgoCD RBAC
kubectl -n argocd patch cm argocd-rbac-cm --type merge -p '{
  "data": {
    "policy.csv": "g, superusers, role:admin\ng, developers, role:readonly\np, role:readonly, applications, get, *, allow\np, role:readonly, clusters, get, *, allow\np, role:readonly, repositories, get, *, allow\np, role:readonly, certificates, get, *, allow",
    "policy.default": "role:readonly"
  }
}'

echo "👥 Creating Keycloak groups and users..."
# Wait for Keycloak to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=keycloak -n keycloak --timeout=300s

# Create groups in Keycloak (using dynamic domain and secrets from config)
# Bitnami Keycloak uses /opt/bitnami/keycloak and no /auth in URL path
ARGOCD_CALLBACK_URL="https://${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}/auth/callback"
kubectl exec -n keycloak keycloak-0 -- bash -c "
/opt/bitnami/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --realm master --user ${KEYCLOAK_ADMIN_USER} --password ${KEYCLOAK_ADMIN_PASSWORD}
# Create ArgoCD client if not exists
/opt/bitnami/keycloak/bin/kcadm.sh create clients -r cnoe -s clientId=argocd -s \"redirectUris=[\\\"${ARGOCD_CALLBACK_URL}\\\"]\" -s publicClient=false -s protocol=openid-connect -s enabled=true -s clientAuthenticatorType=client-secret -s \"defaultClientScopes=[\\\"openid\\\",\\\"profile\\\",\\\"email\\\",\\\"groups\\\"]\" -s secret=${ARGOCD_OIDC_SECRET} 2>/dev/null || true
# Update client if exists
CLIENT_ID=\$(/opt/bitnami/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=argocd | grep \"\\\"id\\\"\" | head -1 | sed \"s/.*\\\"id\\\" *: *\\\"\\([^\\\"]*\\)\\\".*$/\\1/\")
if [ ! -z \"\$CLIENT_ID\" ]; then
  /opt/bitnami/keycloak/bin/kcadm.sh update clients/\$CLIENT_ID -r cnoe -s secret=${ARGOCD_OIDC_SECRET} -s \"defaultClientScopes=[\\\"openid\\\",\\\"profile\\\",\\\"email\\\",\\\"groups\\\"]\"
fi
# Create groups
/opt/bitnami/keycloak/bin/kcadm.sh create groups -r cnoe -s name=superusers 2>/dev/null || true
/opt/bitnami/keycloak/bin/kcadm.sh create groups -r cnoe -s name=developers 2>/dev/null || true
"

echo "🔄 Restarting ArgoCD server to apply SSO configuration..."
kubectl rollout restart -n argocd deployment/argocd-server

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

# Apply other custom manifests (skip hub-cluster-secret.yaml as we created it directly)
for manifest in "$ARGOCD_CUSTOM_MANIFESTS_PATH"/*.yaml; do
  if [[ ! "$manifest" =~ hub-cluster-secret\.yaml$ ]]; then
    kubectl apply -f "$manifest" --kubeconfig $KUBECONFIG_FILE > /dev/null
  fi
done

kubectl apply -f "$EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH" --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Infrastructure ArgoCD Application...${NC}"
kubectl apply -f "$ARGOCD_CUSTOM_MANIFESTS_PATH/infrastructure-app.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

echo -e "${BOLD}${GREEN}🔄 Installing Addons AppSet Argo CD application...${NC}"
helm upgrade --install --wait addons-appset ${REPO_ROOT}/packages/appset-chart \
  --namespace argocd \
  --values "$ADDONS_APPSET_STATIC_VALUES_FILE" \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

# Wait for Argo CD applications to sync
sleep 10
wait_for_apps

# Configure Keycloak and Backstage integration
echo -e "\n${BOLD}${GREEN}🔐 Configuring Keycloak and Backstage integration...${NC}"

# Wait for Keycloak to be ready
echo -e "${CYAN}⏳ Waiting for Keycloak to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n keycloak --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Apply Keycloak Ingress (dynamic from config.yaml)
echo -e "${CYAN}🌐 Creating Keycloak Ingress...${NC}"
KEYCLOAK_HOST="${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keycloak
  namespace: keycloak
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${KEYCLOAK_HOST}
spec:
  ingressClassName: nginx
  rules:
  - host: ${KEYCLOAK_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keycloak
            port:
              number: 80
EOF

# Apply Backstage Ingress (dynamic from config.yaml)
echo -e "${CYAN}🌐 Creating Backstage Ingress...${NC}"
BACKSTAGE_HOST="${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
cat <<EOF | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backstage
  namespace: backstage
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${BACKSTAGE_HOST}
spec:
  ingressClassName: nginx
  rules:
  - host: ${BACKSTAGE_HOST}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: backstage
            port:
              number: 7007
EOF

# Generate dynamic Backstage values overlay with correct domain URLs
echo -e "${CYAN}🔧 Generating dynamic Backstage configuration...${NC}"
BACKSTAGE_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
KEYCLOAK_URL="https://${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"
ARGOCD_URL="https://${ARGOCD_SUBDOMAIN}.${DOMAIN_NAME}"
REPO_URL=$(yq eval '.repo.url' ${CONFIG_FILE})

cat > /tmp/backstage-dynamic-values.yaml <<EOF
ingress:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${BACKSTAGE_HOST}
  host: ${BACKSTAGE_HOST}
backstage:
  extraEnvVars:
    - name: BACKSTAGE_FRONTEND_URL
      value: ${BACKSTAGE_URL}
    - name: KEYCLOAK_NAME_METADATA
      value: ${KEYCLOAK_URL}/auth/realms/cnoe/.well-known/openid-configuration
    - name: ARGO_CD_URL
      value: ${ARGOCD_URL}
    - name: ARGO_WORKFLOWS_URL
      value: https://argo-workflows.${DOMAIN_NAME}
    - name: GITHUB_ORG
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: GITHUB_ORG
    - name: INFRA_REPO
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: INFRA_REPO
    - name: TERRAFORM_BACKEND_BUCKET
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: TERRAFORM_BACKEND_BUCKET
    - name: TERRAFORM_BACKEND_REGION
      valueFrom:
        secretKeyRef:
          name: backstage-env-vars
          key: TERRAFORM_BACKEND_REGION
  appConfig:
    catalog:
      locations:
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-s3/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-ec2/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-security-group/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-vpc/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-eks/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-secrets/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-destroy/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: https://github.com/${GITHUB_ORG}/${INFRA_REPO}/blob/main/catalog-info.yaml
          rules:
            - allow: [Location, Component, Resource, API, System]
      providers:
        github:
          infrastructureResources:
            organization: '${GITHUB_ORG}'
            catalogPath: '/platform/terraform/stacks/**/catalog-info.yaml'
            filters:
              repository: '${INFRA_REPO}'
            schedule:
              frequency: { minutes: 5 }
              timeout: { minutes: 3 }
EOF

# Create ConfigMap with dynamic Backstage values
kubectl create configmap backstage-dynamic-values \
  --namespace backstage \
  --from-file=values.yaml=/tmp/backstage-dynamic-values.yaml \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Apply Keycloak bootstrap Job
echo -e "${CYAN}🔧 Running Keycloak bootstrap Job...${NC}"
kubectl apply -f "$REPO_ROOT/packages/keycloak/keycloak-bootstrap-job.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

# Wait for Job to complete
echo -e "${CYAN}⏳ Waiting for Keycloak configuration to complete (this may take a few minutes)...${NC}"
kubectl wait --for=condition=complete --timeout=300s job/keycloak-bootstrap -n keycloak --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Extract client secret from Job logs
CLIENT_SECRET=$(kubectl logs -n keycloak job/keycloak-bootstrap --kubeconfig $KUBECONFIG_FILE | grep "Client Secret:" | awk '{print $NF}')

if [ -n "$CLIENT_SECRET" ]; then
  echo -e "${GREEN}✅ Keycloak client configured successfully!${NC}"
  echo -e "${CYAN}🔐 Updating Backstage secret with Keycloak client secret...${NC}"

  # Update Backstage secret with the actual client secret
  CLIENT_SECRET_BASE64=$(echo -n "$CLIENT_SECRET" | base64)
  kubectl -n backstage patch secret backstage-env-vars \
    -p "{\"data\":{\"BACKSTAGE_CLIENT_SECRET\":\"$CLIENT_SECRET_BASE64\",\"KEYCLOAK_NAME_METADATA\":\"$(echo -n \"https://keycloak.${DOMAIN_NAME}/auth/realms/cnoe/.well-known/openid-configuration\" | base64)\"}}" \
    --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1

  # Restart Backstage to load new secret
  echo -e "${CYAN}♻️  Restarting Backstage...${NC}\n"
  kubectl rollout restart deployment backstage -n backstage --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1
  kubectl rollout status deployment backstage -n backstage --timeout=180s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1

  echo -e "${GREEN}✅ Backstage configured successfully!${NC}"
else
  echo -e "${YELLOW}⚠️  Warning: Could not extract client secret from Keycloak Job logs.${NC}"
  echo -e "${YELLOW}   You may need to manually update the Backstage secret.${NC}"
fi

# Configure hostAliases for internal Keycloak resolution (hairpin NAT fix)
echo -e "${CYAN}🔧 Configuring internal DNS for OIDC (hostAliases)...${NC}"
KC_IP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}' --kubeconfig $KUBECONFIG_FILE 2>/dev/null)
if [ -n "$KC_IP" ]; then
  KEYCLOAK_HOST="${KEYCLOAK_SUBDOMAIN}.${DOMAIN_NAME}"

  # Add hostAliases to ArgoCD
  kubectl patch deployment argocd-server -n argocd --type='json' \
    -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/hostAliases\", \"value\": [{\"ip\": \"$KC_IP\", \"hostnames\": [\"$KEYCLOAK_HOST\"]}]}]" \
    --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Add hostAliases to Backstage
  kubectl patch deployment backstage -n backstage --type='json' \
    -p="[{\"op\": \"add\", \"path\": \"/spec/template/spec/hostAliases\", \"value\": [{\"ip\": \"$KC_IP\", \"hostnames\": [\"$KEYCLOAK_HOST\"]}]}]" \
    --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  echo -e "${GREEN}✅ hostAliases configured for ArgoCD and Backstage${NC}"
fi

echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}📊 You can now access your resources and start deploying applications.${NC}"
