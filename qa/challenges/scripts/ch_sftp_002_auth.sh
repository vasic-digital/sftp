#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-002 — Auth login flow returns JWT token pair
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

echo "[CH-SFTP-002] Starting API on port ${API_PORT} ..."
SANDBOX="$(mktemp -d)"
cd "$ROOT/api"
go build -o /tmp/sftp-api-ch002 ./cmd/sftp-api/ || { fail "build failed"; exit 1; }
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

/tmp/sftp-api-ch002 &
API_PID=$!

waited=0
while ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; do
    sleep 1; waited=$((waited + 1))
    [[ $waited -ge $MAX_WAIT ]] && { fail "API did not start within ${MAX_WAIT}s"; exit 1; }
done
echo "[CH-SFTP-002] API ready (PID $API_PID)"

# Test 1: wrong password → 401
HTTP_CODE=$(curl -s -o /tmp/ch002_wrong.json -w "%{http_code}" \
    -X POST "${API_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"definitely-wrong-password"}')
[[ "$HTTP_CODE" == "401" ]] && pass "login with wrong password returns 401" || fail "wrong pw: expected 401, got ${HTTP_CODE}"

# Test 2: correct password → 200 + token pair
HTTP_CODE=$(curl -s -o /tmp/ch002_ok.json -w "%{http_code}" \
    -X POST "${API_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"${ADMIN_PASS}\"}")
BODY=$(cat /tmp/ch002_ok.json)
[[ "$HTTP_CODE" == "200" ]] && pass "login with correct password returns 200" || fail "correct pw: expected 200, got ${HTTP_CODE}"

if echo "$BODY" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert 'access_token' in d, 'missing access_token'
assert 'refresh_token' in d, 'missing refresh_token'
assert d.get('token_type') == 'Bearer', f'token_type not Bearer: {d.get(\"token_type\")}'
assert isinstance(d.get('expires_in'), int), 'expires_in not integer'
" 2>/dev/null; then
    pass "JWT pair shape: access_token + refresh_token + token_type=Bearer + expires_in"
else
    fail "JWT pair shape validation failed"
fi

# Test 3: /auth/me with bearer → 200
ACCESS_TOKEN=$(echo "$BODY" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['access_token'])" 2>/dev/null || echo "")
if [[ -n "$ACCESS_TOKEN" ]]; then
    HTTP_CODE=$(curl -s -o /tmp/ch002_me.json -w "%{http_code}" \
        "${API_URL}/api/v1/auth/me" -H "Authorization: Bearer ${ACCESS_TOKEN}")
    [[ "$HTTP_CODE" == "200" ]] && pass "GET /auth/me with valid token returns 200" || fail "GET /auth/me: expected 200, got ${HTTP_CODE}"
else
    fail "could not extract access_token from login response"
fi

echo ""
echo "CH-SFTP-002: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
