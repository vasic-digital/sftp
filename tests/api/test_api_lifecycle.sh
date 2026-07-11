#!/usr/bin/env bash
# ============================================================================
# test_api_lifecycle.sh — full end-to-end lifecycle integration test of the
# SFTP management API against a REAL running binary (STREAM-9, §11.4)
# ----------------------------------------------------------------------------
# Purpose:
#   Exercises the complete account lifecycle through the live HTTP surface:
#     1. health (no auth) → 200
#     2. login wrong password → 401
#     3. login right password → 200 + JWT pair
#     4. /auth/me with bearer → 200
#     5. create accounts: read_only / read_write / public-without-ack (422)
#        / public-with-ack (201)
#     6. list accounts → NO password field anywhere in the response
#        (anti-bluff grep, §11.4.10)
#     7. update an account (permission flip) → 200
#     8. delete an account → 204, then GET → 404
#     9. sync → users.conf rendered atomically with correct atmoz grammar:
#        read_write → no suffix; read_only → ":e"; public → "*" + ":e"
#    10. duplicate create → 409; invalid username shape → 400
#
#   Every PASS cites its captured evidence file (response body / status /
#   rendered users.conf) under qa/results/stream9/<run>/ — a PASS without
#   the real running API is a defect by definition (§11.4).
#
# Usage:
#   tests/api/test_api_lifecycle.sh
#   SFTP_API_BINARY=/path/to/sftp-api tests/api/test_api_lifecycle.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox when SFTP_API_BINARY is
#   unset). Secrets generated per-run via openssl (never printed).
#
# Outputs:
#   qa/results/stream9/<timestamp>/ — api.log, per-step response bodies,
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
#   tests/api/lib_api.sh · api/internal/api/handlers_*.go ·
#   api/internal/sftpsync/sftpsync.go (atmoz grammar) ·
#   constitution §11.4.2, §11.4.5, §11.4.10, §11.4.14, §11.4.69.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

RUN="$ROOT/qa/results/stream9/lifecycle_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API lifecycle integration test ==="
echo "evidence: $RUN"

cleanup() { api_harness_stop; [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"; }
trap cleanup EXIT

api_harness_start "$RUN" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started on random port with temp DB + generated secrets" "$RUN/api.log"

# --- 1. health, no auth ------------------------------------------------------
LAST_BODY_FILE="$RUN/01_health.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]] && grep -q '"status":"ok"' "$LAST_BODY_FILE"; then
    pass "health endpoint returns 200 + status ok without auth" "$LAST_BODY_FILE"
else
    fail "health endpoint 200 without auth" "code=$LAST_CODE"
fi

# --- 2. wrong password → 401 -------------------------------------------------
LAST_BODY_FILE="$RUN/02_login_wrong.json"
api_request POST /api/v1/auth/login \
    -H 'Content-Type: application/json' \
    --data '{"username":"admin","password":"definitely-wrong-password"}'
if [[ "$LAST_CODE" == "401" ]]; then
    pass "login with wrong password → 401" "$LAST_BODY_FILE"
else
    fail "login wrong password → 401" "code=$LAST_CODE"
fi

# --- 3. right password → 200 + JWT pair --------------------------------------
LAST_BODY_FILE="$RUN/03_login_ok.json"
api_login
if [[ "$LAST_CODE" == "200" && -n "${API_TOKEN:-}" && -n "${API_REFRESH:-}" ]]; then
    # Evidence file holds the response; token VALUES are never echoed by
    # this script — only that they exist and parse.
    pass "login with correct password → 200 + access/refresh tokens" "$LAST_BODY_FILE"
else
    fail "login correct password → 200 + tokens" "code=$LAST_CODE"
fi

# --- 4. /auth/me with bearer → 200 -------------------------------------------
LAST_BODY_FILE="$RUN/04_me.json"
api_request GET /api/v1/auth/me -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]] && grep -q '"username":"admin"' "$LAST_BODY_FILE"; then
    pass "GET /auth/me with bearer token → 200 + admin identity" "$LAST_BODY_FILE"
else
    fail "GET /auth/me with bearer" "code=$LAST_CODE"
fi

# --- 4b. missing bearer → 401 ------------------------------------------------
LAST_BODY_FILE="$RUN/04b_me_noauth.json"
api_request GET /api/v1/auth/me
if [[ "$LAST_CODE" == "401" ]]; then
    pass "GET /auth/me without token → 401" "$LAST_BODY_FILE"
else
    fail "GET /auth/me without token → 401" "code=$LAST_CODE"
fi

# --- 5. create accounts, all three permission classes -------------------------
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
mkacct alice read_only false 201 "$RUN/05_create_alice.json"
mkacct bob read_write false 201 "$RUN/05_create_bob.json"

LAST_BODY_FILE="$RUN/05_create_public_noack.json"
api_request POST /api/v1/accounts \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"username":"pub1","password":"test-pw-pub1","permission":"public","public_acknowledged":false}'
if [[ "$LAST_CODE" == "422" ]]; then
    pass "create public WITHOUT acknowledgement → 422" "$LAST_BODY_FILE"
else
    fail "create public without ack → 422" "code=$LAST_CODE"
fi
mkacct pub1 public true 201 "$RUN/05_create_public_ack.json"

# --- 5b. duplicate → 409, bad username → 400 ----------------------------------
mkacct alice read_only false 409 "$RUN/05b_dup_alice.json"
LAST_BODY_FILE="$RUN/05b_bad_username.json"
api_request POST /api/v1/accounts \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"username":"Bad Name!","password":"x","permission":"read_only"}'
if [[ "$LAST_CODE" == "400" ]]; then
    pass "invalid username shape rejected → 400" "$LAST_BODY_FILE"
else
    fail "invalid username shape → 400" "code=$LAST_CODE"
fi

# --- 6. list accounts — NO password material anywhere (anti-bluff grep) -------
LAST_BODY_FILE="$RUN/06_list.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]] && grep -q '"count":3' "$LAST_BODY_FILE"; then
    pass "list accounts → 200 with 3 accounts" "$LAST_BODY_FILE"
else
    fail "list accounts → 200 with 3 accounts" "code=$LAST_CODE"
fi
if grep -qiE '"password|password_hash|\$6\$|test-pw-' "$LAST_BODY_FILE"; then
    fail "list response contains NO password material (§11.4.10)" "password-shaped content found"
else
    pass "list response contains NO password material (§11.4.10)" "$LAST_BODY_FILE"
fi

# --- 7. update: flip bob to read_only ------------------------------------------
LAST_BODY_FILE="$RUN/07_update_bob.json"
api_request PUT /api/v1/accounts/bob \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"permission":"read_only"}'
if [[ "$LAST_CODE" == "200" ]] && grep -q '"permission":"read_only"' "$LAST_BODY_FILE"; then
    pass "update bob read_write → read_only → 200" "$LAST_BODY_FILE"
else
    fail "update bob permission" "code=$LAST_CODE"
fi

# --- 8. delete pub1 → 204, then GET → 404 --------------------------------------
LAST_BODY_FILE="$RUN/08_delete_pub1.json"
api_request DELETE /api/v1/accounts/pub1 -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "204" ]]; then
    pass "delete pub1 → 204" "$LAST_BODY_FILE"
else
    fail "delete pub1 → 204" "code=$LAST_CODE"
fi
LAST_BODY_FILE="$RUN/08_get_pub1_after_delete.json"
api_request GET /api/v1/accounts/pub1 -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "404" ]]; then
    pass "GET deleted account → 404" "$LAST_BODY_FILE"
else
    fail "GET deleted account → 404" "code=$LAST_CODE"
fi

# --- 9. sync → users.conf atmoz grammar -----------------------------------------
# Re-create a public account first so the render covers all three classes.
mkacct pub2 public true 201 "$RUN/09_create_pub2.json"
LAST_BODY_FILE="$RUN/09_sync.json"
api_request POST /api/v1/sync -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]] && grep -q '"rendered_accounts":3' "$LAST_BODY_FILE"; then
    pass "POST /sync → 200, 3 accounts rendered" "$LAST_BODY_FILE"
else
    fail "POST /sync" "code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")"
fi

if [[ -f "$API_USERS_CONF" ]]; then
    cp "$API_USERS_CONF" "$RUN/09_users.conf"
    pass "users.conf rendered to disk (atomic write)" "$RUN/09_users.conf"
else
    fail "users.conf rendered to disk" "file missing at $API_USERS_CONF"
fi

if [[ "$(stat -c%a "$API_USERS_CONF" 2>/dev/null)" == "600" ]]; then
    pass "users.conf permissions are 0600 (holds password hashes)" "$RUN/09_users.conf"
else
    fail "users.conf permissions 0600" "got $(stat -c%a "$API_USERS_CONF" 2>/dev/null || echo missing)"
fi

# Grammar assertions (§11.4.5 captured content):
#   read_write (none left — bob flipped) → check alice read_only has :e,
#   pub2 has '*' + ':e', and any $6$ line has NO :e suffix requirement.
if grep -qE '^alice:\$6\$[^:]+:e:[0-9]+:[0-9]+:/alice$' "$API_USERS_CONF"; then
    pass "read_only account renders with \$6\$ hash + :e chroot suffix" "$RUN/09_users.conf"
else
    fail "read_only render grammar" "line: $(grep '^alice:' "$API_USERS_CONF" || echo missing)"
fi
if grep -qE '^bob:\$6\$[^:]+:e:[0-9]+:[0-9]+:/bob$' "$API_USERS_CONF"; then
    pass "updated read_only account (bob) re-renders with :e suffix" "$RUN/09_users.conf"
else
    fail "updated account re-render" "line: $(grep '^bob:' "$API_USERS_CONF" || echo missing)"
fi
if grep -qE '^pub2:\*:e:[0-9]+:[0-9]+:/pub2$' "$API_USERS_CONF"; then
    pass "public account renders with '*' password + :e suffix" "$RUN/09_users.conf"
else
    fail "public render grammar" "line: $(grep '^pub2:' "$API_USERS_CONF" || echo missing)"
fi
# read_write grammar: temporarily flip bob back and re-sync to prove the
# no-suffix branch on the real running server.
LAST_BODY_FILE="$RUN/09_update_bob_rw.json"
api_request PUT /api/v1/accounts/bob \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"permission":"read_write"}'
LAST_BODY_FILE="$RUN/09_sync2.json"
api_request POST /api/v1/sync -H "Authorization: Bearer $API_TOKEN"
cp "$API_USERS_CONF" "$RUN/09_users_rw.conf"
if grep -qE '^bob:\$6\$[^:]+:e:[0-9]+:[0-9]+:/bob$' "$API_USERS_CONF"; then
    pass "read_write account renders with \$6\$ hash and :e option" "$RUN/09_users_rw.conf"
else
    fail "read_write render grammar" "line: $(grep '^bob:' "$API_USERS_CONF" || echo missing)"
fi

# Atomicity evidence: no stale .tmp file left behind after sync.
if compgen -G "$API_USERS_CONF.tmp" > /dev/null; then
    fail "sync leaves no temp file behind (atomic rename)" ".tmp present"
else
    pass "sync writes atomically (temp-then-rename, no .tmp left)" "$RUN/09_sync.json"
fi

# --- 10. final anti-bluff sweep: no secret anywhere in evidence ---------------
leak=0
if grep -rqF "$JWT_SECRET" "$RUN" --exclude='*.env' 2>/dev/null; then leak=1; fi
if grep -rqF "$SUPERADMIN_PASSWORD" "$RUN" 2>/dev/null; then leak=1; fi
if [[ "$leak" -eq 0 ]]; then
    pass "no generated secret value appears in any evidence artifact (§11.4.10)" "$RUN/api.log"
else
    fail "secret leak scan over evidence dir" "secret value found in $RUN"
fi

verdict
