#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-003 — Account CRUD lifecycle (create list read update delete)
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
API_PORT="${API_PORT:-7722}"
API_URL="http://127.0.0.1:${API_PORT}"
MAX_WAIT=30

PASS_COUNT=0
FAIL_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; }

cleanup() {
    [[ -n "${API_PID:-}" ]] && { kill "$API_PID" 2>/dev/null; wait "$API_PID" 2>/dev/null; } || true
    [[ -n "${SANDBOX:-}" ]] && rm -rf "$SANDBOX"
}
trap cleanup EXIT

echo "[CH-SFTP-003] Starting API on port ${API_PORT} ..."
SANDBOX="$(mktemp -d)"
cd "$ROOT/api"
go build -o /tmp/sftp-api-ch003 ./cmd/sftp-api/ || { fail "build failed"; exit 1; }
mkdir -p "$ROOT/data"

ADMIN_PASS="$(openssl rand -hex 16)"
export SFTP_PORT=7721
export API_PORT="${API_PORT}"
export API_BIND=127.0.0.1
export API_LOG_LEVEL=info
export DB_DRIVER=sqlite
export DB_PATH="${SANDBOX}/sftp.db"
export USERS_CONF_PATH="${SANDBOX}/users.conf"
export JWT_SECRET="$(openssl rand -hex 32)"
export JWT_ISSUER=sftp-enterprise
export ACCESS_TOKEN_TTL=24h
export REFRESH_TOKEN_TTL=168h
export SUPERADMIN_USERNAME=admin
export SUPERADMIN_PASSWORD="${ADMIN_PASS}"
export FIREBASE_ENABLED=false
export I18N_DEFAULT_LANG=en
export VAULT_DATA_DIR="${SANDBOX}/vault"

/tmp/sftp-api-ch003 &
API_PID=$!

waited=0
while ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; do
    sleep 1; waited=$((waited + 1))
    [[ $waited -ge $MAX_WAIT ]] && { fail "API did not start within ${MAX_WAIT}s"; exit 1; }
done
echo "[CH-SFTP-003] API ready (PID $API_PID)"

# Login
LOGIN_RESP=$(curl -s -X POST "${API_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}")
ACCESS_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['access_token'])" 2>/dev/null || echo "")
[[ -z "$ACCESS_TOKEN" ]] && { fail "could not obtain access token"; exit 1; }
AUTH="-H Authorization: Bearer\\ ${ACCESS_TOKEN}"

TEST_USER="crdtest-$(date +%s)"

# Create
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/v1/accounts" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d "{\"username\":\"${TEST_USER}\",\"password\":\"testpass123\",\"permission\":\"read_write\",\"public_acknowledged\":false}")
[[ "$HTTP_CODE" == "201" ]] && pass "create ${TEST_USER} (read_write) → 201" || fail "create: expected 201, got ${HTTP_CODE}"

# List
LIST=$(curl -s "${API_URL}/api/v1/accounts" -H "Authorization: Bearer ${ACCESS_TOKEN}")
[[ $? -eq 0 ]] && echo "$LIST" | grep -q "\"username\":\"${TEST_USER}\"" && pass "list accounts includes ${TEST_USER}" || fail "list does not include ${TEST_USER}"

# Read
HTTP_CODE=$(curl -s -o /tmp/ch003_read.json -w "%{http_code}" "${API_URL}/api/v1/accounts/${TEST_USER}" -H "Authorization: Bearer ${ACCESS_TOKEN}")
[[ "$HTTP_CODE" == "200" ]] && grep -q "\"username\":\"${TEST_USER}\"" /tmp/ch003_read.json && pass "read ${TEST_USER} → 200" || fail "read: expected 200 with correct username, got ${HTTP_CODE}"

# Update to read_only
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "${API_URL}/api/v1/accounts/${TEST_USER}" \
    -H 'Content-Type: application/json' -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -d '{"permission":"read_only"}')
[[ "$HTTP_CODE" == "200" ]] && pass "update to read_only → 200" || fail "update: expected 200, got ${HTTP_CODE}"

# Verify update
HTTP_CODE=$(curl -s -o /tmp/ch003_verify.json -w "%{http_code}" "${API_URL}/api/v1/accounts/${TEST_USER}" -H "Authorization: Bearer ${ACCESS_TOKEN}")
[[ "$HTTP_CODE" == "200" ]] && grep -q '"read_only"' /tmp/ch003_verify.json && pass "verify updated permission is read_only" || fail "verify: not read_only or code ${HTTP_CODE}"

# Delete
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "${API_URL}/api/v1/accounts/${TEST_USER}" -H "Authorization: Bearer ${ACCESS_TOKEN}")
[[ "$HTTP_CODE" == "204" ]] && pass "delete ${TEST_USER} → 204" || fail "delete: expected 204, got ${HTTP_CODE}"

# Confirm deletion
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/v1/accounts/${TEST_USER}" -H "Authorization: Bearer ${ACCESS_TOKEN}")
[[ "$HTTP_CODE" == "404" ]] && pass "GET deleted account → 404 (confirmed removed)" || fail "GET deleted: expected 404, got ${HTTP_CODE}"

echo ""
echo "CH-SFTP-003: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
