#!/bin/bash
set -e -o pipefail

export REPO_ROOT=$(git rev-parse --show-toplevel)
PHASE="install"
export AWS_PROFILE=${AWS_PROFILE:-darede}
export AUTO_CONFIRM=${AUTO_CONFIRM:-yes}
INSTALL_ARGOCD=${INSTALL_ARGOCD:-false}

RUN_ID=$(date +"%Y%m%d-%H%M%S")
LOG_MODE=${LOG_MODE:-tee}
LOG_DIR=${LOG_DIR:-"${REPO_ROOT}/logs"}
LOG_FILE=${LOG_FILE:-"${LOG_DIR}/install-${RUN_ID}.log"}

if [[ "${LOG_MODE}" == "stdout" ]]; then
  LOG_FILE=""
else
  mkdir -p "${LOG_DIR}"
fi

if [[ -n "${LOG_FILE}" ]]; then
  : > "${LOG_FILE}"
  exec > >(tee -a "${LOG_FILE}") 2>&1
fi

source ${REPO_ROOT}/scripts/utils.sh

echo -e "\n${BOLD}${BLUE}🚀 Starting installation process...${NC}"

# Read config values
ACM_CERTIFICATE_ARN=$(yq eval '.acm_certificate_arn' ${CONFIG_FILE})

# Create all namespaces upfront to avoid race conditions
echo -e "${CYAN}📦 Creating namespaces...${NC}"
NAMESPACES=(backstage argo ingress-nginx external-secrets crossplane-system external-dns)
if [[ "$INSTALL_ARGOCD" == "true" ]]; then
  NAMESPACES=(argocd "${NAMESPACES[@]}")
fi
for ns in "${NAMESPACES[@]}"; do
  kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f - --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
done

echo -e "${CYAN}📦 Ensuring gp3 StorageClass exists...${NC}"
kubectl apply -f - --kubeconfig $KUBECONFIG_FILE <<EOFSC
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOFSC

if [[ "$INSTALL_ARGOCD" != "true" ]]; then
  echo -e "${CYAN}🧹 Direct mode: ensuring AWS Load Balancer Controller can be installed cleanly...${NC}"

  DIRECT_MODE_CLEANUP=${DIRECT_MODE_CLEANUP:-false}
  if [[ "$DIRECT_MODE_CLEANUP" == "true" ]]; then
    echo -e "${CYAN}🧹 Direct mode: DIRECT_MODE_CLEANUP=true; running best-effort cleanup...${NC}"

    kubectl delete namespace argocd --ignore-not-found --wait=false --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete serviceaccount/aws-load-balancer-controller -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete secret/aws-load-balancer-tls -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete secret/aws-load-balancer-tls -n kube-system --ignore-not-found --grace-period=0 --force --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete deployment/aws-load-balancer-controller -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete service/aws-load-balancer-webhook-service -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete role/aws-load-balancer-controller-leader-election-role -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete rolebinding/aws-load-balancer-controller-leader-election-rolebinding -n kube-system --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete clusterrole/aws-load-balancer-controller-role --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete clusterrolebinding/aws-load-balancer-controller-rolebinding --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete mutatingwebhookconfiguration/aws-load-balancer-webhook --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete validatingwebhookconfiguration/aws-load-balancer-webhook --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete crd/targetgroupbindings.elbv2.k8s.aws --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete crd/ingressclassparams.elbv2.k8s.aws --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

    kubectl delete ingressclassparams.elbv2.k8s.aws/alb --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl delete ingressclass/alb --ignore-not-found --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
  else
    echo -e "${CYAN}🧹 Direct mode: skipping pre-cleanup (set DIRECT_MODE_CLEANUP=true to force).${NC}"
  fi
fi

# Install AWS Load Balancer Controller (required for NLB with ACM)
echo -e "${BOLD}${GREEN}🔄 Installing AWS Load Balancer Controller...${NC}"

AWS_LBC_SA_CREATE="true"
AWS_LBC_HELM_TAKE_OWNERSHIP="false"
if [[ "$INSTALL_ARGOCD" != "true" ]]; then
  # In direct mode, avoid Helm ownership/adoption issues with pre-existing ServiceAccount.
  AWS_LBC_SA_CREATE="false"
  AWS_LBC_HELM_TAKE_OWNERSHIP="true"
  kubectl create serviceaccount aws-load-balancer-controller -n kube-system \
    --dry-run=client -o yaml | kubectl apply -f - --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

  # Re-apply ownership metadata just-in-time in case something recreated these objects.
  if kubectl get serviceaccount/aws-load-balancer-controller -n kube-system --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1; then
    kubectl annotate serviceaccount/aws-load-balancer-controller -n kube-system \
      meta.helm.sh/release-name=aws-load-balancer-controller \
      meta.helm.sh/release-namespace=kube-system \
      --overwrite --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl label serviceaccount/aws-load-balancer-controller -n kube-system \
      app.kubernetes.io/managed-by=Helm \
      --overwrite --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
  fi
  if kubectl get secret/aws-load-balancer-tls -n kube-system --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1; then
    kubectl annotate secret/aws-load-balancer-tls -n kube-system \
      meta.helm.sh/release-name=aws-load-balancer-controller \
      meta.helm.sh/release-namespace=kube-system \
      --overwrite --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
    kubectl label secret/aws-load-balancer-tls -n kube-system \
      app.kubernetes.io/managed-by=Helm \
      --overwrite --request-timeout=10s --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true
  fi
fi

helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts \
  --namespace kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=${AWS_LBC_SA_CREATE} \
  --set serviceAccount.name=aws-load-balancer-controller \
  $([[ "$AWS_LBC_HELM_TAKE_OWNERSHIP" == "true" ]] && echo "--take-ownership") \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 120s

# Install ingress-nginx with ACM certificate from config.yaml
echo -e "${BOLD}${GREEN}🔄 Installing ingress-nginx with ACM TLS termination...${NC}"
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx \
  --values ${REPO_ROOT}/packages/ingress-nginx/values.yaml \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-ssl-cert"="${ACM_CERTIFICATE_ARN}" \
  --kubeconfig $KUBECONFIG_FILE \
  --wait --timeout 300s

echo -e "${YELLOW}⏳ Waiting for NLB to be provisioned...${NC}"
sleep 30

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
if [[ "$INSTALL_ARGOCD" == "true" ]]; then
  ARGOCD_SUBDOMAIN=$(yq eval '.subdomains.argocd' ${CONFIG_FILE})
  ARGOCD_ADMIN_PASSWORD=$(yq eval '.secrets.argocd.admin_password // "argocd-admin-2024"' ${CONFIG_FILE})
  GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
  GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})

  ARGOCD_DYNAMIC_VALUES_FILE=$(mktemp)
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
  secret:
    argocdServerAdminPassword: ${ARGOCD_ADMIN_PASSWORD}
  params:
    'server.basehref': /$([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.rootpath': $([[ "${PATH_ROUTING}" == "true" ]] && echo "argocd" || echo "")
    'server.insecure': 'true'
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
add_helm_repo_with_retry "external-dns" "https://kubernetes-sigs.github.io/external-dns"

echo -e "${YELLOW}⏳ Updating helm repos...${NC}"
helm repo update > /dev/null

if [[ "$INSTALL_ARGOCD" == "true" ]]; then
  echo -e "${BOLD}${GREEN}🔄 Installing Argo CD...${NC}"
  helm upgrade --install --wait argocd argo/argo-cd \
    --namespace argocd --version $ARGOCD_CHART_VERSION \
    --create-namespace \
    --values "$ARGOCD_STATIC_VALUES_FILE" \
    --values "$ARGOCD_DYNAMIC_VALUES_FILE" \
    --timeout 3m \
    --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${YELLOW}⏳ Waiting for Argo CD to be healthy...${NC}"
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null
fi


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
  --timeout 3m \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

rm -f "$EXTERNAL_SECRETS_DYNAMIC_VALUES_FILE"

echo -e "${YELLOW}⏳ Waiting for External Secrets to be healthy...${NC}"
kubectl wait --for=condition=available deployment/external-secrets -n external-secrets --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null

if [[ "$INSTALL_ARGOCD" != "true" ]]; then
  echo -e "${BOLD}${GREEN}🔄 Installing external-dns...${NC}"
  EXTERNAL_DNS_CHART_VERSION=$(yq '.external-dns.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
  ROUTE53_HOSTED_ZONE_ID=$(yq eval '.route53_hosted_zone_id' ${CONFIG_FILE})
  helm upgrade --install --wait external-dns external-dns/external-dns \
    --namespace external-dns --version $EXTERNAL_DNS_CHART_VERSION \
    --create-namespace \
    --values "${REPO_ROOT}/packages/external-dns/values.yaml" \
    --set zoneIdFilters[0]="$ROUTE53_HOSTED_ZONE_ID" \
    --timeout 3m \
    --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${YELLOW}⏳ Waiting for external-dns to be healthy...${NC}"
  kubectl wait --for=condition=available deployment/external-dns -n external-dns --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${BOLD}${GREEN}🔄 Applying External Secrets manifests...${NC}"
  kubectl apply -f "$EXTERNAL_SECRETS_CUSTOM_MANIFESTS_PATH" --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${BOLD}${GREEN}🔄 Applying Backstage bootstrap manifests...${NC}"
  kubectl apply -f "${REPO_ROOT}/packages/backstage/manifests/terraform-installer-configmap.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null
  kubectl apply -f "${REPO_ROOT}/packages/backstage/manifests/backstage-users-configmap.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null
  kubectl apply -f "${REPO_ROOT}/packages/backstage/manifests/k8s-config-secret.yaml" --kubeconfig $KUBECONFIG_FILE > /dev/null

  # Read Backstage configuration from config.yaml
  BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
  GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
  GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
  INFRA_REPO=$(yq eval '.infrastructure_repo' ${CONFIG_FILE})
  TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
  TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' ${CONFIG_FILE})

  # Cognito OIDC configuration - read from Terraform outputs
  echo -e "${CYAN}🔐 Reading Cognito configuration from Terraform state...${NC}"
  COGNITO_ISSUER_URL=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_issuer_url 2>/dev/null || echo "")
  COGNITO_CLIENT_ID=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_backstage_client_id 2>/dev/null || echo "")
  COGNITO_CLIENT_SECRET=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_backstage_client_secret 2>/dev/null || echo "")
  OIDC_ISSUER_URL="${COGNITO_ISSUER_URL}"

  if [ -z "$OIDC_ISSUER_URL" ] || [ "$OIDC_ISSUER_URL" = "null" ]; then
    echo -e "${RED}❌ ERROR: Cognito not configured in Terraform state${NC}"
    exit 1
  fi

  echo -e "${GREEN}✅ Cognito configuration loaded from Terraform${NC}"

  # Create Cognito users from catalog
  echo -e "${CYAN}👤 Creating Cognito users from catalog...${NC}"
  COGNITO_USER_POOL_ID=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_user_pool_id 2>/dev/null || echo "")
  DEFAULT_PASSWORD=$(yq eval '.secrets.cognito.default_password // "ChangeMe@2024!"' ${CONFIG_FILE})

  if [ -n "$COGNITO_USER_POOL_ID" ] && [ "$COGNITO_USER_POOL_ID" != "null" ]; then
    # Extract emails from users-catalog.yaml
    USER_EMAILS=$(yq eval '.[] | select(.kind == "User") | .spec.profile.email' ${REPO_ROOT}/packages/backstage/users-catalog.yaml)

    for EMAIL in $USER_EMAILS; do
      echo -e "  📧 Checking user: ${EMAIL}"

      # Check if user exists
      USER_EXISTS=$(aws cognito-idp list-users \
        --user-pool-id "$COGNITO_USER_POOL_ID" \
        --filter "email = \"$EMAIL\"" \
        --region $(echo $COGNITO_USER_POOL_ID | cut -d'_' -f1) \
        ${AWS_PROFILE:+--profile $AWS_PROFILE} 2>/dev/null | jq -r '.Users | length')

      if [ "$USER_EXISTS" = "0" ]; then
        echo -e "    ➕ Creating user in Cognito..."
        aws cognito-idp admin-create-user \
          --user-pool-id "$COGNITO_USER_POOL_ID" \
          --username "$EMAIL" \
          --user-attributes Name=email,Value="$EMAIL" Name=email_verified,Value=true \
          --region $(echo $COGNITO_USER_POOL_ID | cut -d'_' -f1) \
          ${AWS_PROFILE:+--profile $AWS_PROFILE} > /dev/null 2>&1 || true

        # Set permanent password
        aws cognito-idp admin-set-user-password \
          --user-pool-id "$COGNITO_USER_POOL_ID" \
          --username "$EMAIL" \
          --password "$DEFAULT_PASSWORD" \
          --permanent \
          --region $(echo $COGNITO_USER_POOL_ID | cut -d'_' -f1) \
          ${AWS_PROFILE:+--profile $AWS_PROFILE} > /dev/null 2>&1 || true

        echo -e "    ✅ User created with default password"
      else
        echo -e "    ℹ️  User already exists"
      fi
    done

    echo -e "${GREEN}✅ Cognito users synchronized${NC}"
    echo -e "${YELLOW}📋 Default password: ${DEFAULT_PASSWORD}${NC}"
  fi

  # Backstage secrets
  AUTH_SESSION_SECRET=$(yq eval '.secrets.backstage.auth_session_secret // "backstage-session-secret-2024"' ${CONFIG_FILE})
  BACKEND_SECRET=$(yq eval '.secrets.backstage.backend_secret // "backstage-backend-secret-2024"' ${CONFIG_FILE})
  POSTGRES_HOST=$(yq eval '.secrets.backstage.postgres_host // "backstage-postgresql"' ${CONFIG_FILE})
  POSTGRES_PORT=$(yq eval '.secrets.backstage.postgres_port // "5432"' ${CONFIG_FILE})
  POSTGRES_USER=$(yq eval '.secrets.backstage.postgres_user // "backstage"' ${CONFIG_FILE})
  POSTGRES_PASSWORD=$(yq eval '.secrets.backstage.postgres_password // "backstage123"' ${CONFIG_FILE})

  # Backstage Frontend URL
  BACKSTAGE_FRONTEND_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"

  BACKSTAGE_HOST="${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
  BACKSTAGE_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"
  ARGO_WORKFLOWS_URL="https://argo-workflows.${DOMAIN_NAME}"
  REPO_URL=$(yq eval '.repo.url' ${CONFIG_FILE})

  echo -e "${CYAN}🔐 Creating Backstage environment variables secret..."
  kubectl create serviceaccount backstage-k8s -n backstage --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null
  kubectl create clusterrolebinding backstage-k8s --clusterrole=view --serviceaccount=backstage:backstage-k8s --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null

  K8S_TOKEN=$(kubectl -n backstage create token backstage-k8s --duration=87600h --kubeconfig $KUBECONFIG_FILE 2>/dev/null || kubectl -n backstage create token backstage-k8s --duration=24h --kubeconfig $KUBECONFIG_FILE)
  kubectl create secret generic backstage-env-vars \
    -n backstage \
    --from-literal=POSTGRES_HOST=${POSTGRES_HOST} \
    --from-literal=POSTGRES_PORT=${POSTGRES_PORT} \
    --from-literal=POSTGRES_USER=${POSTGRES_USER} \
    --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
    --from-literal=GITHUB_TOKEN=$GITHUB_TOKEN \
    --from-literal=ARGO_WORKFLOWS_URL="${ARGO_WORKFLOWS_URL}" \
    --from-literal=OIDC_ISSUER_URL="${OIDC_ISSUER_URL}" \
    --from-literal=OIDC_CLIENT_ID="${COGNITO_CLIENT_ID}" \
    --from-literal=OIDC_CLIENT_SECRET="${COGNITO_CLIENT_SECRET}" \
    --from-literal=AUTH_SESSION_SECRET="${AUTH_SESSION_SECRET}" \
    --from-literal=BACKEND_SECRET="${BACKEND_SECRET}" \
    --from-literal=BACKSTAGE_FRONTEND_URL="${BACKSTAGE_FRONTEND_URL}" \
    --from-literal=K8S_SA_TOKEN="$K8S_TOKEN" \
    --from-literal=GITHUB_ORG="$GITHUB_ORG" \
    --from-literal=INFRA_REPO="$INFRA_REPO" \
    --from-literal=TERRAFORM_BACKEND_BUCKET="$TF_BACKEND_BUCKET" \
    --from-literal=TERRAFORM_BACKEND_REGION="$TF_BACKEND_REGION" \
    --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null

  cat > /tmp/backstage-dynamic-values.yaml <<EOF
ingress:
  annotations:
    external-dns.alpha.kubernetes.io/hostname: ${BACKSTAGE_HOST}
  host: ${BACKSTAGE_HOST}
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/backstage-terraform-irsa
backstage:
  appConfig:
    proxy:
      # Remove ArgoCD proxy in direct mode (ARGO_CD_URL undefined)
      '/argocd/api': null
    catalog:
      locations:
        - type: file
          target: /catalog/users-catalog.yaml
          rules:
            - allow: [User, Group]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-s3/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-ec2-ssm/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-vpc/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/terraform-destroy/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: ${REPO_URL}/blob/main/templates/backstage/resource-manager/template.yaml
          rules:
            - allow: [Template, Location, Component, Resource, API, System]
        - type: url
          target: https://github.com/${GITHUB_ORG}/${INFRA_REPO}/blob/main/catalog-info.yaml
          rules:
            - allow: [Location, Component, Resource, API, System]
EOF

  echo -e "${BOLD}${GREEN}🔄 Installing Backstage...${NC}"
  BACKSTAGE_CHART_VERSION=$(yq '.backstage.defaultVersion' ${REPO_ROOT}/packages/addons/values.yaml)
  helm upgrade --install --wait backstage backstage/backstage \
    --namespace backstage --version $BACKSTAGE_CHART_VERSION \
    --create-namespace \
    --values "${REPO_ROOT}/packages/backstage/values.yaml" \
    --values "/tmp/backstage-dynamic-values.yaml" \
    --timeout 3m \
    --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${YELLOW}⏳ Waiting for Backstage to be healthy...${NC}"
  kubectl wait --for=condition=available deployment/backstage -n backstage --timeout=300s --kubeconfig $KUBECONFIG_FILE > /dev/null

  echo -e "${GREEN}✅ Backstage installed (direct mode)${NC}"
  echo -e "${GREEN}✅ Installation completed successfully!${NC}"
  exit 0
fi

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
echo -e "${CYAN}🔐 Creating application secrets for Backstage, Argo Workflows...${NC}"

# Read Backstage configuration from config.yaml
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' ${CONFIG_FILE})
GITHUB_ORG=$(yq eval '.github_org' ${CONFIG_FILE})
GITHUB_TOKEN=$(yq eval '.github_token' ${CONFIG_FILE})
INFRA_REPO=$(yq eval '.infrastructure_repo' ${CONFIG_FILE})
TF_BACKEND_BUCKET=$(yq eval '.terraform_backend.bucket' ${CONFIG_FILE})
TF_BACKEND_REGION=$(yq eval '.terraform_backend.region // "us-east-1"' ${CONFIG_FILE})

# Cognito OIDC configuration - read from Terraform outputs (not config.yaml)
echo -e "${CYAN}🔐 Reading Cognito configuration from Terraform state...${NC}"
COGNITO_ISSUER_URL=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_issuer_url 2>/dev/null || echo "")
COGNITO_CLIENT_ID=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_backstage_client_id 2>/dev/null || echo "")
COGNITO_CLIENT_SECRET=$(terraform -chdir="$REPO_ROOT/cluster/terraform" output -raw cognito_backstage_client_secret 2>/dev/null || echo "")
OIDC_ISSUER_URL="${COGNITO_ISSUER_URL}"

if [ -z "$COGNITO_ISSUER_URL" ] || [ "$COGNITO_ISSUER_URL" = "null" ]; then
  echo -e "${RED}❌ ERROR: Cognito not configured in Terraform state${NC}"
  echo -e "${YELLOW}⚠️  Make sure cluster was created with Terraform (not eksctl)${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Cognito configuration loaded from Terraform${NC}"

# Backstage secrets
AUTH_SESSION_SECRET=$(yq eval '.secrets.backstage.auth_session_secret // "backstage-session-secret-2024"' ${CONFIG_FILE})
BACKEND_SECRET=$(yq eval '.secrets.backstage.backend_secret // "backstage-backend-secret-2024"' ${CONFIG_FILE})
POSTGRES_HOST=$(yq eval '.secrets.backstage.postgres_host // "backstage-postgresql"' ${CONFIG_FILE})
POSTGRES_PORT=$(yq eval '.secrets.backstage.postgres_port // "5432"' ${CONFIG_FILE})
POSTGRES_USER=$(yq eval '.secrets.backstage.postgres_user // "backstage"' ${CONFIG_FILE})
POSTGRES_PASSWORD=$(yq eval '.secrets.backstage.postgres_password // "backstage123"' ${CONFIG_FILE})

# Backstage Frontend URL
BACKSTAGE_FRONTEND_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"

echo -e "${CYAN}🔐 Creating Backstage environment variables secret..."
# Create service account for Backstage Kubernetes plugin
kubectl create serviceaccount backstage-k8s -n backstage --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE
kubectl create clusterrolebinding backstage-k8s --clusterrole=view --serviceaccount=backstage:backstage-k8s --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE

# Create secret with K8s token and other env vars
K8S_TOKEN=$(kubectl -n backstage create token backstage-k8s --duration=87600h --kubeconfig $KUBECONFIG_FILE 2>/dev/null || kubectl -n backstage create token backstage-k8s --duration=24h --kubeconfig $KUBECONFIG_FILE)
kubectl create secret generic backstage-env-vars \
  -n backstage \
  --from-literal=POSTGRES_HOST=${POSTGRES_HOST} \
  --from-literal=POSTGRES_PORT=${POSTGRES_PORT} \
  --from-literal=POSTGRES_USER=${POSTGRES_USER} \
  --from-literal=POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  --from-literal=GITHUB_TOKEN=$GITHUB_TOKEN \
  --from-literal=ARGOCD_ADMIN_PASSWORD=${ARGOCD_ADMIN_PASSWORD} \
  --from-literal=OIDC_ISSUER_URL="${OIDC_ISSUER_URL}" \
  --from-literal=OIDC_CLIENT_ID="${COGNITO_CLIENT_ID}" \
  --from-literal=OIDC_CLIENT_SECRET="${COGNITO_CLIENT_SECRET}" \
  --from-literal=AUTH_SESSION_SECRET="${AUTH_SESSION_SECRET}" \
  --from-literal=BACKEND_SECRET="${BACKEND_SECRET}" \
  --from-literal=BACKSTAGE_FRONTEND_URL="${BACKSTAGE_FRONTEND_URL}" \
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

echo "✅ ArgoCD configured with admin password from config.yaml"
# ArgoCD is now configured with simple admin password
# OIDC/SSO can be added later if needed via ArgoCD ConfigMap

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
  --timeout 3m \
  --kubeconfig $KUBECONFIG_FILE > /dev/null

# Wait for Argo CD applications to sync
sleep 10
wait_for_apps

# Backstage integration with AWS Cognito
echo -e "\n${BOLD}${GREEN}🔐 Backstage configured with AWS Cognito OIDC...${NC}"

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
EOF

# Create ConfigMap with dynamic Backstage values
kubectl create configmap backstage-dynamic-values \
  --namespace backstage \
  --from-file=values.yaml=/tmp/backstage-dynamic-values.yaml \
  --dry-run=client -o yaml | kubectl apply -f - --kubeconfig $KUBECONFIG_FILE > /dev/null 2>&1 || true

echo -e "${GREEN}✅ Backstage configured with AWS Cognito OIDC${NC}"
echo -e "${CYAN}📋 Backstage uses Cognito for authentication - no Keycloak bootstrap needed${NC}"

echo -e "\n${BOLD}${BLUE}🎉 Installation completed successfully! 🎉${NC}"
echo -e "${CYAN}📊 You can now access your resources and start deploying applications.${NC}"
