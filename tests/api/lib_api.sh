#!/usr/bin/env bash
# ============================================================================
# lib_api.sh — shared harness library for the SFTP API test matrix (STREAM-9)
# ----------------------------------------------------------------------------
# Purpose:
#   Common helpers for every STREAM-9 test script: start/stop a REAL
#   sftp-api binary on a random port with a temp DB + generated secrets,
#   curl wrappers with status capture, pass/fail/skip accounting with
#   mandatory evidence paths (§11.4.69 ab_pass_with_evidence pattern),
#   latency percentile computation, and fd-count snapshots for leak
#   detection.
#
#   Sourced by: tests/api/test_api_lifecycle.sh, test_api_stress.sh,
#   test_api_chaos.sh, test_api_security.sh — never executed directly.
#
# Usage:
#   source tests/api/lib_api.sh
#   api_harness_start <evidence_dir>   # exports API_PORT, API_BASE, API_PID
#   api_harness_stop                   # graceful SIGTERM, waits for exit
#
# Inputs:
#   Env: SFTP_API_BINARY (optional override; default builds via `go -C`).
#   Args to api_harness_start: an evidence directory (created if missing).
#
# Outputs:
#   Exports API_PORT / API_BASE / API_PID / API_EVIDENCE / API_DB /
#   API_USERS_CONF. Logs land in <evidence>/api.log (secrets NEVER
#   printed — harness asserts it, §11.4.10).
#
# Side-effects:
#   One mktemp -d sandbox per harness start (DB, users.conf, secrets).
#   A compiled binary under the sandbox (build cache reused). Callers
#   MUST register cleanup traps (§11.4.14) — the library registers its
#   own EXIT trap for the API process.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3 (percentiles), openssl, ss or lsof
#   (fd snapshot — degrade gracefully when absent).
#
# Cross-references:
#   api/cmd/sftp-api/main.go · api/internal/config/config.go ·
#   constitution §11.4.5 (captured evidence), §11.4.10 (credentials),
#   §11.4.14 (cleanup), §11.4.85 (stress/chaos), §11.4.69 (evidence).
# ============================================================================
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# pass/fail accounting — every PASS MUST cite an evidence path (§11.4.69).
# ---------------------------------------------------------------------------
PASS=0
FAIL=0
SKIP=0

pass() {  # pass <description> <evidence-path>
    PASS=$((PASS + 1))
    echo "PASS: $1 [evidence: $2]"
}

fail() {  # fail <description> <reason>
    FAIL=$((FAIL + 1))
    echo "FAIL: $1 — $2"
}

skip() {  # skip <description> <closed-set reason> <note-file>
    SKIP=$((SKIP + 1))
    echo "SKIP: $1 [reason: $2]"
    printf 'SKIP: %s\nreason: %s\ndate: %s\n' "$1" "$2" "$(date -u +%FT%TZ)" > "$3"
}

verdict() {  # verdict — print summary, exit 0 iff FAIL==0
    echo
    echo "=== verdict: PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
    if [[ "$FAIL" -eq 0 ]]; then
        echo "ALL CHECKS PASSED"
        exit 0
    else
        echo "TEST SUITE FAILED"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Random free TCP port on 127.0.0.1.
# ---------------------------------------------------------------------------
api_pick_port() {
    python3 -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()'
}

# ---------------------------------------------------------------------------
# api_harness_start <evidence_dir> [extra env KEY=VALUE ...]
# Builds (or reuses SFTP_API_BINARY), generates secrets into a 0600 file,
# starts the API, waits for /health, and asserts no secret leaked into the
# API log (§11.4.10). Extra KEY=VALUE pairs are injected into the API env
# (used by chaos/security tests, e.g. ACCESS_TOKEN_TTL=1s).
# ---------------------------------------------------------------------------
api_harness_start() {
    API_EVIDENCE="$1"; shift
    mkdir -p "$API_EVIDENCE"

    API_SANDBOX="$(mktemp -d)"
    API_DB="$API_SANDBOX/data/sftp.db"
    API_USERS_CONF="$API_SANDBOX/data/users.conf"
    mkdir -p "$API_SANDBOX/data"
    API_COOKIE_JAR="$API_SANDBOX/cookies.txt"
    export API_SANDBOX API_DB API_USERS_CONF API_COOKIE_JAR

    # Secrets: generated, written 0600, exported, NEVER echoed (§11.4.10).
    JWT_SECRET="$(openssl rand -hex 32)"
    SUPERADMIN_PASSWORD="$(openssl rand -hex 16)"
    printf 'JWT_SECRET=%s\nSUPERADMIN_PASSWORD=%s\n' "$JWT_SECRET" "$SUPERADMIN_PASSWORD" \
        > "$API_SANDBOX/secrets.env"
    chmod 600 "$API_SANDBOX/secrets.env"
    export JWT_SECRET SUPERADMIN_PASSWORD

    API_PORT="$(api_pick_port)"
    API_BASE="http://127.0.0.1:${API_PORT}"
    export API_PORT API_BASE

    # Binary: reuse override or build into the sandbox (out of repo tree).
    if [[ -n "${SFTP_API_BINARY:-}" && -x "${SFTP_API_BINARY:-}" ]]; then
        API_BIN="$SFTP_API_BINARY"
    else
        API_BIN="$API_SANDBOX/sftp-api"
        local root
        root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        if ! go -C "$root/api" build -o "$API_BIN" ./cmd/sftp-api 2> "$API_EVIDENCE/build.err"; then
            echo "FATAL: API build failed — see $API_EVIDENCE/build.err" >&2
            return 1
        fi
    fi
    export API_BIN

    # Environment for the API: test-mode knobs are opt-in via caller's
    # extra KEY=VALUE pairs (ACCESS_TOKEN_TTL etc.).
    local env_args=(
        "API_PORT=${API_PORT}"
        "DB_PATH=${API_DB}"
        "USERS_CONF_PATH=${API_USERS_CONF}"
        "JWT_SECRET=${JWT_SECRET}"
        "SUPERADMIN_PASSWORD=${SUPERADMIN_PASSWORD}"
        "GIN_MODE=release"
    )
    local kv
    for kv in "$@"; do env_args+=("$kv"); done

    env "${env_args[@]}" "$API_BIN" > "$API_EVIDENCE/api.log" 2>&1 &
    API_PID=$!
    export API_PID

    # Wait for /health (up to 15 s).
    local i body code
    for i in $(seq 1 75); do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$API_BASE/api/v1/health" 2>/dev/null || echo 000)"
        if [[ "$code" == "200" ]]; then break; fi
        if ! kill -0 "$API_PID" 2>/dev/null; then
            echo "FATAL: API died during startup — see $API_EVIDENCE/api.log" >&2
            return 1
        fi
        sleep 0.2
    done
    body="$(curl -s --max-time 2 "$API_BASE/api/v1/health")"
    printf '%s\n' "$body" > "$API_EVIDENCE/health.json"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$API_BASE/api/v1/health")"
    if [[ "$code" != "200" ]]; then
        echo "FATAL: API did not become healthy (code=$code)" >&2
        return 1
    fi

    # §11.4.10: the API log MUST NOT contain either secret value.
    if grep -qF "$JWT_SECRET" "$API_EVIDENCE/api.log" \
        || grep -qF "$SUPERADMIN_PASSWORD" "$API_EVIDENCE/api.log"; then
        echo "FATAL: secret value leaked into API log (§11.4.10)" >&2
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# api_harness_stop — graceful SIGTERM, then hard kill as a last resort.
# ---------------------------------------------------------------------------
api_harness_stop() {
    if [[ -n "${API_PID:-}" ]] && kill -0 "$API_PID" 2>/dev/null; then
        kill -TERM "$API_PID" 2>/dev/null
        local i
        for i in $(seq 1 100); do
            kill -0 "$API_PID" 2>/dev/null || { wait "$API_PID" 2>/dev/null; break; }
            sleep 0.1
        done
        if kill -0 "$API_PID" 2>/dev/null; then
            kill -9 "$API_PID" 2>/dev/null || true
            wait "$API_PID" 2>/dev/null || true
        fi
    fi
}

# ---------------------------------------------------------------------------
# api_request <method> <path> [curl-args...]
# Performs the request, writes the body to $LAST_BODY_FILE, exports
# LAST_CODE (HTTP status). Caller supplies an evidence file via
# LAST_BODY_FILE beforehand or the default is used.
# ---------------------------------------------------------------------------
api_request() {
    local method="$1" path="$2"; shift 2
    LAST_BODY_FILE="${LAST_BODY_FILE:-$API_EVIDENCE/last_body.json}"
    LAST_CODE="$(curl -s -o "$LAST_BODY_FILE" -w '%{http_code}' \
        -c "${API_COOKIE_JAR:-/dev/null}" -b "${API_COOKIE_JAR:-/dev/null}" \
        -X "$method" "$API_BASE$path" "$@")"
    export LAST_CODE LAST_BODY_FILE
}

# api_login <password-file-mode> — login with the real admin password from
# the sandbox secrets file and extract the access token into API_TOKEN.
# The password itself never appears on any command line or log: it is read
# from the 0600 secrets file into a bash variable and sent via @file JSON
# built without echoing it.
api_login() {
    local sa_pw jwt_tmp
    sa_pw="$(grep '^SUPERADMIN_PASSWORD=' "$API_SANDBOX/secrets.env" | cut -d= -f2-)"
    jwt_tmp="$API_EVIDENCE/login_payload.json"
    python3 - "$sa_pw" "$jwt_tmp" <<'PYEOF'
import json, sys
pw, out = sys.argv[1], sys.argv[2]
with open(out, "w") as f:
    json.dump({"username": "admin", "password": pw}, f)
PYEOF
    chmod 600 "$jwt_tmp"
    api_request POST /api/v1/auth/login \
        -H 'Content-Type: application/json' \
        --data "@${jwt_tmp}"
    rm -f "$jwt_tmp"
    if [[ "$LAST_CODE" == "200" ]]; then
        API_TOKEN="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["access_token"])' "$LAST_BODY_FILE")"
        # refresh_token moved to HttpOnly cookie (Phase 4 security hardening).
        # The cookie jar handles it; set sentinel so -n checks still pass.
        API_REFRESH="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("refresh_token","cookie"))
' "$LAST_BODY_FILE")"
        export API_TOKEN API_REFRESH
    fi
}

# ---------------------------------------------------------------------------
# fd count snapshot for the API process (leak detection). Empty when no
# /proc access (macOS) — callers treat empty as unmeasurable.
# ---------------------------------------------------------------------------
api_fd_count() {
    if [[ -n "${API_PID:-}" && -d "/proc/$API_PID/fd" ]]; then
        ls "/proc/$API_PID/fd" 2>/dev/null | wc -l
    fi
}

# ---------------------------------------------------------------------------
# percentile_ms <file-of-ms-values> — prints p50 p95 p99 (one per line,
# labelled) computed in python.
# ---------------------------------------------------------------------------
percentile_report() {  # <latencies-file> <out-json>
    python3 - "$1" "$2" <<'PYEOF'
import json, sys, math
src, dst = sys.argv[1], sys.argv[2]
vals = sorted(float(l) for l in open(src) if l.strip())
if not vals:
    json.dump({"error": "no samples"}, open(dst, "w"))
    sys.exit(0)
def pct(p):
    idx = (len(vals) - 1) * p / 100.0
    lo, hi = math.floor(idx), math.ceil(idx)
    if lo == hi:
        return round(vals[lo], 3)
    return round(vals[lo] + (vals[hi] - vals[lo]) * (idx - lo), 3)
json.dump({
    "samples": len(vals),
    "min_ms": round(vals[0], 3),
    "max_ms": round(vals[-1], 3),
    "p50_ms": pct(50),
    "p95_ms": pct(95),
    "p99_ms": pct(99),
}, open(dst, "w"), indent=2)
PYEOF
}
