#!/usr/bin/env bash
# ============================================================================
# test_api_stress.sh — stress test of the SFTP management API (STREAM-9,
# §11.4.85 stress mandate)
# ----------------------------------------------------------------------------
# Purpose:
#   Sustained-load + concurrent-contention stress against a REAL running
#   sftp-api binary:
#     A. SEQUENTIAL: ≥100 login+list cycles, each cycle = health + login +
#        list accounts; per-cycle latency recorded in milliseconds.
#     B. CONCURRENT: 12 parallel workers × 10 cycles each (≥10 concurrent
#        invocations), same cycle shape.
#   Assertions (§11.4.85): zero 5xx responses, zero transport failures,
#   p50/p95/p99 latencies recorded to latency.json, and no connection/fd
#   leak (fd count before vs after, bounded growth).
#
# Usage:
#   tests/api/test_api_stress.sh
#   STRESS_SEQ_CYCLES=120 STRESS_PAR_WORKERS=12 STRESS_PAR_CYCLES=10 \
#       tests/api/test_api_stress.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox). Env overrides for
#   cycle counts (defaults above; minimums enforced: 100 seq / 10 workers).
#
# Outputs:
#   qa/results/stream9/<timestamp>/ — latency.json (p50/p95/p99), raw
#   latency samples, per-worker logs, fd snapshots, verdict.
#   Exit 0 ONLY when every check PASSes.
#
# Side-effects:
#   One mktemp sandbox + evidence dir; API stopped + sandbox removed on
#   EXIT (§11.4.14). CPU/network load on 127.0.0.1 only, bounded.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl.
#
# Cross-references:
#   tests/api/lib_api.sh · constitution §11.4.85 (stress), §11.4.50
#   (deterministic evidence), §11.4.69 (evidence paths), §12.6 (bounded).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

SEQ_CYCLES="${STRESS_SEQ_CYCLES:-100}"
PAR_WORKERS="${STRESS_PAR_WORKERS:-12}"
PAR_CYCLES="${STRESS_PAR_CYCLES:-10}"
# §11.4.85 floors — never silently de-rate below the mandate.
[[ "$SEQ_CYCLES" -lt 100 ]] && SEQ_CYCLES=100
[[ "$PAR_WORKERS" -lt 10 ]] && PAR_WORKERS=10

RUN="$ROOT/qa/results/stream9/stress_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API stress test (seq=$SEQ_CYCLES, par=${PAR_WORKERS}x${PAR_CYCLES}) ==="
echo "evidence: $RUN"

cleanup() { api_harness_stop; [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"; }
trap cleanup EXIT

# The auth endpoints carry a 10/min per-IP login rate limit by design;
# stress measures the API SURFACE under load, so the limit is lifted for
# this run (its enforcement is verified separately in test_api_security.sh
# under its real default — §11.4.6: the configuration delta is explicit,
# never hidden).
api_harness_start "$RUN" "LOGIN_RATE_LIMIT=1000000" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started for stress run (login rate limit lifted — surface stress, not limit test)" "$RUN/api.log"

# Login request payload built ONCE (password never on a command line per
# request — same @file pattern as lib_api.sh api_login).
SA_PW="$(grep '^SUPERADMIN_PASSWORD=' "$API_SANDBOX/secrets.env" | cut -d= -f2-)"
LOGIN_PAYLOAD="$API_SANDBOX/login.json"
python3 - "$SA_PW" "$LOGIN_PAYLOAD" <<'PYEOF'
import json, sys
with open(sys.argv[2], "w") as f:
    json.dump({"username": "admin", "password": sys.argv[1]}, f)
PYEOF
chmod 600 "$LOGIN_PAYLOAD"

# one_cycle <tag> <latfile> — health + login + list; appends the cycle
# latency in ms to <latfile>; records any non-2xx/transport failure to
# <latfile>.errors. Returns 0 always (errors counted from the file so
# `set -e` never masks a sample).
one_cycle() {
    local latfile="$1" errfile="$2" t0 t1 code token
    t0="$(date +%s%N)"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$API_BASE/api/v1/health")"
    if [[ "$code" != "200" ]]; then echo "health=$code" >> "$errfile"; return 0; fi
    token="$(curl -s --max-time 10 -X POST "$API_BASE/api/v1/auth/login" \
        -H 'Content-Type: application/json' --data "@$LOGIN_PAYLOAD" \
        | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["access_token"])
except Exception:
    print("")' 2>/dev/null)"
    if [[ -z "$token" ]]; then echo "login_failed" >> "$errfile"; return 0; fi
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -H "Authorization: Bearer $token" "$API_BASE/api/v1/accounts")"
    if [[ "$code" != "200" ]]; then echo "list=$code" >> "$errfile"; return 0; fi
    t1="$(date +%s%N)"
    echo $(( (t1 - t0) / 1000000 )) >> "$latfile"
}

# --- A. sequential sustained load ---------------------------------------------
FD_BEFORE="$(api_fd_count)"
echo "$FD_BEFORE" > "$RUN/fd_before.txt"
: > "$RUN/lat_seq.txt"; : > "$RUN/lat_seq.errors"
for i in $(seq 1 "$SEQ_CYCLES"); do
    one_cycle "$RUN/lat_seq.txt" "$RUN/lat_seq.errors"
done
seq_samples="$(wc -l < "$RUN/lat_seq.txt")"
seq_errors="$(wc -l < "$RUN/lat_seq.errors")"

if [[ "$seq_samples" -eq "$SEQ_CYCLES" ]]; then
    pass "sequential sustained load: $SEQ_CYCLES/$SEQ_CYCLES cycles completed" "$RUN/lat_seq.txt"
else
    fail "sequential sustained load" "$seq_samples/$SEQ_CYCLES completed"
fi
if [[ "$seq_errors" -eq 0 ]]; then
    pass "sequential phase: zero 5xx / transport failures" "$RUN/lat_seq.errors"
else
    fail "sequential phase failures" "$seq_errors errors — see $RUN/lat_seq.errors"
fi

# --- B. concurrent contention --------------------------------------------------
: > "$RUN/lat_par.txt"; : > "$RUN/lat_par.errors"
pids=()
for w in $(seq 1 "$PAR_WORKERS"); do
    (
        wlat="$RUN/lat_par_w${w}.txt"; werr="$RUN/lat_par_w${w}.errors"
        : > "$wlat"; : > "$werr"
        for c in $(seq 1 "$PAR_CYCLES"); do
            one_cycle "$wlat" "$werr"
        done
    ) &
    pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done
cat "$RUN"/lat_par_w*.txt >> "$RUN/lat_par.txt"
cat "$RUN"/lat_par_w*.errors >> "$RUN/lat_par.errors"

par_samples="$(wc -l < "$RUN/lat_par.txt")"
par_errors="$(wc -l < "$RUN/lat_par.errors")"
par_expected=$(( PAR_WORKERS * PAR_CYCLES ))
if [[ "$par_samples" -eq "$par_expected" ]]; then
    pass "concurrent contention: $par_expected/$par_expected cycles completed ($PAR_WORKERS workers)" "$RUN/lat_par.txt"
else
    fail "concurrent contention" "$par_samples/$par_expected completed"
fi
if [[ "$par_errors" -eq 0 ]]; then
    pass "concurrent phase: zero 5xx / deadlock / transport failures" "$RUN/lat_par.errors"
else
    fail "concurrent phase failures" "$par_errors errors — see $RUN/lat_par.errors"
fi

# --- C. latency percentiles -----------------------------------------------------
cat "$RUN/lat_seq.txt" "$RUN/lat_par.txt" > "$RUN/lat_all.txt"
percentile_report "$RUN/lat_all.txt" "$RUN/latency.json"
if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "p95_ms" in d else 1)' "$RUN/latency.json"; then
    pass "latency percentiles recorded (p50/p95/p99)" "$RUN/latency.json"
else
    fail "latency percentiles recorded" "latency.json malformed"
fi
echo "--- latency.json ---"; cat "$RUN/latency.json"; echo

# --- D. fd / connection leak check ----------------------------------------------
sleep 2  # let keep-alive sockets drain
FD_AFTER="$(api_fd_count)"
echo "$FD_AFTER" > "$RUN/fd_after.txt"
if [[ -n "$FD_BEFORE" && -n "$FD_AFTER" ]]; then
    growth=$(( FD_AFTER - FD_BEFORE ))
    echo "$growth" > "$RUN/fd_growth.txt"
    if [[ "$growth" -le 10 ]]; then
        pass "no connection/fd leak (before=$FD_BEFORE after=$FD_AFTER growth=$growth ≤ 10)" "$RUN/fd_growth.txt"
    else
        fail "fd leak suspected" "before=$FD_BEFORE after=$FD_AFTER growth=$growth"
    fi
else
    skip "fd leak check" "hardware_not_present" "$RUN/skip_fd.txt"
fi

# --- E. server still healthy after the storm ------------------------------------
LAST_BODY_FILE="$RUN/final_health.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]]; then
    pass "API still healthy after stress (no wedge, §11.4.85)" "$LAST_BODY_FILE"
else
    fail "API healthy after stress" "code=$LAST_CODE"
fi

verdict
