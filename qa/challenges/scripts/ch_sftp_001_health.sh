#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-001 — API health check returns ok
# ----------------------------------------------------------------------------
# Challenge: The unauthenticated /api/v1/health endpoint MUST return HTTP 200
# with a JSON body containing status ok, a version string, and a firebase field.
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
    if [[ -n "${API_PID:-}" ]]; then
        kill "$API_PID" 2>/dev/null || true
        wait "$API_PID" 2>/dev/null || true
    fi
    [[ -n "${SANDBOX:-}" ]] && rm -rf "$SANDBOX"
}
trap cleanup EXIT

# --- Start the API ---
if ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; then
    echo "[CH-SFTP-001] Starting API on port ${API_PORT} ..."
    SANDBOX="$(mktemp -d)"
    cd "$ROOT/api"
    go build -o /tmp/sftp-api-ch001 ./cmd/sftp-api/ || {
        fail "cannot build API binary"
        exit 1
    }
    mkdir -p "$ROOT/data"

    # Export env vars for the API binary (uses os.Getenv, not .env file).
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

    /tmp/sftp-api-ch001 &
    API_PID=$!

    waited=0
    while ! curl -s "${API_URL}/api/v1/health" >/dev/null 2>&1; do
        sleep 1
        waited=$((waited + 1))
        if [[ $waited -ge $MAX_WAIT ]]; then
            fail "API did not start within ${MAX_WAIT}s"
            exit 1
        fi
    done
    echo "[CH-SFTP-001] API ready (PID $API_PID)"
fi

# --- Run the health check ---
echo "[CH-SFTP-001] Checking health endpoint ..."
HTTP_CODE=$(curl -s -o /tmp/ch001_health.json -w "%{http_code}" "${API_URL}/api/v1/health")

if [[ "$HTTP_CODE" != "200" ]]; then
    fail "expected HTTP 200, got ${HTTP_CODE}"
else
    pass "health endpoint returns HTTP 200"
    BODY=$(cat /tmp/ch001_health.json)
    if echo "$BODY" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
assert d.get('status') == 'ok', f'status not ok: {d.get(\"status\")}'
assert 'version' in d, 'missing version'
assert 'firebase' in d, 'missing firebase'
" 2>/dev/null; then
        pass "health JSON: status=ok, version present, firebase present"
    else
        fail "health JSON validation failed"
        echo "Body: $BODY"
    fi
fi

echo ""
echo "CH-SFTP-001: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
