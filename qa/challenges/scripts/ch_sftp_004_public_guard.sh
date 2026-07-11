#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-004 — Public access guard rejects unacknowledged public account
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

echo "[CH-SFTP-004] Starting API on port ${API_PORT} ..."
SANDBOX="$(mktemp -d)"
cd "$ROOT/api"
go build -o /tmp/sftp-api-ch004 ./cmd/sftp-api/ || { fail "build failed"; exit 1; }
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

/tmp/sftp-api-ch004 &
API_PID=$!

waited=0
while ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; do
    sleep 1; waited=$((waited + 1))
    [[ $waited -ge $MAX_WAIT ]] && { fail "API did not start within ${MAX_WAIT}s"; exit 1; }
done
echo "[CH-SFTP-004] API ready (PID $API_PID)"

# Login
LOGIN_RESP=$(curl -s -X POST "${API_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}")
ACCESS_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['access_token'])" 2>/dev/null || echo "")
[[ -z "$ACCESS_TOKEN" ]] && { fail "could not obtain access token"; exit 1; }
AUTH="Authorization: Bearer ${ACCESS_TOKEN}"

TEST_USER="pubguard-$(date +%s)"

# Test 1: public without acknowledgement → 422
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/v1/accounts" \
    -H 'Content-Type: application/json' -H "$AUTH" \
    -d "{\"username\":\"${TEST_USER}\",\"password\":\"testpass123\",\"permission\":\"public\",\"public_acknowledged\":false}")
[[ "$HTTP_CODE" == "422" ]] && pass "public w/o ack → 422" || fail "public w/o ack: expected 422, got ${HTTP_CODE}"

# Test 2: public with missing acknowledgement → 422
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/v1/accounts" \
    -H 'Content-Type: application/json' -H "$AUTH" \
    -d "{\"username\":\"${TEST_USER}2\",\"password\":\"testpass123\",\"permission\":\"public\"}")
[[ "$HTTP_CODE" == "422" ]] && pass "public missing ack → 422" || fail "public missing ack: expected 422, got ${HTTP_CODE}"

# Test 3: public with acknowledgement → 201 (guard is real, not blanket)
TEST_USER3="pubguard-ack-$(date +%s)"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${API_URL}/api/v1/accounts" \
    -H 'Content-Type: application/json' -H "$AUTH" \
    -d "{\"username\":\"${TEST_USER3}\",\"password\":\"testpass123\",\"permission\":\"public\",\"public_acknowledged\":true}")
[[ "$HTTP_CODE" == "201" ]] && pass "public with ack → 201 (guard not blanket)" || fail "public with ack: expected 201, got ${HTTP_CODE}"

# Cleanup test account
[[ "$HTTP_CODE" == "201" ]] && curl -s -X DELETE "${API_URL}/api/v1/accounts/${TEST_USER3}" -H "$AUTH" >/dev/null 2>&1 || true

echo ""
echo "CH-SFTP-004: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
