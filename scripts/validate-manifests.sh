#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Manifest Validation Script
# =============================================================================
# This script validates Kubernetes manifests using yamllint and kubeconform
#
# Usage: ./validate-manifests.sh [path-to-manifests]
#
# Prerequisites:
#   - yamllint
#   - kubeconform
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFESTS_DIR="${1:-.}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
  echo -e "${RED}[ERROR]${NC} $*"
  exit 1
}

# Check prerequisites
command -v yamllint >/dev/null 2>&1 || error "yamllint is not installed. Install with: pip install yamllint"
command -v kubeconform >/dev/null 2>&1 || error "kubeconform is not installed. Install from: https://github.com/yannh/kubeconform"

# =============================================================================
# STEP 1: YAML Lint
# =============================================================================
info "Running yamllint..."

YAMLLINT_CONFIG=$(cat <<'EOF'
---
extends: default
rules:
  line-length:
    max: 120
    level: warning
  indentation:
    spaces: 2
    indent-sequences: true
  comments:
    min-spaces-from-content: 1
  document-start: disable
  truthy:
    allowed-values: ['true', 'false', 'yes', 'no']
EOF
)

echo "$YAMLLINT_CONFIG" > /tmp/yamllint-config.yaml

if yamllint -c /tmp/yamllint-config.yaml "$MANIFESTS_DIR"; then
  info "✓ yamllint passed"
else
  error "✗ yamllint failed"
fi

rm /tmp/yamllint-config.yaml

# =============================================================================
# STEP 2: Kubeconform Validation
# =============================================================================
info "Running kubeconform..."

# Find all YAML files
YAML_FILES=$(find "$MANIFESTS_DIR" -type f \( -name "*.yaml" -o -name "*.yml" \) 2>/dev/null || true)

if [ -z "$YAML_FILES" ]; then
  warn "No YAML files found in $MANIFESTS_DIR"
  exit 0
fi

FAILED=0

for file in $YAML_FILES; do
  info "Validating $file..."

  # Run kubeconform with strict validation
  if kubeconform \
    -strict \
    -ignore-missing-schemas \
    -kubernetes-version 1.28.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
    -verbose \
    "$file"; then
    info "✓ $file is valid"
  else
    error "✗ $file is invalid"
    FAILED=1
  fi
done

if [ $FAILED -eq 1 ]; then
  error "Kubeconform validation failed for one or more files"
fi

info "✓ All manifests are valid"
