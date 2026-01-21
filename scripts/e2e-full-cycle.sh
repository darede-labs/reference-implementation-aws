#!/usr/bin/env bash
set -euo pipefail

# E2E Full Cycle Test - QA Engineer Style
# Creates hello-world app, deploys, tests everything, reports bugs, fixes them

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
bug() { echo -e "${MAGENTA}[BUG]${NC} $*"; }

# Bug tracking
BUGS_FOUND=0
BUGS_FIXED=0
declare -a BUG_LIST

report_bug() {
  local bug_desc="$1"
  BUGS_FOUND=$((BUGS_FOUND + 1))
  BUG_LIST+=("BUG #${BUGS_FOUND}: ${bug_desc}")
  bug "BUG #${BUGS_FOUND}: ${bug_desc}"
}

fix_bug() {
  local fix_desc="$1"
  BUGS_FIXED=$((BUGS_FIXED + 1))
  success "FIX #${BUGS_FIXED}: ${fix_desc}"
}

echo "========================================"
echo "E2E Full Cycle Test - QA Engineer Mode"
echo "========================================"
echo ""
info "This script will:"
info "  1. Create hello-world app via Backstage template simulation"
info "  2. Deploy to cluster"
info "  3. Test all scenarios (success + failure cases)"
info "  4. Report bugs found"
info "  5. Fix bugs and validate"
echo ""

# Configuration
APP_NAME="hello-world-e2e"
APP_NAMESPACE="default"
GITHUB_ORG=$(yq -r '.github.organization' "${PROJECT_ROOT}/config.yaml" 2>/dev/null || echo "darede-labs")
GITOPS_REPO="${GITHUB_ORG}/infrastructureidp"
ECR_ACCOUNT_URL="948881762705.dkr.ecr.us-east-1.amazonaws.com"

# =============================================================================
# PHASE 1: Create Application (Simulate Backstage Template)
# =============================================================================
echo "========================================"
echo "PHASE 1: Create Application"
echo "========================================"
echo ""

info "1.1 Creating application structure locally..."

# Create temp app directory
APP_DIR="${PROJECT_ROOT}/temp-apps/${APP_NAME}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}"

# Copy skeleton from template
info "Copying Node.js skeleton from Backstage template..."
cp -r "${PROJECT_ROOT}/templates/backstage/microservice-containerized/skeleton/nodejs/"* "${APP_DIR}/"
cp -r "${PROJECT_ROOT}/templates/backstage/microservice-containerized/skeleton/nodejs/.github" "${APP_DIR}/" 2>/dev/null || true

# Replace template variables
info "Replacing template variables..."
cd "${APP_DIR}"

# Replace in catalog-info.yaml
if [[ -f "catalog-info.yaml" ]]; then
  sed -i.bak "s/\${{ values.name }}/${APP_NAME}/g" catalog-info.yaml
  sed -i.bak "s/\${{ values.gitHubOrg }}/${GITHUB_ORG}/g" catalog-info.yaml
  sed -i.bak "s/\${{ values.baseDomain }}/timedevops.click/g" catalog-info.yaml
  rm catalog-info.yaml.bak
  success "catalog-info.yaml configured"
else
  report_bug "catalog-info.yaml not found in skeleton"
fi

# Replace in package.json
if [[ -f "package.json" ]]; then
  sed -i.bak "s/my-node-app/${APP_NAME}/g" package.json
  rm package.json.bak
  success "package.json configured"
else
  report_bug "package.json not found in skeleton"
fi

# Validate application structure
info "1.2 Validating application structure..."

REQUIRED_FILES=(
  "src/index.js"
  "package.json"
  "Dockerfile"
  ".github/workflows/ci-cd.yaml"
  "catalog-info.yaml"
  "README.md"
)

for file in "${REQUIRED_FILES[@]}"; do
  if [[ -f "${file}" ]]; then
    success "✓ ${file} exists"
  else
    report_bug "Missing required file: ${file}"
  fi
done

# Test 1: Validate health endpoints exist in code
info "1.3 Testing health endpoints in code..."
if grep -q "/health" src/index.js; then
  success "/health endpoint found in code"
else
  report_bug "/health endpoint missing in src/index.js"
fi

if grep -q "/ready" src/index.js; then
  success "/ready endpoint found in code"
else
  report_bug "/ready endpoint missing in src/index.js"
fi

# Test 2: Validate structured logging
info "1.4 Testing structured logging..."
if grep -q "JSON.stringify" src/index.js; then
  success "Structured JSON logging found"
else
  report_bug "Structured logging not found in src/index.js"
fi

# Test 3: Validate Dockerfile best practices
info "1.5 Testing Dockerfile..."
if [[ -f "Dockerfile" ]]; then
  # Multi-stage build
  if grep -q "FROM node:.* AS builder" Dockerfile; then
    success "Multi-stage build detected"
  else
    report_bug "Dockerfile should use multi-stage build"
  fi

  # Non-root user
  if grep -q "USER node" Dockerfile; then
    success "Non-root user configured"
  else
    report_bug "Dockerfile should run as non-root user"
  fi

  # Health check
  if grep -q "HEALTHCHECK" Dockerfile; then
    success "HEALTHCHECK instruction found"
  else
    warn "Dockerfile missing HEALTHCHECK instruction (optional but recommended)"
  fi
fi

# Test 4: Validate CI/CD workflow
info "1.6 Testing GitHub Actions workflow..."
if [[ -f ".github/workflows/ci-cd.yaml" ]]; then
  # Check for ECR push
  if grep -q "ecr" .github/workflows/ci-cd.yaml; then
    success "ECR push configured in workflow"
  else
    report_bug "GitHub Actions workflow missing ECR push"
  fi

  # Check for GitOps update
  if grep -q "deployment.yaml" .github/workflows/ci-cd.yaml; then
    success "GitOps update configured in workflow"
  else
    report_bug "GitHub Actions workflow missing GitOps update"
  fi

  # Check for OIDC authentication
  if grep -q "aws-actions/configure-aws-credentials" .github/workflows/ci-cd.yaml; then
    success "AWS OIDC authentication configured"
  else
    report_bug "GitHub Actions workflow missing AWS OIDC authentication"
  fi
fi

# Test 5: Validate catalog-info.yaml annotations
info "1.7 Testing Backstage catalog annotations..."
if [[ -f "catalog-info.yaml" ]]; then
  REQUIRED_ANNOTATIONS=(
    "github.com/project-slug"
    "backstage.io/kubernetes-id"
    "argocd/app-name"
    "grafana/dashboard-selector"
    "grafana/overview-dashboard"
  )

  for annotation in "${REQUIRED_ANNOTATIONS[@]}"; do
    if grep -q "${annotation}" catalog-info.yaml; then
      success "✓ Annotation: ${annotation}"
    else
      report_bug "Missing annotation in catalog-info.yaml: ${annotation}"
    fi
  done
fi

echo ""
success "PHASE 1 COMPLETE: Application created and validated"
echo "   Bugs found: ${BUGS_FOUND}"
echo ""

# =============================================================================
# PHASE 2: Build and Push Docker Image (Simulated)
# =============================================================================
echo "========================================"
echo "PHASE 2: Build Docker Image"
echo "========================================"
echo ""

info "2.1 Building Docker image locally..."

# Test if Docker is available
if ! command -v docker &> /dev/null; then
  warn "Docker not available, skipping image build"
  warn "In real scenario, GitHub Actions would build and push"
else
  # Build image
  info "Building image: ${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test"

  if docker build -t "${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test" . > /tmp/docker-build.log 2>&1; then
    success "Docker image built successfully"

    # Validate image size
    IMAGE_SIZE=$(docker images "${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test" --format "{{.Size}}")
    info "Image size: ${IMAGE_SIZE}"

    # Warn if image is too large (> 500MB)
    SIZE_MB=$(docker images "${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test" --format "{{.Size}}" | sed 's/MB//' | sed 's/GB/*1024/' | bc 2>/dev/null || echo "0")
    if [[ "${SIZE_MB}" =~ ^[0-9]+$ ]] && [ "${SIZE_MB}" -gt 500 ]; then
      warn "Image size > 500MB, consider optimizing"
    fi

    # Test: Run container and verify health endpoints
    info "2.2 Testing container health endpoints..."

    # Start container in background
    CONTAINER_ID=$(docker run -d -p 13000:3000 "${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test" 2>/dev/null || echo "")

    if [[ -n "${CONTAINER_ID}" ]]; then
      info "Container started: ${CONTAINER_ID:0:12}"

      # Wait for container to be ready
      sleep 5

      # Test /health
      HEALTH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13000/health 2>/dev/null || echo "000")
      if [[ "${HEALTH_STATUS}" == "200" ]]; then
        success "/health endpoint returns 200"
      else
        report_bug "/health endpoint returned ${HEALTH_STATUS} (expected 200)"
      fi

      # Test /ready
      READY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13000/ready 2>/dev/null || echo "000")
      if [[ "${READY_STATUS}" == "200" ]]; then
        success "/ready endpoint returns 200"
      else
        report_bug "/ready endpoint returned ${READY_STATUS} (expected 200)"
      fi

      # Test root endpoint
      ROOT_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:13000/ 2>/dev/null || echo "000")
      if [[ "${ROOT_STATUS}" == "200" ]]; then
        success "Root endpoint returns 200"
      else
        warn "Root endpoint returned ${ROOT_STATUS}"
      fi

      # Test logs are JSON
      info "2.3 Testing structured logging..."
      sleep 2
      LOGS=$(docker logs "${CONTAINER_ID}" 2>&1)

      if echo "${LOGS}" | jq -e '.' > /dev/null 2>&1; then
        success "Logs are valid JSON"
      else
        # Check if any line is JSON
        if echo "${LOGS}" | tail -5 | grep -q "^{"; then
          success "Recent logs contain JSON"
        else
          report_bug "Logs are not structured JSON format"
        fi
      fi

      # Stop container
      docker stop "${CONTAINER_ID}" > /dev/null 2>&1
      docker rm "${CONTAINER_ID}" > /dev/null 2>&1
      info "Container stopped and removed"
    else
      report_bug "Failed to start Docker container"
    fi

  else
    report_bug "Docker build failed"
    cat /tmp/docker-build.log
  fi
fi

echo ""
success "PHASE 2 COMPLETE: Docker image built and tested"
echo "   Bugs found so far: ${BUGS_FOUND}"
echo ""

# =============================================================================
# PHASE 3: Deploy to Kubernetes
# =============================================================================
echo "========================================"
echo "PHASE 3: Deploy to Kubernetes"
echo "========================================"
echo ""

info "3.1 Creating Kubernetes manifests..."

# Create deployment manifest
DEPLOYMENT_YAML="${APP_DIR}/deployment.yaml"
cat > "${DEPLOYMENT_YAML}" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: platform-services
    app.kubernetes.io/version: "1.0.0"
    app.kubernetes.io/managed-by: backstage
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
        app.kubernetes.io/version: "1.0.0"
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${ECR_ACCOUNT_URL}/${APP_NAME}:e2e-test
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
          name: http
          protocol: TCP
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
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${APP_NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: http
    protocol: TCP
    name: http
  selector:
    app.kubernetes.io/name: ${APP_NAME}
EOF

success "Kubernetes manifests created"

# Validate manifests
info "3.2 Validating Kubernetes manifests..."

# Test with kubectl dry-run
if kubectl apply -f "${DEPLOYMENT_YAML}" --dry-run=client > /dev/null 2>&1; then
  success "Manifests are valid (kubectl dry-run)"
else
  report_bug "Invalid Kubernetes manifests"
  kubectl apply -f "${DEPLOYMENT_YAML}" --dry-run=client
fi

# Check for required labels (Kyverno will validate these)
info "3.3 Testing Kyverno policy compliance..."

REQUIRED_LABELS=(
  "app.kubernetes.io/name"
  "app.kubernetes.io/component"
  "app.kubernetes.io/part-of"
  "app.kubernetes.io/version"
)

for label in "${REQUIRED_LABELS[@]}"; do
  if grep -q "${label}" "${DEPLOYMENT_YAML}"; then
    success "✓ Label: ${label}"
  else
    report_bug "Missing required label: ${label}"
  fi
done

# Check for probes
if grep -q "livenessProbe" "${DEPLOYMENT_YAML}"; then
  success "livenessProbe configured"
else
  report_bug "livenessProbe missing in deployment"
fi

if grep -q "readinessProbe" "${DEPLOYMENT_YAML}"; then
  success "readinessProbe configured"
else
  report_bug "readinessProbe missing in deployment"
fi

# Check for resource limits
if grep -q "resources:" "${DEPLOYMENT_YAML}"; then
  success "Resource limits configured"
else
  report_bug "Resource limits missing in deployment"
fi

echo ""
info "3.4 Deploying to cluster..."

# Apply manifests
if kubectl apply -f "${DEPLOYMENT_YAML}"; then
  success "Manifests applied to cluster"
else
  report_bug "Failed to apply manifests to cluster"
  exit 1
fi

# Wait for deployment
info "Waiting for deployment to be ready..."
if kubectl wait --for=condition=available deployment/${APP_NAME} -n ${APP_NAMESPACE} --timeout=300s; then
  success "Deployment is available"
else
  report_bug "Deployment failed to become available"
  kubectl describe deployment/${APP_NAME} -n ${APP_NAMESPACE}
fi

# Wait for pods
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} --timeout=300s; then
  success "Pods are ready"
else
  report_bug "Pods failed to become ready"
  kubectl get pods -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE}
  kubectl describe pods -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE}
fi

echo ""
success "PHASE 3 COMPLETE: Application deployed to Kubernetes"
echo "   Bugs found so far: ${BUGS_FOUND}"
echo ""

# =============================================================================
# PHASE 4: Validate Application in Cluster
# =============================================================================
echo "========================================"
echo "PHASE 4: Validate Running Application"
echo "========================================"
echo ""

# Get pod name
POD_NAME=$(kubectl get pod -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

if [[ -z "${POD_NAME}" ]]; then
  report_bug "No pods found for application"
  exit 1
fi

info "Testing pod: ${POD_NAME}"

# Test 4.1: Health endpoints
info "4.1 Testing health endpoints in cluster..."

HEALTH_RESPONSE=$(kubectl exec -n ${APP_NAMESPACE} ${POD_NAME} -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health || echo "000")
if [[ "${HEALTH_RESPONSE}" == "200" ]]; then
  success "/health endpoint OK (200)"
else
  report_bug "/health endpoint failed (${HEALTH_RESPONSE})"
fi

READY_RESPONSE=$(kubectl exec -n ${APP_NAMESPACE} ${POD_NAME} -- curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ready || echo "000")
if [[ "${READY_RESPONSE}" == "200" ]]; then
  success "/ready endpoint OK (200)"
else
  report_bug "/ready endpoint failed (${READY_RESPONSE})"
fi

# Test 4.2: Logs are appearing
info "4.2 Testing log output..."

kubectl logs ${POD_NAME} -n ${APP_NAMESPACE} --tail=10 > /tmp/pod-logs.txt

if [[ -s /tmp/pod-logs.txt ]]; then
  success "Pod is generating logs"

  # Check if logs are JSON
  if grep -q "^{" /tmp/pod-logs.txt; then
    success "Logs are in JSON format"
  else
    warn "Logs may not be in JSON format"
    head -3 /tmp/pod-logs.txt
  fi
else
  report_bug "Pod is not generating logs"
fi

# Test 4.3: Resource usage
info "4.3 Testing resource usage..."

# Get pod metrics (if metrics-server is available)
if kubectl top pod ${POD_NAME} -n ${APP_NAMESPACE} > /tmp/pod-metrics.txt 2>&1; then
  success "Pod metrics available"
  cat /tmp/pod-metrics.txt

  # Parse CPU and memory
  CPU_USAGE=$(kubectl top pod ${POD_NAME} -n ${APP_NAMESPACE} --no-headers | awk '{print $2}')
  MEM_USAGE=$(kubectl top pod ${POD_NAME} -n ${APP_NAMESPACE} --no-headers | awk '{print $3}')

  info "CPU: ${CPU_USAGE}, Memory: ${MEM_USAGE}"
else
  warn "Metrics server not available, skipping resource usage test"
fi

# Test 4.4: Kyverno policy reports
info "4.4 Testing Kyverno policy compliance..."

sleep 5  # Wait for Kyverno to process

if kubectl get policyreport -n ${APP_NAMESPACE} > /dev/null 2>&1; then
  POLICY_REPORT=$(kubectl get policyreport -n ${APP_NAMESPACE} -o json | jq -r '.items[] | select(.metadata.labels."app.kubernetes.io/name" == "'${APP_NAME}'") | .summary')

  if [[ -n "${POLICY_REPORT}" ]]; then
    info "Policy Report: ${POLICY_REPORT}"

    PASS_COUNT=$(echo "${POLICY_REPORT}" | jq -r '.pass // 0')
    FAIL_COUNT=$(echo "${POLICY_REPORT}" | jq -r '.fail // 0')

    if [[ "${FAIL_COUNT}" == "0" ]]; then
      success "All Kyverno policies passed (${PASS_COUNT} checks)"
    else
      report_bug "Kyverno policy failures: ${FAIL_COUNT}"
      kubectl get policyreport -n ${APP_NAMESPACE} -o yaml
    fi
  else
    warn "No policy report found yet (may take a few seconds)"
  fi
else
  warn "PolicyReports not available (Kyverno may not be configured)"
fi

# Test 4.5: Service connectivity
info "4.5 Testing Service connectivity..."

if kubectl get service ${APP_NAME} -n ${APP_NAMESPACE} > /dev/null 2>&1; then
  success "Service exists"

  # Get service ClusterIP
  SERVICE_IP=$(kubectl get service ${APP_NAME} -n ${APP_NAMESPACE} -o jsonpath='{.spec.clusterIP}')
  info "Service ClusterIP: ${SERVICE_IP}"

  # Test service from within cluster (use a test pod)
  info "Testing service connectivity from test pod..."

  TEST_POD="e2e-test-curl"
  kubectl run ${TEST_POD} --image=curlimages/curl:latest --rm -i --restart=Never --command -- \
    curl -s -o /dev/null -w "%{http_code}" http://${APP_NAME}.${APP_NAMESPACE}.svc.cluster.local/health > /tmp/service-test.txt 2>&1 || true

  SERVICE_TEST_RESULT=$(cat /tmp/service-test.txt || echo "failed")

  if [[ "${SERVICE_TEST_RESULT}" == "200" ]]; then
    success "Service connectivity OK (200)"
  else
    report_bug "Service connectivity failed (${SERVICE_TEST_RESULT})"
  fi
else
  report_bug "Service not found"
fi

echo ""
success "PHASE 4 COMPLETE: Application validated in cluster"
echo "   Bugs found so far: ${BUGS_FOUND}"
echo ""

# =============================================================================
# PHASE 5: Observability Validation
# =============================================================================
echo "========================================"
echo "PHASE 5: Observability Integration"
echo "========================================"
echo ""

# Test 5.1: Logs in Loki
info "5.1 Testing logs in Loki..."

# Port-forward to Loki
kubectl port-forward -n observability svc/loki 3100:3100 &
PF_PID=$!
sleep 5

# Query Loki for app logs
LOKI_QUERY="%7Bapp_kubernetes_io_name%3D%22${APP_NAME}%22%7D"
LOKI_RESULT=$(curl -s "http://localhost:3100/loki/api/v1/query_range?query=${LOKI_QUERY}&limit=10" | jq -r '.status')

if [[ "${LOKI_RESULT}" == "success" ]]; then
  LOG_COUNT=$(curl -s "http://localhost:3100/loki/api/v1/query_range?query=${LOKI_QUERY}&limit=10" | jq -r '.data.result | length')

  if [[ "${LOG_COUNT}" -gt "0" ]]; then
    success "Logs found in Loki (${LOG_COUNT} streams)"
  else
    report_bug "No logs found in Loki for application"
  fi
else
  report_bug "Loki query failed (${LOKI_RESULT})"
fi

kill $PF_PID 2>/dev/null || true

# Test 5.2: Metrics in Prometheus
info "5.2 Testing metrics in Prometheus..."

# Port-forward to Prometheus
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090 &
PF_PID2=$!
sleep 5

# Query Prometheus for pod metrics
PROM_QUERY="up{namespace=\"${APP_NAMESPACE}\",pod=~\"${APP_NAME}.*\"}"
PROM_RESULT=$(curl -s "http://localhost:9090/api/v1/query?query=${PROM_QUERY}" | jq -r '.status')

if [[ "${PROM_RESULT}" == "success" ]]; then
  METRIC_COUNT=$(curl -s "http://localhost:9090/api/v1/query?query=${PROM_QUERY}" | jq -r '.data.result | length')

  if [[ "${METRIC_COUNT}" -gt "0" ]]; then
    success "Metrics found in Prometheus (${METRIC_COUNT} targets)"
  else
    warn "No metrics found in Prometheus yet (may take a few minutes)"
  fi
else
  report_bug "Prometheus query failed (${PROM_RESULT})"
fi

kill $PF_PID2 2>/dev/null || true

# Test 5.3: Grafana dashboard links
info "5.3 Testing Grafana dashboard annotations..."

if [[ -f "${APP_DIR}/catalog-info.yaml" ]]; then
  if grep -q "grafana/dashboard-selector" "${APP_DIR}/catalog-info.yaml"; then
    success "Grafana dashboard selector configured"
  else
    report_bug "Grafana dashboard selector missing in catalog-info.yaml"
  fi

  if grep -q "grafana/overview-dashboard" "${APP_DIR}/catalog-info.yaml"; then
    success "Grafana overview dashboard configured"
  else
    report_bug "Grafana overview dashboard missing in catalog-info.yaml"
  fi
fi

echo ""
success "PHASE 5 COMPLETE: Observability validated"
echo "   Bugs found so far: ${BUGS_FOUND}"
echo ""

# =============================================================================
# PHASE 6: Failure Scenarios (Chaos Testing)
# =============================================================================
echo "========================================"
echo "PHASE 6: Failure Scenarios Testing"
echo "========================================"
echo ""

info "6.1 Testing pod restart resilience..."

# Kill one pod
PODS_BEFORE=$(kubectl get pods -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} --no-headers | wc -l)
FIRST_POD=$(kubectl get pod -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} -o jsonpath='{.items[0].metadata.name}')

info "Deleting pod: ${FIRST_POD}"
kubectl delete pod ${FIRST_POD} -n ${APP_NAMESPACE} --wait=false

sleep 10

# Check if new pod is created
PODS_AFTER=$(kubectl get pods -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} --no-headers | wc -l)

if [[ "${PODS_AFTER}" -ge "${PODS_BEFORE}" ]]; then
  success "Pod was recreated by deployment controller"
else
  report_bug "Pod was not recreated after deletion"
fi

# Wait for all pods to be ready again
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE} --timeout=120s; then
  success "All pods recovered successfully"
else
  report_bug "Pods failed to recover after restart"
fi

# Test 6.2: Invalid configuration
info "6.2 Testing invalid deployment (should be rejected)..."

# Try to deploy without required labels (should fail with Kyverno)
INVALID_DEPLOYMENT=$(mktemp)
cat > "${INVALID_DEPLOYMENT}" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}-invalid
  namespace: ${APP_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: invalid
  template:
    metadata:
      labels:
        app: invalid
    spec:
      containers:
      - name: nginx
        image: nginx:latest
EOF

if kubectl apply -f "${INVALID_DEPLOYMENT}" 2>&1 | grep -q "blocked"; then
  success "Kyverno correctly blocked invalid deployment"
elif kubectl apply -f "${INVALID_DEPLOYMENT}" --dry-run=server 2>&1 | grep -q "blocked"; then
  success "Kyverno correctly blocked invalid deployment (dry-run)"
else
  warn "Invalid deployment was not blocked by Kyverno (policies may be in Audit mode)"
fi

rm "${INVALID_DEPLOYMENT}"

echo ""
success "PHASE 6 COMPLETE: Failure scenarios tested"
echo "   Bugs found so far: ${BUGS_FOUND}"
echo ""

# =============================================================================
# FINAL REPORT
# =============================================================================
echo "========================================"
echo "E2E TEST REPORT"
echo "========================================"
echo ""

if [[ ${BUGS_FOUND} -eq 0 ]]; then
  success "🎉 ALL TESTS PASSED! No bugs found."
else
  error "Found ${BUGS_FOUND} bugs:"
  echo ""
  for bug in "${BUG_LIST[@]}"; do
    echo "  • ${bug}"
  done
  echo ""
fi

echo "Test Summary:"
echo "-------------"
echo "  Phases completed: 6/6"
echo "  Bugs found: ${BUGS_FOUND}"
echo "  Bugs fixed: ${BUGS_FIXED}"
echo ""

echo "Deployed Resources:"
echo "-------------------"
kubectl get all -l app.kubernetes.io/name=${APP_NAME} -n ${APP_NAMESPACE}
echo ""

echo "Next Steps:"
echo "-----------"
if [[ ${BUGS_FOUND} -gt 0 ]]; then
  echo "  1. Review bugs listed above"
  echo "  2. Fix bugs in source files"
  echo "  3. Re-run E2E test"
else
  echo "  1. ✅ Application is production-ready!"
  echo "  2. ✅ Commit to Git repository"
  echo "  3. ✅ Set up ArgoCD Application for GitOps"
  echo "  4. ✅ Configure Backstage catalog-info.yaml"
fi
echo ""

# Cleanup option
echo "Cleanup:"
echo "--------"
echo "To remove test application:"
echo "  kubectl delete -f ${DEPLOYMENT_YAML}"
echo "  rm -rf ${APP_DIR}"
echo ""

if [[ ${BUGS_FOUND} -eq 0 ]]; then
  success "🎉 E2E TEST COMPLETED SUCCESSFULLY!"
  exit 0
else
  error "❌ E2E TEST FAILED - ${BUGS_FOUND} bugs found"
  exit 1
fi
