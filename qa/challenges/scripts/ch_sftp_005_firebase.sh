#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-005 — Firebase graceful degrade when disabled
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

echo "[CH-SFTP-005] Starting API on port ${API_PORT} (FIREBASE_ENABLED=false) ..."
SANDBOX="$(mktemp -d)"
cd "$ROOT/api"
go build -o /tmp/sftp-api-ch005 ./cmd/sftp-api/ || { fail "build failed"; exit 1; }
mkdir -p "$ROOT/data"

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
export SUPERADMIN_PASSWORD="$(openssl rand -hex 16)"
export FIREBASE_ENABLED=false
export I18N_DEFAULT_LANG=en
export VAULT_DATA_DIR="${SANDBOX}/vault"

/tmp/sftp-api-ch005 &
API_PID=$!

waited=0
while ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; do
    sleep 1; waited=$((waited + 1))
    [[ $waited -ge $MAX_WAIT ]] && { fail "API did not start within ${MAX_WAIT}s"; exit 1; }
done
echo "[CH-SFTP-005] API ready (PID $API_PID)"

# Test 1: API is alive
HTTP_CODE=$(curl -s -o /tmp/ch005_health.json -w "%{http_code}" "${API_URL}/api/v1/health")
[[ "$HTTP_CODE" == "200" ]] && pass "API serves health endpoint (200)" || fail "health: expected 200, got ${HTTP_CODE}"

# Test 2: firebase field is unavailable or disabled
FIREBASE_STATE=$(python3 -c "
import sys, json
fb = json.loads(sys.stdin.read()).get('firebase', 'MISSING')
print(fb)
" < /tmp/ch005_health.json 2>/dev/null || echo "PARSE_ERROR")

if [[ "$FIREBASE_STATE" == "unavailable" || "$FIREBASE_STATE" == "disabled" ]]; then
    pass "firebase field is '${FIREBASE_STATE}' (expected unavailable or disabled)"
else
    fail "firebase: expected 'unavailable' or 'disabled', got '${FIREBASE_STATE}'"
fi

# Test 3: API continues to serve traffic (no crash after health)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${API_URL}/api/v1/health")
[[ "$HTTP_CODE" == "200" ]] && pass "API continues to serve traffic (no crash)" || fail "API second health: expected 200, got ${HTTP_CODE}"

echo ""
echo "CH-SFTP-005: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
