#!/bin/bash
# Sync values.yaml to backstage-app-config ConfigMap
# Run this after editing values.yaml to apply changes immediately

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="$SCRIPT_DIR/values.yaml"
CONFIG_FILE="$(cd "$SCRIPT_DIR/../.." && pwd)/config.yaml"
NAMESPACE="backstage"

echo "🔄 Syncing Backstage configuration..."

# Read domain from config.yaml
DOMAIN_NAME=$(yq eval '.domain' "$CONFIG_FILE")
BACKSTAGE_SUBDOMAIN=$(yq eval '.subdomains.backstage' "$CONFIG_FILE")
BACKSTAGE_URL="https://${BACKSTAGE_SUBDOMAIN}.${DOMAIN_NAME}"

# Extract app-config from values.yaml
yq eval '.backstage.appConfig' "$VALUES_FILE" > /tmp/app-config-temp.yaml

# Create ConfigMap with updated config
kubectl create configmap backstage-app-config \
  -n "$NAMESPACE" \
  --from-file=app-config.yaml=/tmp/app-config-temp.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

# Update BACKSTAGE_FRONTEND_URL in env vars secret if it changed
echo "🔐 Updating BACKSTAGE_FRONTEND_URL in secret..."
kubectl patch secret backstage-env-vars -n "$NAMESPACE" \
  -p "{\"stringData\":{\"BACKSTAGE_FRONTEND_URL\":\"$BACKSTAGE_URL\"}}" \
  --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1 || true

# Restart Backstage pod
echo "🔄 Restarting Backstage pod..."
kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/name=backstage

# Wait for pod to be ready
echo "⏳ Waiting for Backstage to be ready..."
kubectl wait --for=condition=ready pod \
  -n "$NAMESPACE" \
  -l app.kubernetes.io/name=backstage \
  --timeout=120s

echo "✅ Backstage configuration synced and restarted successfully!"
echo "🌐 Access: $BACKSTAGE_URL"
echo "⏱️  Wait 2 minutes for catalog refresh"

rm -f /tmp/app-config-temp.yaml
