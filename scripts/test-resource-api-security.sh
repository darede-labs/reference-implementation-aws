#!/bin/bash
# Test Resource API security fixes (WAVE 1.6 validation)

set -e

BASE_URL="https://backstage.timedevops.click/api/resources/resources"

echo "============================================"
echo "WAVE 1.6 - Resource API Security Tests"
echo "============================================"
echo ""

# Test 1: Unauthenticated request
echo "Test 1: Unauthenticated request (should fail with 401)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL")
if [ "$HTTP_CODE" = "401" ]; then
  echo "✅ PASS - Returns 401 Unauthorized"
else
  echo "❌ FAIL - Expected 401, got $HTTP_CODE"
  exit 1
fi
echo ""

# Test 2: Attempt to enumerate other user's resources
echo "Test 2: Cross-user enumeration attempt (should fail with 403)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Backstage-User: user:default/admin" \
  "$BASE_URL?owner=other-user")
if [ "$HTTP_CODE" = "403" ]; then
  echo "✅ PASS - Returns 403 Forbidden"
else
  echo "❌ FAIL - Expected 403, got $HTTP_CODE"
  exit 1
fi
echo ""

# Test 3: Authenticated user lists own resources
echo "Test 3: Authenticated user lists own resources (should succeed with 200)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Backstage-User: user:default/admin" \
  "$BASE_URL?owner=admin")
if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ PASS - Returns 200 OK"
else
  echo "❌ FAIL - Expected 200, got $HTTP_CODE"
  exit 1
fi
echo ""

# Test 4: Authenticated user with no owner param (defaults to authenticated user)
echo "Test 4: Authenticated user without owner param (should succeed with 200)"
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "X-Backstage-User: user:default/matheus-andrade" \
  "$BASE_URL")
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ PASS - Returns 200 OK"
  echo "Response: $BODY"
else
  echo "❌ FAIL - Expected 200, got $HTTP_CODE"
  exit 1
fi
echo ""

echo "============================================"
echo "✅ ALL SECURITY TESTS PASSED"
echo "============================================"
