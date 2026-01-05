#!/bin/bash
# List resources created by a specific user from Terraform state bucket
# Usage: ./list-my-resources.sh <owner_email> [bucket_name]

set -e

OWNER_EMAIL="${1:-}"
BUCKET="${2:-poc-idp-tfstate}"
REGION="${3:-us-east-1}"

if [ -z "$OWNER_EMAIL" ]; then
    echo "Usage: $0 <owner_email> [bucket_name] [region]"
    exit 1
fi

# Extract owner username from email
OWNER=$(echo "$OWNER_EMAIL" | cut -d'@' -f1)

echo "=== Resources owned by: $OWNER ($OWNER_EMAIL) ==="
echo ""
echo "TYPE           | NAME                                    | STATE KEY"
echo "---------------|----------------------------------------|------------------------------------------"

# List all state files and filter by owner path
aws s3 ls "s3://${BUCKET}/" --recursive 2>/dev/null | grep "terraform.tfstate$" | while read -r line; do
    STATE_KEY=$(echo "$line" | awk '{print $4}')

    # Check if this state belongs to the owner (new format: type/owner/name/terraform.tfstate)
    if echo "$STATE_KEY" | grep -q "/${OWNER}/"; then
        TYPE=$(echo "$STATE_KEY" | cut -d'/' -f1)
        NAME=$(echo "$STATE_KEY" | cut -d'/' -f3)
        printf "%-14s | %-40s | %s\n" "$TYPE" "$NAME" "$STATE_KEY"
    fi

    # Also check platform format: platform/terraform/stacks/type/name/terraform.tfstate
    if echo "$STATE_KEY" | grep -q "^platform/terraform/stacks/"; then
        TYPE=$(echo "$STATE_KEY" | cut -d'/' -f4)
        NAME=$(echo "$STATE_KEY" | cut -d'/' -f5)
        printf "%-14s | %-40s | %s\n" "$TYPE" "$NAME" "$STATE_KEY"
    fi
done

echo ""
echo "To delete a resource, use the Resource Manager template in Backstage"
echo "or run: terraform destroy with the appropriate state key"
