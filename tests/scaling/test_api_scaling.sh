#!/usr/bin/env bash
# ============================================================================
# test_api_scaling.sh — scaling test of the SFTP management API (STREAM-9)
# ----------------------------------------------------------------------------
# Purpose:
#   Scale-test the account CRUD pipeline against a REAL running sftp-api
#   binary: create 100 accounts, verify they all exist via list+sync, delete
#   all 100, assert the account list is empty again.  Timing data and every
#   intermediate API response are captured as evidence (§11.4.5/§11.4.69).
#
#   Phases:
#     1. Start harness with LOGIN_RATE_LIMIT=1000000 (lifted for bulk ops)
#     2. Admin login
#     3. Create 100 accounts (scale001–scale100, read_write) in a loop
#        → count 201s vs failures, assert all 100 created
#     4. List accounts → assert count ≥ 100
#     5. POST /sync → assert rendered_accounts ≥ 100 + copy users.conf
#     6. Delete all 100 accounts in a loop → count 204s vs failures
#     7. List accounts → assert count == 0 (admin is not an SFTP account)
#     8. Final health check
#     9. Timing summary
#
# Usage:
#   tests/scaling/test_api_scaling.sh
#   SCALE_COUNT=200 tests/scaling/test_api_scaling.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox).  SCALE_COUNT env var
#   overrides the default (100, minimum 2).
#
# Outputs:
#   qa/results/stream9/scaling_<timestamp>/ — per-account create/delete
#   evidence, list_before.json, list_after.json, sync_body.json, users.conf
#   copy, timing.txt, final health, verdict.  Exit 0 ONLY on all-green.
#
# Side-effects:
#   One mktemp sandbox (DB, users.conf, secrets, vault) + evidence dir;
#   sandbox removed on EXIT, API stopped gracefully (§11.4.14).
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · api/internal/api/handlers_accounts.go ·
#   api/internal/api/handlers_sync.go · constitution §11.4.5, §11.4.10,
#   §11.4.14, §11.4.69, §11.4.85 (stress/scaling resilience).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

NUM="${SCALE_COUNT:-100}"
# Safety floor — a scaling test with < 2 accounts is meaningless.
[[ "$NUM" -lt 2 ]] && NUM=2

RUN="$ROOT/qa/results/stream9/scaling_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API scaling test ($NUM accounts: create → verify → sync → delete) ==="
echo "evidence: $RUN"

cleanup() { api_harness_stop; [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Start the harness with a high rate-limit so bulk account operations are
#    not throttled (§11.4.6: the limit is lifted for surface-capacity
#    measurement, its enforcement is verified separately in security tests).
# ---------------------------------------------------------------------------
api_harness_start "$RUN" "LOGIN_RATE_LIMIT=1000000" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started on port $API_PORT (LOGIN_RATE_LIMIT lifted for bulk scaling)" "$RUN/api.log"

# ---------------------------------------------------------------------------
# 2. Admin login — uses api_login (password read from 0600 secrets, never
#    echoed or on a command line, §11.4.10).
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/login.json"
api_login
if [[ "$LAST_CODE" == "200" && -n "${API_TOKEN:-}" ]]; then
    pass "admin login → 200 + access token" "$LAST_BODY_FILE"
else
    fail "admin login" "code=$LAST_CODE"
    verdict
fi

# ---------------------------------------------------------------------------
# 3. CREATE phase: NUM accounts in a loop, each with permission read_write.
#    Usernames are scale001…scale<NUM> (all lowercase + digits, per the
#    project's username rules).  Timing is captured via $SECONDS.
# ---------------------------------------------------------------------------
CREATE_OK=0
CREATE_FAIL=0
echo "=== Creating $NUM accounts (scale001 … scale$(printf '%03d' "$NUM")) ==="
T_START="$SECONDS"

for i in $(seq -w 1 "$NUM"); do
    username="scale${i}"
    password="test-pw-${username}"
    evidence="$RUN/create_${username}.json"
    LAST_BODY_FILE="$evidence"

    # Build JSON body without echoing the password (§11.4.10).
    body="$(python3 -c "
import json, sys
u, pw = sys.argv[1], sys.argv[2]
print(json.dumps({'username': u, 'password': pw, 'permission': 'read_write'}))
" "$username" "$password")"

    api_request POST /api/v1/accounts \
        -H "Authorization: Bearer $API_TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$body"

    if [[ "$LAST_CODE" == "201" ]]; then
        CREATE_OK=$((CREATE_OK + 1))
    else
        CREATE_FAIL=$((CREATE_FAIL + 1))
        echo "CREATE FAIL $username: code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")" >> "$RUN/create_failures.log"
    fi
done

ELAPSED_CREATE=$(( SECONDS - T_START ))

if [[ "$CREATE_OK" -eq "$NUM" && "$CREATE_FAIL" -eq 0 ]]; then
    pass "created $CREATE_OK/$NUM accounts (all 201), elapsed=${ELAPSED_CREATE}s" "$RUN/create_failures.log"
else
    fail "account creation" "ok=$CREATE_OK fail=$CREATE_FAIL expected=$NUM (see $RUN/create_failures.log)"
fi

# ---------------------------------------------------------------------------
# 4. LIST accounts → assert the count covers all created accounts.
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/list_before.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"

list_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["count"])' "$LAST_BODY_FILE")"
if [[ "$LAST_CODE" == "200" && "$list_count" -ge "$NUM" ]]; then
    pass "list accounts after creation → count=$list_count (≥ $NUM)" "$LAST_BODY_FILE"
else
    fail "list accounts after creation" "code=$LAST_CODE count=$list_count expected≥$NUM"
fi

# ---------------------------------------------------------------------------
# 5. SYNC → render users.conf, verify rendered_accounts ≥ NUM, copy the file
#    into evidence before the sandbox is torn down.
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/sync_body.json"
api_request POST /api/v1/sync -H "Authorization: Bearer $API_TOKEN"

sync_count="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["rendered_accounts"])' "$LAST_BODY_FILE")"
if [[ "$LAST_CODE" == "200" && "$sync_count" -ge "$NUM" ]]; then
    pass "POST /sync → rendered_accounts=$sync_count (≥ $NUM)" "$LAST_BODY_FILE"
else
    fail "POST /sync" "code=$LAST_CODE rendered=$sync_count expected≥$NUM"
fi

# Copy users.conf for evidence & verify line count on disk.
if [[ -f "$API_USERS_CONF" ]]; then
    cp "$API_USERS_CONF" "$RUN/users.conf"
    conf_lines="$(wc -l < "$API_USERS_CONF")"
    if [[ "$conf_lines" -ge "$NUM" ]]; then
        pass "users.conf on disk has $conf_lines lines (≥ $NUM)" "$RUN/users.conf"
    else
        fail "users.conf line count" "got $conf_lines, expected ≥ $NUM"
    fi
else
    fail "users.conf exists on disk" "file missing at $API_USERS_CONF"
fi

# ---------------------------------------------------------------------------
# 6. DELETE phase: remove all NUM accounts, count 204s vs failures.
# ---------------------------------------------------------------------------
DELETE_OK=0
DELETE_FAIL=0
echo "=== Deleting $NUM accounts ==="
T_START_DEL="$SECONDS"

for i in $(seq -w 1 "$NUM"); do
    username="scale${i}"
    evidence="$RUN/delete_${username}.json"
    LAST_BODY_FILE="$evidence"

    api_request DELETE "/api/v1/accounts/${username}" \
        -H "Authorization: Bearer $API_TOKEN"

    if [[ "$LAST_CODE" == "204" ]]; then
        DELETE_OK=$((DELETE_OK + 1))
    else
        DELETE_FAIL=$((DELETE_FAIL + 1))
        echo "DELETE FAIL $username: code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")" >> "$RUN/delete_failures.log"
    fi
done

ELAPSED_DELETE=$(( SECONDS - T_START_DEL ))

if [[ "$DELETE_OK" -eq "$NUM" && "$DELETE_FAIL" -eq 0 ]]; then
    pass "deleted $DELETE_OK/$NUM accounts (all 204), elapsed=${ELAPSED_DELETE}s" "$RUN/delete_failures.log"
else
    fail "account deletion" "ok=$DELETE_OK fail=$DELETE_FAIL expected=$NUM (see $RUN/delete_failures.log)"
fi

# ---------------------------------------------------------------------------
# 7. LIST after deletion → assert count == 0.
#    The admin user is NOT an SFTP account (it is validated via the
#    SUPERADMIN_PASSWORD env var in the auth handler, never stored in the
#    accounts table), so after deleting every scaleNNN account the list MUST
#    return zero SFTP accounts.
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/list_after.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"

list_count_after="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["count"])' "$LAST_BODY_FILE")"
if [[ "$LAST_CODE" == "200" && "$list_count_after" -eq 0 ]]; then
    pass "list accounts after deletion → count=0 (admin is not an SFTP account)" "$LAST_BODY_FILE"
else
    fail "list accounts after deletion → count must be 0" "code=$LAST_CODE count=$list_count_after"
fi

# ---------------------------------------------------------------------------
# 8. Final health check — the API must still be responsive.
# ---------------------------------------------------------------------------
LAST_BODY_FILE="$RUN/final_health.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]]; then
    pass "API still healthy after scaling test (no wedge, no leak)" "$LAST_BODY_FILE"
else
    fail "final health check" "code=$LAST_CODE"
fi

# ---------------------------------------------------------------------------
# 9. Timing summary — total wall-clock for create+delete phases.
# ---------------------------------------------------------------------------
TOTAL_ELAPSED=$(( ELAPSED_CREATE + ELAPSED_DELETE ))
{
    echo "accounts_created=$NUM"
    echo "accounts_deleted=$NUM"
    echo "create_ok=$CREATE_OK"
    echo "create_fail=$CREATE_FAIL"
    echo "create_elapsed_seconds=$ELAPSED_CREATE"
    echo "delete_ok=$DELETE_OK"
    echo "delete_fail=$DELETE_FAIL"
    echo "delete_elapsed_seconds=$ELAPSED_DELETE"
    echo "total_elapsed_seconds=$TOTAL_ELAPSED"
    echo "create_per_account_ms=$(python3 -c "print(round(${ELAPSED_CREATE}*1000/${NUM},1))")"
    echo "delete_per_account_ms=$(python3 -c "print(round(${ELAPSED_DELETE}*1000/${NUM},1))")"
    echo "timestamp_utc=$(date -u +%FT%TZ)"
} > "$RUN/timing.txt"

pass "timing data saved (create=${ELAPSED_CREATE}s, delete=${ELAPSED_DELETE}s, total=${TOTAL_ELAPSED}s)" "$RUN/timing.txt"

echo "--- timing summary ---"; cat "$RUN/timing.txt"; echo

verdict
