#!/usr/bin/env bash
# ============================================================================
# test_api_benchmark.sh — API performance benchmark (STREAM-9, §11.4.85
# stress + performance mandate)
# ----------------------------------------------------------------------------
# Purpose:
#   Benchmarks key API operations against a REAL running sftp-api binary:
#     A. HEALTH  — GET  /api/v1/health
#     B. LOGIN   — POST /api/v1/auth/login
#     C. LIST    — GET  /api/v1/accounts
#     D. CREATE  — POST /api/v1/accounts
#     E. DELETE  — DELETE /api/v1/accounts/<user>
#   Each operation: 10 warmup iterations + 50 measured iterations,
#   ops/sec computed as 50 / total_elapsed_seconds (sub-ms precision
#   via python3 time.perf_counter).
#
# Usage:
#   tests/benchmarking/test_api_benchmark.sh
#   SFTP_API_BINARY=/path/to/sftp-api tests/benchmarking/test_api_benchmark.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox when SFTP_API_BINARY is
#   unset). Secrets generated per-run via openssl (never printed, §11.4.10).
#
# Outputs:
#   qa/results/stream9/bench_<timestamp>/ — evidence files + benchmark.json:
#     {
#       "health_ops_per_sec": ...,
#       "login_ops_per_sec":  ...,
#       "list_ops_per_sec":   ...,
#       "create_ops_per_sec": ...,
#       "delete_ops_per_sec": ...
#     }
#   Minimum throughput: health ≥ 50, login ≥ 10, list ≥ 30,
#   create ≥ 5, delete ≥ 5 ops/sec.
#   Exit 0 ONLY when every check PASSes.
#
# Side-effects:
#   One mktemp sandbox (DB, users.conf, secrets) + evidence dir; API
#   stopped and sandbox removed on EXIT (§11.4.14). Remaining bench_*
#   accounts cleaned up during EXIT trap.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24 (or SFTP_API_BINARY), curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · api/internal/config/config.go ·
#   constitution §11.4.5, §11.4.10, §11.4.14, §11.4.85, §11.4.69.
# ============================================================================
# shellcheck shell=bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

RUN="$ROOT/qa/results/stream9/bench_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API benchmark ==="
echo "evidence: $RUN"

# ---------------------------------------------------------------------------
# Cleanup trap: stop the API, delete any remaining bench_* accounts, remove
# the sandbox. §11.4.14 — every exit path cleans up.
# ---------------------------------------------------------------------------
cleanup() {
    # Clean up any remaining bench_* accounts while the API is still alive.
    if [[ -n "${API_PID:-}" ]] && kill -0 "$API_PID" 2>/dev/null; then
        echo "--- cleanup: removing remaining bench_* accounts ---" >&2
        if api_login 2>/dev/null && [[ "${LAST_CODE:-}" == "200" && -n "${API_TOKEN:-}" ]]; then
            local remaining u
            remaining="$(curl -s "$API_BASE/api/v1/accounts" \
                -H "Authorization: Bearer $API_TOKEN" 2>/dev/null \
                | python3 -c '
import json, sys
data = json.load(sys.stdin)
for a in data.get("accounts", []):
    if a["username"].startswith("bench_"):
        print(a["username"])
' 2>/dev/null || echo "")"
            while IFS= read -r u; do
                [[ -z "$u" ]] && continue
                curl -s -o /dev/null -X DELETE "$API_BASE/api/v1/accounts/$u" \
                    -H "Authorization: Bearer $API_TOKEN" 2>/dev/null || true
            done <<< "$remaining"
        fi
    fi
    api_harness_stop
    [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Start the API with a high login rate limit so the benchmark is never
# throttled by the rate limiter.
# ---------------------------------------------------------------------------
api_harness_start "$RUN" "LOGIN_RATE_LIMIT=1000000" \
    || { echo "FATAL: harness start failed"; exit 1; }
pass "API started on port $API_PORT with LOGIN_RATE_LIMIT=1000000" "$RUN/api.log"

# ---------------------------------------------------------------------------
# Initial login — obtain a bearer token for authenticated benchmark phases.
# ---------------------------------------------------------------------------
api_login
if [[ "$LAST_CODE" != "200" ]]; then
    fail "benchmark prerequisite: initial login" \
        "code=$LAST_CODE body=$(cat "$LAST_BODY_FILE")"
    verdict
fi
pass "initial login obtained bearer token" "$LAST_BODY_FILE"
TOKEN="$API_TOKEN"

# ===========================================================================
# Helper — run_timed_loop: executes $func $i for i=1..$count, records
# total wall-clock elapsed via python3 time.perf_counter. Stores ops/sec
# into the variable named by $out_var.
# ===========================================================================
run_timed_loop() {
    local name="$1" count="$2" func="$3" out_var="$4"
    local t0 t1 elapsed ops

    t0="$(python3 -c 'import time; print(time.perf_counter())')"
    local i
    for i in $(seq 1 "$count"); do
        "$func" "$i"
    done
    t1="$(python3 -c 'import time; print(time.perf_counter())')"

    elapsed="$(python3 -c "
t0 = float('${t0}')
t1 = float('${t1}')
print(round(t1 - t0, 6))
")"
    ops="$(python3 -c "
elapsed = float('${elapsed}')
ops = ${count}.0 / elapsed if elapsed > 0.0 else float('inf')
print(round(ops, 2))
")"
    echo "    ${name}: ${ops} ops/sec (${count} iterations in ${elapsed}s)"

    # Write the value back into the caller's variable.
    printf -v "$out_var" '%s' "$ops"
}

# ===========================================================================
# PHASE A — HEALTH benchmark (GET /api/v1/health, no auth)
# ===========================================================================
echo ""
echo "=== A. HEALTH benchmark (GET /api/v1/health) ==="

health_req() {  # health_req <iteration-number>
    local n="$1"
    LAST_BODY_FILE="$RUN/health_$(printf '%02d' "$n").json"
    api_request GET /api/v1/health
}

echo "    warmup: 10 iterations..."
for i in $(seq 1 10); do
    LAST_BODY_FILE="$RUN/health_warm_$(printf '%02d' "$i").json"
    api_request GET /api/v1/health
done

echo "    measured: 50 iterations..."
run_timed_loop "health" 50 health_req HEALTH_OPS
# Spot-check: verify a health request still returns 200 after the benchmark.
LAST_BODY_FILE="$RUN/health_01.json"; api_request GET /api/v1/health
[[ "$LAST_CODE" == "200" ]] && pass "health spot-check returns 200" "$LAST_BODY_FILE" \
    || fail "health spot-check" "code=$LAST_CODE"

# ===========================================================================
# PHASE B — LOGIN benchmark (POST /api/v1/auth/login)
# ===========================================================================
echo ""
echo "=== B. LOGIN benchmark (POST /api/v1/auth/login) ==="

login_req() {  # login_req <iteration-number>
    local n="$1"
    LAST_BODY_FILE="$RUN/login_$(printf '%02d' "$n").json"
    api_login
}

echo "    warmup: 10 iterations..."
for i in $(seq 1 10); do
    LAST_BODY_FILE="$RUN/login_warm_$(printf '%02d' "$i").json"
    api_login
done

echo "    measured: 50 iterations..."
run_timed_loop "login" 50 login_req LOGIN_OPS
# Spot-check the last login succeeded.
echo "    login spot-check: code=${LAST_CODE:-unset}"
if [[ "${LAST_CODE:-}" == "200" ]]; then
    pass "login spot-check returns 200" "$LAST_BODY_FILE"
else
    fail "login spot-check" "code=${LAST_CODE:-unset}"
fi

# ---------------------------------------------------------------------------
# Re-login after the login benchmark: the login phase performed 60 logins;
# get a guaranteed-fresh token for authenticated phases.
# ---------------------------------------------------------------------------
api_login
if [[ "$LAST_CODE" == "200" ]]; then
    TOKEN="$API_TOKEN"
    pass "re-login after login benchmark" "$LAST_BODY_FILE"
else
    fail "re-login after login benchmark" "code=$LAST_CODE"
fi

# ===========================================================================
# PHASE C — LIST benchmark (GET /api/v1/accounts)
# ===========================================================================
echo ""
echo "=== C. LIST benchmark (GET /api/v1/accounts) ==="

list_req() {  # list_req <iteration-number>
    local n="$1"
    LAST_BODY_FILE="$RUN/list_$(printf '%02d' "$n").json"
    api_request GET /api/v1/accounts -H "Authorization: Bearer $TOKEN"
}

echo "    warmup: 10 iterations..."
for i in $(seq 1 10); do
    LAST_BODY_FILE="$RUN/list_warm_$(printf '%02d' "$i").json"
    api_request GET /api/v1/accounts -H "Authorization: Bearer $TOKEN"
done

echo "    measured: 50 iterations..."
run_timed_loop "list" 50 list_req LIST_OPS
# Spot-check.
LAST_BODY_FILE="$RUN/list_50.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $TOKEN"
if [[ "$LAST_CODE" == "200" ]]; then
    pass "list spot-check returns 200" "$LAST_BODY_FILE"
else
    fail "list spot-check" "code=$LAST_CODE"
fi

# ===========================================================================
# PHASE D — CREATE benchmark (POST /api/v1/accounts)
# ===========================================================================
echo ""
echo "=== D. CREATE benchmark (POST /api/v1/accounts) ==="

echo "    warmup: 10 iterations (creating bench_warm_001..010)..."
for i in $(seq 1 10); do
    bname="$(printf 'bench_warm_%03d' "$i")"
    bbody="$(python3 -c "
import json, sys
print(json.dumps({
    'username': sys.argv[1],
    'password': 'benchpass',
    'permission': 'read_only',
}))
" "$bname")"
    LAST_BODY_FILE="$RUN/create_warm_$(printf '%02d' "$i").json"
    api_request POST /api/v1/accounts \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$bbody"
    if [[ "$LAST_CODE" != "201" ]]; then
        fail "create warmup $i (${bname})" "expected 201, got $LAST_CODE"
    fi
done

echo "    measured: 50 iterations (creating bench_001..050)..."
CREATE_T0="$(python3 -c 'import time; print(time.perf_counter())')"
for i in $(seq 1 50); do
    bname="$(printf 'bench_%03d' "$i")"
    bbody="$(python3 -c "
import json, sys
print(json.dumps({
    'username': sys.argv[1],
    'password': 'benchpass',
    'permission': 'read_only',
}))
" "$bname")"
    LAST_BODY_FILE="$RUN/create_$(printf '%02d' "$i").json"
    api_request POST /api/v1/accounts \
        -H "Authorization: Bearer $TOKEN" \
        -H 'Content-Type: application/json' \
        --data "$bbody"
    if [[ "$LAST_CODE" != "201" ]]; then
        fail "create iteration $i (${bname})" \
            "expected 201, got $LAST_CODE body=$(cat "$LAST_BODY_FILE")"
    fi
done
CREATE_T1="$(python3 -c 'import time; print(time.perf_counter())')"
CREATE_OPS="$(python3 -c "
t0 = float('${CREATE_T0}')
t1 = float('${CREATE_T1}')
elapsed = t1 - t0
ops = 50.0 / elapsed if elapsed > 0.0 else float('inf')
print(round(ops, 2))
")"
echo "    create: ${CREATE_OPS} ops/sec (50 iterations)"
pass "create benchmark ${CREATE_OPS} ops/sec" "$RUN/create_50.json"

# ===========================================================================
# PHASE E — DELETE benchmark (DELETE /api/v1/accounts/<user>)
# ===========================================================================
echo ""
echo "=== E. DELETE benchmark (DELETE /api/v1/accounts/bench_NNN) ==="

echo "    warmup: 10 iterations (deleting bench_warm_001..010)..."
for i in $(seq 1 10); do
    bname="$(printf 'bench_warm_%03d' "$i")"
    LAST_BODY_FILE="$RUN/delete_warm_$(printf '%02d' "$i").json"
    api_request DELETE "/api/v1/accounts/${bname}" \
        -H "Authorization: Bearer $TOKEN"
    if [[ "$LAST_CODE" != "204" ]]; then
        fail "delete warmup $i (${bname})" \
            "expected 204, got $LAST_CODE"
    fi
done

echo "    measured: 50 iterations (deleting bench_001..050)..."
DELETE_T0="$(python3 -c 'import time; print(time.perf_counter())')"
for i in $(seq 1 50); do
    bname="$(printf 'bench_%03d' "$i")"
    LAST_BODY_FILE="$RUN/delete_$(printf '%02d' "$i").json"
    api_request DELETE "/api/v1/accounts/${bname}" \
        -H "Authorization: Bearer $TOKEN"
    if [[ "$LAST_CODE" != "204" ]]; then
        fail "delete iteration $i (${bname})" \
            "expected 204, got $LAST_CODE"
    fi
done
DELETE_T1="$(python3 -c 'import time; print(time.perf_counter())')"
DELETE_OPS="$(python3 -c "
t0 = float('${DELETE_T0}')
t1 = float('${DELETE_T1}')
elapsed = t1 - t0
ops = 50.0 / elapsed if elapsed > 0.0 else float('inf')
print(round(ops, 2))
")"
echo "    delete: ${DELETE_OPS} ops/sec (50 iterations)"
pass "delete benchmark ${DELETE_OPS} ops/sec" "$RUN/delete_50.json"

# ===========================================================================
# Write benchmark.json — single results document for the run.
# ===========================================================================
BENCH_JSON="$RUN/benchmark.json"
python3 - "$BENCH_JSON" "$HEALTH_OPS" "$LOGIN_OPS" "$LIST_OPS" \
    "$CREATE_OPS" "$DELETE_OPS" <<'PYEOF'
import json, sys

dst = sys.argv[1]
data = {
    "health_ops_per_sec": float(sys.argv[2]),
    "login_ops_per_sec":  float(sys.argv[3]),
    "list_ops_per_sec":   float(sys.argv[4]),
    "create_ops_per_sec": float(sys.argv[5]),
    "delete_ops_per_sec": float(sys.argv[6]),
}
with open(dst, "w") as f:
    json.dump(data, f, indent=2)
print("benchmark.json written to " + dst)
PYEOF
pass "benchmark.json saved" "$BENCH_JSON"

# ===========================================================================
# Assert minimum throughput thresholds (requirement 6).
# ===========================================================================
echo ""
echo "=== Throughput assertions ==="

assert_throughput() {
    local label="$1" actual="$2" minimum="$3"
    local ok
    ok="$(python3 -c "
a = float('${actual}')
m = float('${minimum}')
print('1' if a >= m else '0')
")"
    if [[ "$ok" == "1" ]]; then
        pass "${label} throughput ${actual} >= ${minimum} ops/sec" "$BENCH_JSON"
    else
        fail "${label} throughput ${actual} < ${minimum} ops/sec" \
            "${actual} ops/sec is below the ${minimum} ops/sec minimum"
    fi
}

assert_throughput "health" "$HEALTH_OPS" 50
assert_throughput "login"  "$LOGIN_OPS"  10
assert_throughput "list"   "$LIST_OPS"   30
assert_throughput "create" "$CREATE_OPS" 5
assert_throughput "delete" "$DELETE_OPS" 5

# ===========================================================================
# Final verdict — exit 0 iff FAIL == 0.
# ===========================================================================
echo ""
echo "=== SFTP API benchmark complete ==="
verdict
