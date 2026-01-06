#!/bin/bash
# Sync values.yaml to backstage-app-config ConfigMap
# Run this after editing values.yaml to apply changes immediately

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="$SCRIPT_DIR/values.yaml"
NAMESPACE="backstage"

echo "🔄 Syncing Backstage configuration..."

# Extract app-config from values.yaml
yq eval '.backstage.appConfig' "$VALUES_FILE" > /tmp/app-config-temp.yaml

# Create ConfigMap with updated config
kubectl create configmap backstage-app-config \
  -n "$NAMESPACE" \
  --from-file=app-config.yaml=/tmp/app-config-temp.yaml \
  --dry-run=client -o yaml | kubectl apply -f -

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
echo "🌐 Access: https://backstage.timedevops.click"
echo "⏱️  Wait 2 minutes for catalog refresh"

rm -f /tmp/app-config-temp.yaml
