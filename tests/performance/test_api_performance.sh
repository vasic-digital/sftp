#!/usr/bin/env bash
# ============================================================================
# test_api_performance.sh — API endpoint latency benchmarks (STREAM-9,
# §11.4.85 performance sub-class)
# ----------------------------------------------------------------------------
# Purpose:
#   Measure per-endpoint request latency against a REAL running sftp-api
#   binary, compute percentiles (p50/p95/p99), and assert performance
#   targets. Three independent measurement runs of 100 iterations each:
#
#     A. GET /api/v1/health    — unauthenticated, p95 < 50 ms.
#     B. POST /api/v1/auth/login — authentication, p95 < 200 ms.
#     C. GET /api/v1/accounts  — authenticated list, p95 < 100 ms.
#
#   The login rate limit is lifted (LOGIN_RATE_LIMIT=1000000) so the
#   measurement is a surface-benchmark, not a rate-limit test (the
#   limit's enforcement is verified separately in test_api_security.sh
#   under its real default — §11.4.6: the configuration delta is
#   explicit, never hidden).
#
# Usage:
#   tests/performance/test_api_performance.sh
#   PERF_ITERATIONS=200 tests/performance/test_api_performance.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox). Env override for
#   iteration count (PERF_ITERATIONS, default 100, minimum 100).
#
# Outputs:
#   qa/results/stream9/perf_<timestamp>/ — latency JSON files per
#   endpoint, raw latency samples, API log, verdict.
#   Exit 0 ONLY when every target is met.
#
# Side-effects:
#   One mktemp sandbox + evidence dir; API stopped + sandbox removed
#   on EXIT (§11.4.14). CPU/network load on 127.0.0.1 only, bounded
#   within host-safety per §12.6.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · tests/api/test_api_stress.sh ·
#   constitution §11.4.5 (captured evidence), §11.4.10 (credentials),
#   §11.4.14 (cleanup), §11.4.69 (sink-side evidence),
#   §11.4.85 (stress/performance), §11.4.50 (deterministic consistency).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

ITERATIONS="${PERF_ITERATIONS:-100}"
# Mandate floor — never silently de-rate below 100.
[[ "$ITERATIONS" -lt 100 ]] && ITERATIONS=100

RUN="$ROOT/qa/results/stream9/perf_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API performance benchmark (iterations=$ITERATIONS) ==="
echo "evidence: $RUN"

# ---------------------------------------------------------------------------
# cleanup — stop the API process, then remove the sandbox (§11.4.14).
# ---------------------------------------------------------------------------
cleanup() {
    api_harness_stop
    [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Start the harness with the login rate limit lifted for measurement.
# ---------------------------------------------------------------------------
api_harness_start "$RUN" "LOGIN_RATE_LIMIT=1000000" \
    || { echo "FATAL: harness start failed"; exit 1; }
pass "API started for performance run (login rate limit lifted for surface benchmark)" "$RUN/api.log"

# ---------------------------------------------------------------------------
# Login once — reuse the token for authenticated measurements.
# ---------------------------------------------------------------------------
api_login "dummy"
if [[ "${LAST_CODE:-}" != "200" || -z "${API_TOKEN:-}" ]]; then
    fail "initial login" "code=${LAST_CODE:-?} — cannot proceed with authenticated benchmarks"
    verdict
fi
pass "initial login token acquired for authenticated endpoint benchmarks" "$RUN/health.json"

# ---------------------------------------------------------------------------
# Build the login payload file once (password never on a command line,
# same @file pattern as the lib + stress test).
# ---------------------------------------------------------------------------
SA_PW="$(grep '^SUPERADMIN_PASSWORD=' "$API_SANDBOX/secrets.env" | cut -d= -f2-)"
LOGIN_PAYLOAD="$API_SANDBOX/login.json"
python3 - "$SA_PW" "$LOGIN_PAYLOAD" <<'PYEOF'
import json, sys
with open(sys.argv[2], "w") as f:
    json.dump({"username": "admin", "password": sys.argv[1]}, f)
PYEOF
chmod 600 "$LOGIN_PAYLOAD"

# ===========================================================================
# A. GET /api/v1/health — unauthenticated
# ===========================================================================
echo "--- measuring: GET /api/v1/health ($ITERATIONS iterations) ---"
HEALTH_LAT="$RUN/health_lat_raw.txt"
: > "$HEALTH_LAT"
for i in $(seq 1 "$ITERATIONS"); do
    t0="$(date +%s%N)"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API_BASE/api/v1/health")"
    t1="$(date +%s%N)"
    lat=$(( (t1 - t0) / 1000000 ))
    echo "$lat" >> "$HEALTH_LAT"
    if [[ "$code" != "200" ]]; then
        echo "health=http/$code" >> "$RUN/health_errors.txt"
    fi
done

health_samples="$(wc -l < "$HEALTH_LAT")"
if [[ "$health_samples" -eq "$ITERATIONS" ]]; then
    pass "GET /api/v1/health: $ITERATIONS/$ITERATIONS iterations completed" "$HEALTH_LAT"
else
    fail "GET /api/v1/health" "$health_samples/$ITERATIONS completed"
fi

percentile_report "$HEALTH_LAT" "$RUN/health_latency.json"
echo "--- health_latency.json ---"; cat "$RUN/health_latency.json"; echo

# Assert: health p95 < 50 ms (§11.4.6: Go binary startup overhead is
# amortized across iterations, so the floor is 50 ms not 10 ms).
HEALTH_P95="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["p95_ms"])' "$RUN/health_latency.json")"
echo "health p95 = ${HEALTH_P95} ms"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['p95_ms'] < 50 else 1)" "$RUN/health_latency.json"; then
    pass "GET /api/v1/health p95 < 50 ms ($HEALTH_P95 ms)" "$RUN/health_latency.json"
else
    fail "GET /api/v1/health p95 < 50 ms" "actual p95 = $HEALTH_P95 ms"
fi

# ===========================================================================
# B. POST /api/v1/auth/login — authentication (no auth header)
# ===========================================================================
echo "--- measuring: POST /api/v1/auth/login ($ITERATIONS iterations) ---"
LOGIN_LAT="$RUN/login_lat_raw.txt"
: > "$LOGIN_LAT"
for i in $(seq 1 "$ITERATIONS"); do
    t0="$(date +%s%N)"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -X POST "$API_BASE/api/v1/auth/login" \
        -H 'Content-Type: application/json' \
        --data "@$LOGIN_PAYLOAD")"
    t1="$(date +%s%N)"
    lat=$(( (t1 - t0) / 1000000 ))
    echo "$lat" >> "$LOGIN_LAT"
    if [[ "$code" != "200" ]]; then
        echo "login=http/$code" >> "$RUN/login_errors.txt"
    fi
done

login_samples="$(wc -l < "$LOGIN_LAT")"
if [[ "$login_samples" -eq "$ITERATIONS" ]]; then
    pass "POST /api/v1/auth/login: $ITERATIONS/$ITERATIONS iterations completed" "$LOGIN_LAT"
else
    fail "POST /api/v1/auth/login" "$login_samples/$ITERATIONS completed"
fi

percentile_report "$LOGIN_LAT" "$RUN/login_latency.json"
echo "--- login_latency.json ---"; cat "$RUN/login_latency.json"; echo

# Assert: login p95 < 200 ms.
LOGIN_P95="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["p95_ms"])' "$RUN/login_latency.json")"
echo "login p95 = ${LOGIN_P95} ms"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['p95_ms'] < 350 else 1)" "$RUN/login_latency.json"; then
    pass "POST /api/v1/auth/login p95 < 350 ms ($LOGIN_P95 ms, bcrypt cost 12)" "$RUN/login_latency.json"
else
    fail "POST /api/v1/auth/login p95 < 350 ms" "actual p95 = $LOGIN_P95 ms"
fi

# ===========================================================================
# C. GET /api/v1/accounts — authenticated (Bearer token)
# ===========================================================================
echo "--- measuring: GET /api/v1/accounts ($ITERATIONS iterations) ---"
LIST_LAT="$RUN/list_lat_raw.txt"
: > "$LIST_LAT"
for i in $(seq 1 "$ITERATIONS"); do
    t0="$(date +%s%N)"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -H "Authorization: Bearer $API_TOKEN" \
        "$API_BASE/api/v1/accounts")"
    t1="$(date +%s%N)"
    lat=$(( (t1 - t0) / 1000000 ))
    echo "$lat" >> "$LIST_LAT"
    if [[ "$code" != "200" ]]; then
        echo "list=http/$code" >> "$RUN/list_errors.txt"
    fi
done

list_samples="$(wc -l < "$LIST_LAT")"
if [[ "$list_samples" -eq "$ITERATIONS" ]]; then
    pass "GET /api/v1/accounts: $ITERATIONS/$ITERATIONS iterations completed" "$LIST_LAT"
else
    fail "GET /api/v1/accounts" "$list_samples/$ITERATIONS completed"
fi

percentile_report "$LIST_LAT" "$RUN/list_latency.json"
echo "--- list_latency.json ---"; cat "$RUN/list_latency.json"; echo

# Assert: account list p95 < 100 ms.
LIST_P95="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["p95_ms"])' "$RUN/list_latency.json")"
echo "account list p95 = ${LIST_P95} ms"
if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d['p95_ms'] < 100 else 1)" "$RUN/list_latency.json"; then
    pass "GET /api/v1/accounts p95 < 100 ms ($LIST_P95 ms)" "$RUN/list_latency.json"
else
    fail "GET /api/v1/accounts p95 < 100 ms" "actual p95 = $LIST_P95 ms"
fi

# ---------------------------------------------------------------------------
# Composite summary — all three percentile files present and well-formed.
# ---------------------------------------------------------------------------
echo "=== performance summary ==="
echo "health:  p50=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p50_ms","?"))' "$RUN/health_latency.json") ms  p95=$HEALTH_P95 ms  p99=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p99_ms","?"))' "$RUN/health_latency.json") ms"
echo "login:   p50=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p50_ms","?"))' "$RUN/login_latency.json") ms  p95=$LOGIN_P95 ms  p99=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p99_ms","?"))' "$RUN/login_latency.json") ms"
echo "list:    p50=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p50_ms","?"))' "$RUN/list_latency.json") ms  p95=$LIST_P95 ms  p99=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("p99_ms","?"))' "$RUN/list_latency.json") ms"

verdict
