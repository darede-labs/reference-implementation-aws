#!/bin/bash
# Platform health check script
# Usage: ./health-check.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "🏥 Platform Health Check"
echo "========================"
echo ""

EXIT_CODE=0

# Function to check status
check_status() {
  local name="$1"
  local command="$2"
  local expected="$3"

  printf "%-40s" "$name"

  if result=$(eval "$command" 2>&1); then
    if [[ "$result" == *"$expected"* ]] || [ -z "$expected" ]; then
      echo -e "${GREEN}✅ OK${NC}"
    else
      echo -e "${YELLOW}⚠️  WARNING${NC}"
      echo "   Expected: $expected"
      echo "   Got: $result"
      EXIT_CODE=1
    fi
  else
    echo -e "${RED}❌ FAILED${NC}"
    echo "   Error: $result"
    EXIT_CODE=1
  fi
}

# 1. Cluster connectivity
echo "🔌 Cluster Connectivity"
echo "------------------------"
check_status "Kubernetes API" "kubectl cluster-info --request-timeout=10s" "is running"
check_status "Nodes ready" "kubectl get nodes --no-headers | grep -c Ready" ""
echo ""

# 2. Core namespaces
echo "📦 Core Namespaces"
echo "------------------------"
for ns in kube-system ingress-nginx backstage argocd crossplane-system; do
  check_status "Namespace: $ns" "kubectl get namespace $ns -o name 2>/dev/null" "namespace/$ns"
done
echo ""

# 3. Critical pods
echo "🚀 Critical Workloads"
echo "------------------------"
check_status "Backstage pods" "kubectl get pods -n backstage -l app.kubernetes.io/name=backstage --field-selector=status.phase=Running --no-headers | wc -l" ""
check_status "Resource API pods" "kubectl get pods -n backstage -l app=resource-api --field-selector=status.phase=Running --no-headers | wc -l" ""
check_status "PostgreSQL pod" "kubectl get pods -n backstage -l app.kubernetes.io/name=postgresql --field-selector=status.phase=Running --no-headers | wc -l" ""
check_status "Ingress controller" "kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller --field-selector=status.phase=Running --no-headers | wc -l" ""
echo ""

# 4. PVCs
echo "💾 Persistent Volumes"
echo "------------------------"
check_status "PostgreSQL PVC bound" "kubectl get pvc -n backstage data-backstage-postgresql-0 -o jsonpath='{.status.phase}'" "Bound"
echo ""

# 5. Services
echo "🌐 Services"
echo "------------------------"
check_status "Backstage service" "kubectl get svc -n backstage backstage -o name" "service/backstage"
check_status "Resource API service" "kubectl get svc -n backstage resource-api -o name" "service/resource-api"
check_status "Ingress LB provisioned" "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'" ""
echo ""

# 6. Ingress
echo "🔀 Ingress Resources"
echo "------------------------"
BACKSTAGE_HOST=$(kubectl get ingress -n backstage backstage -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "NOT_FOUND")
if [ "$BACKSTAGE_HOST" != "NOT_FOUND" ]; then
  check_status "Backstage ingress" "echo $BACKSTAGE_HOST" "backstage"

  # Test HTTP endpoint
  if command -v curl &> /dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${BACKSTAGE_HOST}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
      printf "%-40s${GREEN}✅ OK${NC} (HTTP $HTTP_CODE)\n" "Backstage HTTPS endpoint"
    else
      printf "%-40s${RED}❌ FAILED${NC} (HTTP $HTTP_CODE)\n" "Backstage HTTPS endpoint"
      EXIT_CODE=1
    fi
  fi
else
  printf "%-40s${RED}❌ FAILED${NC}\n" "Backstage ingress"
  EXIT_CODE=1
fi
echo ""

# 7. Resource limits
echo "⚙️  Resource Configuration"
echo "------------------------"
PODS_WITHOUT_LIMITS=$(kubectl get pods -n backstage -o json | jq -r '.items[] | select(.spec.containers[0].resources.limits == null) | .metadata.name' | wc -l)
if [ "$PODS_WITHOUT_LIMITS" -eq 0 ]; then
  printf "%-40s${GREEN}✅ OK${NC}\n" "All pods have resource limits"
else
  printf "%-40s${YELLOW}⚠️  WARNING${NC} ($PODS_WITHOUT_LIMITS pods)\n" "Pods without resource limits"
  EXIT_CODE=1
fi
echo ""

# 8. PodDisruptionBudgets
echo "🛡️  High Availability"
echo "------------------------"
PDB_COUNT=$(kubectl get pdb -n backstage --no-headers 2>/dev/null | wc -l)
if [ "$PDB_COUNT" -gt 0 ]; then
  printf "%-40s${GREEN}✅ OK${NC} ($PDB_COUNT PDBs)\n" "PodDisruptionBudgets configured"
else
  printf "%-40s${YELLOW}⚠️  WARNING${NC}\n" "No PodDisruptionBudgets found"
fi
echo ""

# Summary
echo "========================================"
if [ $EXIT_CODE -eq 0 ]; then
  echo -e "${GREEN}✅ All checks passed!${NC}"
else
  echo -e "${YELLOW}⚠️  Some checks failed or need attention${NC}"
fi
echo ""

exit $EXIT_CODE
