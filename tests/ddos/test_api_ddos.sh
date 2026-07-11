#!/usr/bin/env bash
# ============================================================================
# test_api_ddos.sh — DDoS resilience test of the SFTP management API
# (STREAM-9, §11.4.85 stress/chaos mandate — connection-flood + rate-limit
# enforcement subset)
# ----------------------------------------------------------------------------
# Purpose:
#   Verifies the API remains responsive under a connection flood against the
#   login endpoint while its DEFAULT 10/min per-IP rate limit is engaged.
#   Unlike test_api_stress.sh (which LIFTS the rate limit for surface-stress),
#   THIS test keeps the real limit to prove it engages CORRECTLY:
#
#     Phase 1 — CONNECTION FLOOD: 50 concurrent curl processes hammer
#               POST /api/v1/auth/login with wrong credentials for ~5 s.
#     Phase 2 — RATE LIMIT CHECK: after the flood, count how many requests
#               got 429 (rate-limited) vs non-429.  With 50 concurrent
#               connections from 127.0.0.1 and a 10/min default ceiling,
#               some MUST get 429.
#     Phase 3 — HEALTH DURING FLOOD: a health-check request fired mid-flood
#               (non-rate-limited endpoint) MUST still return 200 — proving
#               the API does not wedge under login-endpoint pressure.
#     Phase 4 — POST-FLOOD: a legitimate login after the flood subsides.
#               It may get 429 (window still active) or 200 (window lapsed);
#               either outcome is documented as evidence — never a guess.
#     Phase 5 — AGGREGATE: total flood requests, 429 count, non-429 count.
#
#   Assertions:
#     - The health endpoint survives the flood (200).
#     - At least one flood request got 429 (rate limiter engaged).
#     - The API process did not crash (PID still alive after flood).
#
# Usage:
#   tests/api/test_api_ddos.sh
#   FLOOD_WORKERS=50 FLOOD_SECONDS=5 tests/api/test_api_ddos.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox). Env overrides for
#   flood worker count and duration (defaults: 50 workers, 5 seconds).
#
# Outputs:
#   qa/results/stream9/ddos_<timestamp>/ — flood_results.txt (one line per
#   request: HTTP status code), health_during_flood.json, post_flood_login.json,
#   api.log, verdict summary.
#   Exit 0 ONLY when every check PASSes.
#
# Side-effects:
#   One mktemp sandbox + evidence dir; API stopped + sandbox removed on
#   EXIT (§11.4.14).  Heavy CPU/network load on 127.0.0.1 for ~5 s, bounded.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · constitution §11.4.85 (stress/chaos), §11.4.69
#   (evidence paths), §11.4.5 (captured evidence), §11.4.14 (cleanup).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

FLOOD_WORKERS="${FLOOD_WORKERS:-50}"
FLOOD_SECONDS="${FLOOD_SECONDS:-5}"
# Floors — a DDoS test with <10 workers is not a flood (§11.4.85)
[[ "$FLOOD_WORKERS" -lt 10 ]] && FLOOD_WORKERS=10

RUN="$ROOT/qa/results/stream9/ddos_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API DDoS resilience test (workers=$FLOOD_WORKERS, seconds=$FLOOD_SECONDS) ==="
echo "evidence: $RUN"

cleanup() {
    api_harness_stop
    [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Start the API with its DEFAULT rate limit (10/min per IP).
# The stress test lifts the limit with LOGIN_RATE_LIMIT=1000000; THIS test
# deliberately does NOT pass that override — the 10/min default MUST apply
# so the rate limiter engages and we can prove it works.
# ---------------------------------------------------------------------------
api_harness_start "$RUN" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started for DDoS resilience run (DEFAULT rate limit — 10/min per IP)" "$RUN/api.log"

# ---------------------------------------------------------------------------
# Login once with the real super-admin password to confirm a legitimate
# request works before the flood.  The token is kept for the post-flood
# check (Phase 4).
# ---------------------------------------------------------------------------
api_login
if [[ "$LAST_CODE" == "200" ]]; then
    pass "pre-flood login succeeded (token obtained for post-flood check)" "$LAST_BODY_FILE"
else
    fail "pre-flood login" "code=$LAST_CODE — cannot proceed"
    verdict
fi

# ---------------------------------------------------------------------------
# Build a "wrong password" payload for the flood workers.  The password
# itself never appears on a command line (§11.4.10).
# ---------------------------------------------------------------------------
FLOOD_PAYLOAD="$API_SANDBOX/flood_payload.json"
python3 - "$FLOOD_PAYLOAD" <<'PYEOF'
import json, sys
with open(sys.argv[1], "w") as f:
    json.dump({"username": "admin", "password": "WRONG_PASSWORD_FOR_FLOOD"}, f)
PYEOF
chmod 600 "$FLOOD_PAYLOAD"

# ---------------------------------------------------------------------------
# Per-worker temp directory for status-code output files.
# ---------------------------------------------------------------------------
FLOOD_TMP="$API_SANDBOX/flood_workers"
mkdir -p "$FLOOD_TMP"

# ---------------------------------------------------------------------------
# Phase 1 — CONNECTION FLOOD
# ---------------------------------------------------------------------------
# Each worker runs in a tight loop sending POST /api/v1/auth/login with
# wrong credentials for exactly FLOOD_SECONDS seconds.  Every response code
# is appended to <worker>.codes (one line per request).  A per-worker done
# marker signals completion so the controller can `wait` accurately.
# ---------------------------------------------------------------------------
FLOOD_START="$(date +%s)"
echo "flood_start_epoch=$FLOOD_START" > "$RUN/flood_meta.txt"

pids=()
for w in $(seq 1 "$FLOOD_WORKERS"); do
    (
        wcodes="$FLOOD_TMP/w${w}.codes"
        wdone="$FLOOD_TMP/w${w}.done"
        : > "$wcodes"
        deadline=$(( $(date +%s) + FLOOD_SECONDS ))
        while [[ "$(date +%s)" -lt "$deadline" ]]; do
            code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 \
                -X POST "$API_BASE/api/v1/auth/login" \
                -H 'Content-Type: application/json' \
                --data "@$FLOOD_PAYLOAD" 2>/dev/null || echo 000)"
            echo "$code" >> "$wcodes"
        done
        touch "$wdone"
    ) &
    pids+=($!)
done

# ---------------------------------------------------------------------------
# Phase 3 — HEALTH DURING FLOOD (fire after ~1 s so the flood is at peak)
# ---------------------------------------------------------------------------
sleep 1
HEALTH_DURING_CODE="$(curl -s -o "$RUN/health_during_flood.json" -w '%{http_code}' \
    --max-time 5 "$API_BASE/api/v1/health" 2>/dev/null || echo 000)"
echo "health_during_flood_code=$HEALTH_DURING_CODE" >> "$RUN/flood_meta.txt"

# ---------------------------------------------------------------------------
# Wait for every flood worker to finish.
# ---------------------------------------------------------------------------
for p in "${pids[@]}"; do wait "$p" || true; done

FLOOD_END="$(date +%s)"
echo "flood_end_epoch=$FLOOD_END" >> "$RUN/flood_meta.txt"
flood_duration=$(( FLOOD_END - FLOOD_START ))
echo "flood_duration_seconds=$flood_duration" >> "$RUN/flood_meta.txt"

# ---------------------------------------------------------------------------
# Phase 2 & 5 — AGGREGATE FLOOD RESULTS
# ---------------------------------------------------------------------------
FLOOD_RESULTS="$RUN/flood_results.txt"
: > "$FLOOD_RESULTS"
for w in $(seq 1 "$FLOOD_WORKERS"); do
    wcodes="$FLOOD_TMP/w${w}.codes"
    if [[ -f "$wcodes" ]]; then
        cat "$wcodes" >> "$FLOOD_RESULTS"
    fi
done

total_requests="$(wc -l < "$FLOOD_RESULTS")"
count_429="$(grep -c '^429$' "$FLOOD_RESULTS" || echo 0)"
count_non_429=$(( total_requests - count_429 ))
count_transport="$(grep -c '^000$' "$FLOOD_RESULTS" || echo 0)"

echo "total_requests=$total_requests"   >> "$RUN/flood_meta.txt"
echo "count_429=$count_429"            >> "$RUN/flood_meta.txt"
echo "count_non_429=$count_non_429"    >> "$RUN/flood_meta.txt"
echo "count_transport=$count_transport" >> "$RUN/flood_meta.txt"

echo "--- flood summary ---"
echo "total requests: $total_requests"
echo "429 (rate-limited): $count_429"
echo "non-429: $count_non_429"
echo "transport failures (000): $count_transport"

# Rate-limiter engagement: at least one request MUST have gotten 429.
# With 50 concurrent workers and a 10/min limit, this is guaranteed.
if [[ "$count_429" -gt 0 ]]; then
    pass "rate limiter engaged: $count_429/$total_requests flood requests got 429 (≥1 required)" "$FLOOD_RESULTS"
else
    fail "rate limiter engaged" "0/$total_requests got 429 — rate limiter may not be active"
fi

# Transport failure check: with 50 concurrent connections to localhost,
# transport failures (000) should be minimal.  A high count signals a
# server-side listen backlog exhaustion or crash.
if [[ "$count_transport" -le $(( total_requests / 10 )) ]]; then
    pass "transport resilience: $count_transport/$total_requests transport failures (≤10%)" "$FLOOD_RESULTS"
else
    fail "transport resilience" "$count_transport/$total_requests transport failures exceeds 10% — possible listen-backlog exhaustion"
fi

# ---------------------------------------------------------------------------
# Phase 3 verdict — HEALTH DURING FLOOD
# ---------------------------------------------------------------------------
if [[ "$HEALTH_DURING_CODE" == "200" ]]; then
    pass "health endpoint survived the flood (200 — API responsive for non-rate-limited endpoints)" "$RUN/health_during_flood.json"
else
    fail "health endpoint during flood" "code=$HEALTH_DURING_CODE — API wedged under login-endpoint pressure"
fi

# The API PID must still be alive.
if [[ -n "${API_PID:-}" ]] && kill -0 "$API_PID" 2>/dev/null; then
    pass "API process survived the DDoS flood (PID $API_PID still alive)" "$RUN/api.log"
else
    fail "API process survived the flood" "PID $API_PID is dead — server crashed under load"
fi

# ---------------------------------------------------------------------------
# Phase 4 — POST-FLOOD LEGITIMATE LOGIN
# ---------------------------------------------------------------------------
POST_FLOOD_CODE="$(curl -s -o "$RUN/post_flood_login.json" -w '%{http_code}' \
    --max-time 10 -X POST "$API_BASE/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    --data "{\"username\":\"admin\",\"password\":\"$(grep '^SUPERADMIN_PASSWORD=' "$API_SANDBOX/secrets.env" | cut -d= -f2-)\"}" \
    2>/dev/null || echo 000)"

echo "post_flood_login_code=$POST_FLOOD_CODE" >> "$RUN/flood_meta.txt"

if [[ "$POST_FLOOD_CODE" == "200" ]]; then
    pass "post-flood login: 200 (rate-limit window lapsed — API serving legitimate traffic again)" "$RUN/post_flood_login.json"
elif [[ "$POST_FLOOD_CODE" == "429" ]]; then
    pass "post-flood login: 429 (rate-limit window still active — expected behavior, documented as evidence)" "$RUN/post_flood_login.json"
else
    # Any other code (including 000 transport failure) is unexpected.
    fail "post-flood login" "code=$POST_FLOOD_CODE — expected 200 or 429 (rate-limit window); got unexpected response"
fi

verdict
