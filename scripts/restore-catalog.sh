#!/bin/bash
# Restore Backstage catalog to PostgreSQL
# Usage: ./restore-catalog.sh <backup-file.sql.gz>

set -e

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ] || [ ! -f "$BACKUP_FILE" ]; then
  echo "❌ Usage: $0 <backup-file.sql.gz>"
  echo "   Example: $0 backups/backstage-catalog-20260112_104500.sql.gz"
  exit 1
fi

echo "🔄 Backstage Catalog Restore"
echo "=============================="
echo "📁 Source: $BACKUP_FILE"
echo ""

# Warn user
read -p "⚠️  This will OVERWRITE the current database. Continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Restore cancelled"
  exit 0
fi

# Get PostgreSQL credentials
echo "📋 Reading PostgreSQL credentials..."
POSTGRES_PASSWORD=$(kubectl get secret -n backstage backstage-postgresql -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌ Failed to retrieve PostgreSQL password"
  exit 1
fi

# Decompress if needed
RESTORE_FILE="$BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.gz ]]; then
  echo "🗜️  Decompressing backup..."
  RESTORE_FILE="${BACKUP_FILE%.gz}"
  gunzip -c "$BACKUP_FILE" > "$RESTORE_FILE"
  CLEANUP_FILE="$RESTORE_FILE"
fi

# Port-forward to PostgreSQL
echo "🔌 Creating port-forward to PostgreSQL..."
kubectl port-forward -n backstage svc/backstage-postgresql 5432:5432 &
PF_PID=$!
sleep 3

# Perform restore
echo "♻️  Restoring database..."
PGPASSWORD="$POSTGRES_PASSWORD" pg_restore \
  -h localhost \
  -p 5432 \
  -U postgres \
  -d backstage \
  --clean \
  --if-exists \
  "$RESTORE_FILE" || {
    echo "❌ Restore failed"
    kill $PF_PID 2>/dev/null
    [ -n "$CLEANUP_FILE" ] && rm -f "$CLEANUP_FILE"
    exit 1
  }

# Cleanup
kill $PF_PID 2>/dev/null
[ -n "$CLEANUP_FILE" ] && rm -f "$CLEANUP_FILE"

echo ""
echo "✅ Restore complete!"
echo "🔄 Restart Backstage pods to apply changes:"
echo "   kubectl rollout restart deployment/backstage -n backstage"
