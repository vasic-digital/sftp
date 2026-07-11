#!/usr/bin/env bash
# ============================================================================
# test_e2e_operator_journey.sh — full end-to-end operator journey integration
# test against the REAL sftp-api binary (STREAM-9, §11.4)
# ----------------------------------------------------------------------------
# Purpose:
#   Exercises the complete operator lifecycle through the live HTTP surface
#   exactly as a human operator would experience it:
#     1. start API → health check → login
#     2. create alice (read_write) → create bob (read_only)
#     3. list accounts → 2 accounts present
#     4. update bob to read_write
#     5. sync → verify users.conf atmoz grammar (both accounts)
#     6. list again → confirm bob permission flipped
#     7. delete alice → GET alice → 404
#     8. final health check
#
#   Every PASS cites its captured evidence file (response body / status /
#   rendered users.conf) under qa/results/stream9/e2e_<timestamp>/ — a PASS
#   without the real running API is a defect by definition (§11.4).
#
# Usage:
#   tests/e2e/test_e2e_operator_journey.sh
#   SFTP_API_BINARY=/path/to/sftp-api tests/e2e/test_e2e_operator_journey.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox when SFTP_API_BINARY is
#   unset). Secrets generated per-run via openssl (never printed).
#
# Outputs:
#   qa/results/stream9/e2e_<timestamp>/ — api.log, per-step response bodies,
#   users.conf render, verdict. Exit 0 ONLY when every check PASSes.
#
# Side-effects:
#   One mktemp sandbox (DB, users.conf, secrets) + evidence dir; sandbox
#   removed on EXIT, API stopped gracefully (§11.4.14). No repo files are
#   modified.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24 (or SFTP_API_BINARY), curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · tests/api/test_api_lifecycle.sh ·
#   api/internal/api/handlers_*.go · api/internal/sftpsync/sftpsync.go ·
#   constitution §11.4.2, §11.4.5, §11.4.10, §11.4.14, §11.4.69.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

RUN="$ROOT/qa/results/stream9/e2e_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API end-to-end operator journey test ==="
echo "evidence: $RUN"

cleanup() { api_harness_stop; [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"; }
trap cleanup EXIT

api_harness_start "$RUN" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started on random port with temp DB + generated secrets" "$RUN/api.log"

# ---------------------------------------------------------------------------
# 1. Health check (no auth required)
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/01_health.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]] && grep -q '"status":"ok"' "$LAST_BODY_FILE"; then
    pass "health endpoint returns 200 + status ok without auth" "$LAST_BODY_FILE"
else
    fail "health endpoint 200 without auth" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 2. Login as super-admin
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/02_login.json"
api_login
if [[ "$LAST_CODE" == "200" && -n "${API_TOKEN:-}" && -n "${API_REFRESH:-}" ]]; then
    pass "login with correct password → 200 + access/refresh tokens" "$LAST_BODY_FILE"
else
    fail "login correct password → 200 + tokens" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 2b. /auth/me confirms admin identity
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/02b_me.json"
api_request GET /api/v1/auth/me -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]] && grep -q '"username":"admin"' "$LAST_BODY_FILE"; then
    pass "GET /auth/me with bearer token → 200 + admin identity" "$LAST_BODY_FILE"
else
    fail "GET /auth/me with bearer" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# Helper: create an account and assert the expected HTTP status code.
# ---------------------------------------------------------------------------
mkacct() {  # mkacct <username> <permission> <ack> <expect-code> <evidence>
    LAST_BODY_FILE="$5"
    local body
    body="$(python3 -c "
import json,sys
u,p,ack = sys.argv[1],sys.argv[2],sys.argv[3]=='true'
print(json.dumps({'username':u,'password':'test-pw-'+u,'permission':p,'public_acknowledged':ack}))
" "$1" "$2" "$3")"
    api_request POST /api/v1/accounts \
        -H "Authorization: Bearer $API_TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$body"
    if [[ "$LAST_CODE" == "$4" ]]; then
        pass "create $1 ($2) → $4" "$LAST_BODY_FILE"
    else
        fail "create $1 ($2) → $4" "code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")"
    fi
}

# ---------------------------------------------------------------------------
# 3. Create alice (read_write)
# ---------------------------------------------------------------------------
mkacct alice read_write false 201 "$RUN/03_create_alice.json"

# ---------------------------------------------------------------------------
# 4. Create bob (read_only)
# ---------------------------------------------------------------------------
mkacct bob read_only false 201 "$RUN/04_create_bob.json"

# ---------------------------------------------------------------------------
# 5. List accounts — expect exactly 2 non-admin accounts (count=2)
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/05_list_after_create.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]]; then
    pass "list accounts → 200 after creating alice+bob" "$LAST_BODY_FILE"
else
    fail "list accounts → 200" "code=$LAST_CODE"
fi
# Count accounts in the response.  The admin is not an SFTP account, so the
# list should contain exactly 2 entries (alice + bob).
account_count="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['accounts']))" "$LAST_BODY_FILE")"
if [[ "$account_count" == "2" ]]; then
    pass "list accounts → count is exactly 2 (alice + bob, no admin)" "$LAST_BODY_FILE"
else
    fail "list accounts → count=2" "count=$account_count"
fi

# Confirm both usernames appear in the list body.
if grep -q '"username":"alice"' "$LAST_BODY_FILE" \
    && grep -q '"username":"bob"' "$LAST_BODY_FILE"; then
    pass "list response contains both alice and bob" "$LAST_BODY_FILE"
else
    fail "list response contains alice and bob" "missing one or both usernames"
fi

# ---------------------------------------------------------------------------
# 6. Update bob: read_only → read_write
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/06_update_bob.json"
api_request PUT /api/v1/accounts/bob \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"permission":"read_write"}'
if [[ "$LAST_CODE" == "200" ]] && grep -q '"permission":"read_write"' "$LAST_BODY_FILE"; then
    pass "update bob read_only → read_write → 200" "$LAST_BODY_FILE"
else
    fail "update bob permission" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 7. Sync — render users.conf with atmoz grammar
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/07_sync.json"
api_request POST /api/v1/sync -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]]; then
    pass "POST /sync → 200, accounts rendered to disk" "$LAST_BODY_FILE"
else
    fail "POST /sync" "code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")"
fi

if [[ -f "$API_USERS_CONF" ]]; then
    cp "$API_USERS_CONF" "$RUN/07_users.conf"
    pass "users.conf rendered to disk (atomic write)" "$RUN/07_users.conf"
else
    fail "users.conf rendered to disk" "file missing at $API_USERS_CONF"
fi

# ---------------------------------------------------------------------------
# 7b. Verify users.conf atmoz grammar for both accounts.
#
#   atmoz/sftp grammar:
#     read_write  → username:$6$hash:uid:gid:/home/username
#     read_only   → username:$6$hash:uid:gid:/home/username:e
#
#   After the update BOTH alice and bob are read_write, so NEITHER line
#   should carry the ":e" suffix.  Both must have a real $6$ password hash.
# ---------------------------------------------------------------------------
CONF="$API_USERS_CONF"

# alice: read_write — hash present, no :e suffix
if grep -qE '^alice:\$6\$[^:]+:[0-9]+:[0-9]+:/alice$' "$CONF"; then
    pass "read_write alice renders with \$6\$ hash and NO option suffix" "$RUN/07_users.conf"
else
    fail "read_write alice render grammar" "line: $(grep '^alice:' "$CONF" || echo missing)"
fi

# bob: read_write (just updated) — hash present, no :e suffix
if grep -qE '^bob:\$6\$[^:]+:[0-9]+:[0-9]+:/bob$' "$CONF"; then
    pass "read_write bob (after update) renders with \$6\$ hash and NO option suffix" "$RUN/07_users.conf"
else
    fail "read_write bob render grammar" "line: $(grep '^bob:' "$CONF" || echo missing)"
fi

# users.conf permissions must be 0600 (contains password hashes, §11.4.10).
if [[ "$(stat -c%a "$CONF" 2>/dev/null)" == "600" ]]; then
    pass "users.conf permissions are 0600 (holds password hashes)" "$RUN/07_users.conf"
else
    fail "users.conf permissions 0600" "got $(stat -c%a "$CONF" 2>/dev/null || echo missing)"
fi

# Atomicity: no stale .tmp file left behind.
if compgen -G "$API_USERS_CONF.tmp" > /dev/null 2>&1; then
    fail "sync leaves no temp file behind (atomic rename)" ".tmp present"
else
    pass "sync writes atomically (temp-then-rename, no .tmp left)" "$RUN/07_sync.json"
fi

# ---------------------------------------------------------------------------
# 8. List accounts again — confirm bob's permission is now read_write and
#    both accounts still present.
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/08_list_after_update.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]]; then
    pass "list accounts after update → 200" "$LAST_BODY_FILE"
else
    fail "list accounts after update → 200" "code=$LAST_CODE"
fi

# bob should show read_write in the list response.
if grep -q '"username":"bob"' "$LAST_BODY_FILE" \
    && grep -q '"permission":"read_write"' "$LAST_BODY_FILE"; then
    pass "list confirms bob is now read_write" "$LAST_BODY_FILE"
else
    fail "list confirms bob read_write" "bob entry missing or permission not read_write"
fi

# Count should still be 2.
account_count2="$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))['accounts']))" "$LAST_BODY_FILE")"
if [[ "$account_count2" == "2" ]]; then
    pass "list accounts after update → count still 2" "$LAST_BODY_FILE"
else
    fail "list accounts after update → count=2" "count=$account_count2"
fi

# ---------------------------------------------------------------------------
# 9. Delete alice → 204
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/09_delete_alice.json"
api_request DELETE /api/v1/accounts/alice -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "204" ]]; then
    pass "delete alice → 204" "$LAST_BODY_FILE"
else
    fail "delete alice → 204" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 10. GET alice → 404 (confirm deletion)
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/10_get_alice_after_delete.json"
api_request GET /api/v1/accounts/alice -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "404" ]]; then
    pass "GET deleted account alice → 404" "$LAST_BODY_FILE"
else
    fail "GET deleted account alice → 404" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 11. Final health check — API still healthy after all operations
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/11_health_final.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]] && grep -q '"status":"ok"' "$LAST_BODY_FILE"; then
    pass "final health check → 200 + status ok" "$LAST_BODY_FILE"
else
    fail "final health check → 200 + status ok" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 12. Anti-bluff sweep: no secret leaked into evidence artifacts (§11.4.10)
# ---------------------------------------------------------------------------
leak=0
if grep -rqF "$JWT_SECRET" "$RUN" --exclude='*.env' 2>/dev/null; then leak=1; fi
if grep -rqF "$SUPERADMIN_PASSWORD" "$RUN" 2>/dev/null; then leak=1; fi
if [[ "$leak" -eq 0 ]]; then
    pass "no generated secret value appears in any evidence artifact (§11.4.10)" "$RUN/api.log"
else
    fail "secret leak scan over evidence dir" "secret value found in $RUN"
fi

verdict
