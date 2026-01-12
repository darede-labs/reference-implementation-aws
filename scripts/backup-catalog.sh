#!/bin/bash
# Backup Backstage catalog from PostgreSQL
# Usage: ./backup-catalog.sh [output-dir]

set -e

BACKUP_DIR="${1:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/backstage-catalog-${TIMESTAMP}.sql"

echo "🔒 Backstage Catalog Backup"
echo "=============================="

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Get PostgreSQL credentials from secret
echo "📋 Reading PostgreSQL credentials..."
POSTGRES_PASSWORD=$(kubectl get secret -n backstage backstage-postgresql -o jsonpath='{.data.password}' | base64 -d)

if [ -z "$POSTGRES_PASSWORD" ]; then
  echo "❌ Failed to retrieve PostgreSQL password"
  exit 1
fi

# Port-forward to PostgreSQL
echo "🔌 Creating port-forward to PostgreSQL..."
kubectl port-forward -n backstage svc/backstage-postgresql 5432:5432 &
PF_PID=$!
sleep 3

# Perform backup
echo "💾 Backing up database..."
PGPASSWORD="$POSTGRES_PASSWORD" pg_dump \
  -h localhost \
  -p 5432 \
  -U postgres \
  -d backstage \
  -F c \
  -f "$BACKUP_FILE" || {
    echo "❌ Backup failed"
    kill $PF_PID 2>/dev/null
    exit 1
  }

# Cleanup
kill $PF_PID 2>/dev/null

# Compress backup
echo "🗜️  Compressing backup..."
gzip "$BACKUP_FILE"
BACKUP_FILE="${BACKUP_FILE}.gz"

# Calculate size
SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

echo ""
echo "✅ Backup complete!"
echo "📁 File: $BACKUP_FILE"
echo "📊 Size: $SIZE"
echo ""
echo "To restore:"
echo "  ./scripts/restore-catalog.sh $BACKUP_FILE"
