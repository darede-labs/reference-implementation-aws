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
ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)
ISSUER_URL=$([[ "${PATH_ROUTING}" == "false" ]] && echo "keycloak.${DOMAIN_NAME}" || echo "${DOMAIN_NAME}/keycloak")
cat << EOF > "$ARGOCD_DYNAMIC_VALUES_FILE"
cnoe_ref_impl: # Specific values for reference CNOE implementation to control extraObjects.
  auto_mode: $([[ "${AUTO_MODE}" == "true" ]] && echo '"true"' || echo '"false"')
global:
  domain: $([[ "${PATH_ROUTING}" == "true" ]] && echo "${DOMAIN_NAME}" || echo "argocd.${DOMAIN_NAME}")
server:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: $([[ "${PATH_ROUTING}" == "false" ]] && echo '"letsencrypt-prod"' || echo "")
    path: /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
configs:
  cm:
    oidc.config: |
      name: Keycloak
      issuer: https://$ISSUER_URL/auth/realms/cnoe
      clientID: argocd
      clientSecret: argocd-secret-2024
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

# Keycloak secret
kubectl create secret generic keycloak \
  --namespace keycloak \
  --from-literal=admin-password=admin \
  --from-literal=management-password=manager123 \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

# Create ConfigMap with domain configuration for Keycloak bootstrap
ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' ${CONFIG_FILE})
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
KEYCLOAK_SUBDOMAIN=$(yq eval '.subdomains.keycloak' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
INFRA_REPO=$(yq eval '.infrastructure_repo' ${CONFIG_FILE})
TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' ${CONFIG_FILE})
TF_LOCKS_TABLE=$(yq eval '.terraform_backend.dynamodb_table' ${CONFIG_FILE})

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
  --from-literal=POSTGRES_HOST=backstage-postgresql \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_USER=backstage \
  --from-literal=POSTGRES_PASSWORD=backstage123 \
  --from-literal=GITHUB_TOKEN=$GITHUB_TOKEN \
  --from-literal=ARGOCD_ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) \
  --from-literal=BACKSTAGE_CLIENT_SECRET=backstage-secret-2024 \
  --from-literal=K8S_SA_TOKEN="$K8S_TOKEN" \
  --from-literal=GITHUB_ORG="$GITHUB_ORG" \
  --from-literal=INFRA_REPO="$INFRA_REPO" \
  --from-literal=TERRAFORM_BACKEND_BUCKET="$TF_BACKEND_BUCKET" \
  --from-literal=TERRAFORM_BACKEND_REGION="$TF_BACKEND_REGION" \
  --from-literal=TERRAFORM_LOCKS_TABLE="$TF_LOCKS_TABLE" \
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

echo "🔧 Creating secret for ArgoCD GitHub OAuth integration..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: argocd-github-oauth-secret
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-github-oauth-secret
    app.kubernetes.io/part-of: argocd
type: Opaque
data:
  clientId: $(echo -n "$github_oauth_client_id" | base64)
  clientSecret: $(echo -n "$github_oauth_client_secret" | base64)
EOF

echo "🔐 Configuring ArgoCD with Keycloak SSO..."
# Create secret for ArgoCD Keycloak client
kubectl create secret generic argocd-keycloak-secret -n argocd \
  --from-literal=secret=argocd-secret-2024 \
  --dry-run=client -o yaml | kubectl apply -f -

# Configure ArgoCD OIDC with Keycloak
kubectl -n argocd patch cm argocd-cm --type merge -p '{
  "data": {
    "oidc.config": "name: Keycloak\nissuer: https://keycloak.timedevops.click/auth/realms/cnoe\nclientID: argocd\nclientSecret: $argocd-keycloak-secret:secret\nrequestedScopes:\n  - openid\n  - profile\n  - email\n  - groups"
  }
}'

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

# Create groups in Keycloak
kubectl exec -n keycloak keycloak-0 -- bash -c '
/opt/jboss/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080/auth --realm master --user admin --password admin
# Create ArgoCD client if not exists
/opt/jboss/keycloak/bin/kcadm.sh create clients -r cnoe -s clientId=argocd -s "redirectUris=[\"https://argocd.timedevops.click/auth/callback\"]" -s publicClient=false -s protocol=openid-connect -s enabled=true -s clientAuthenticatorType=client-secret -s "defaultClientScopes=[\"openid\",\"profile\",\"email\",\"groups\"]" -s secret=argocd-secret-2024 2>/dev/null || true
# Update client if exists
CLIENT_ID=$(/opt/jboss/keycloak/bin/kcadm.sh get clients -r cnoe -q clientId=argocd | grep "\"id\"" | head -1 | sed "s/.*\"id\" *: *\"\([^\"]*\)\".*/\1/")
if [ ! -z "$CLIENT_ID" ]; then
  /opt/jboss/keycloak/bin/kcadm.sh update clients/$CLIENT_ID -r cnoe -s secret=argocd-secret-2024 -s "defaultClientScopes=[\"openid\",\"profile\",\"email\",\"groups\"]"
fi
# Create groups
/opt/jboss/keycloak/bin/kcadm.sh create groups -r cnoe -s name=superusers 2>/dev/null || true
/opt/jboss/keycloak/bin/kcadm.sh create groups -r cnoe -s name=developers 2>/dev/null || true
'

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

# Apply Keycloak Ingress
echo -e "${CYAN}🌐 Creating Keycloak Ingress...${NC}"
kubectl apply -f "$REPO_ROOT/packages/keycloak/keycloak-ingress.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

# Apply Backstage Ingress (if not already applied)
echo -e "${CYAN}🌐 Creating Backstage Ingress...${NC}"
kubectl apply -f "$REPO_ROOT/packages/backstage/backstage-ingress.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

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

echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}📊 You can now access your resources and start deploying applications.${NC}"
