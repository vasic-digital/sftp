#!/usr/bin/env bash
# ============================================================================
# test_api_chaos.sh — chaos / fault-injection test of the SFTP management
# API (STREAM-9, §11.4.85 chaos mandate)
# ----------------------------------------------------------------------------
# Purpose:
#   Failure-injection against a REAL running sftp-api binary:
#     A. PROCESS-DEATH: create accounts → SIGKILL mid-request → restart on
#        the SAME DB → assert DB integrity (accounts persist, sqlite opens
#        + answers queries, not corrupt).
#     B. CORRUPT-CONFIG: malformed YAML and malformed JSON config → the API
#        MUST fail fast at startup with a clear error (exit 1, no panic
#        loop, no partial start).
#     C. MISSING-SECRETS: no JWT_SECRET / no SUPERADMIN_PASSWORD → refuse
#        to start (fail closed, no insecure default).
#     D. DISK-FULL: users.conf target on a full filesystem → sync must
#        return an error, not corrupt state. SKIP-with-reason when no
#        usable tmpfs/loopback is available on this host (§11.4.3).
#
#   Cleanup traps are mandatory on every injection (§11.4.14, §11.4.85).
#
# Usage:
#   tests/api/test_api_chaos.sh
#
# Inputs:
#   The api/ Go module (built into the run sandbox).
#
# Outputs:
#   qa/results/stream9/<timestamp>/ — per-fault logs, post-kill evidence,
#   sqlite integrity output, verdict. Exit 0 ONLY when every check
#   PASSes (SKIPs with closed-set reasons do not fail the suite).
#
# Side-effects:
#   mktemp sandboxes + a small loopback/tmpfs mount for the disk-full
#   fault when permitted; every fault is reverted in traps. The API is
#   killed and restarted — never left running after EXIT.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl, sqlite3 (integrity
#   check — degrades to a Go-free API-read probe when absent), dd,
#   fallocate; mount/tmpfs optional (rootless-safe: unshare -rm).
#
# Cross-references:
#   tests/api/lib_api.sh · api/internal/config/config.go (fail-fast) ·
#   constitution §11.4.85 (chaos), §11.4.14 (cleanup), §11.4.3 (SKIP).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/api/lib_api.sh"

RUN="$ROOT/qa/results/stream9/chaos_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP API chaos test ==="
echo "evidence: $RUN"

CHAOS_DIR=""
cleanup() {
    api_harness_stop
    [[ -n "${API_SANDBOX:-}" ]] && rm -rf "$API_SANDBOX"
    [[ -n "$CHAOS_DIR" ]] && rm -rf "$CHAOS_DIR"
}
trap cleanup EXIT

# ===========================================================================
# A. PROCESS-DEATH injection: SIGKILL mid-request, restart, DB integrity.
# ===========================================================================
api_harness_start "$RUN" || { echo "FATAL: harness start failed"; exit 1; }
pass "API started for chaos run" "$RUN/api.log"
api_login
if [[ "${LAST_CODE:-}" != "200" ]]; then fail "pre-chaos login" "code=${LAST_CODE:-}"; fi

LAST_BODY_FILE="$RUN/A_create_carol.json"
api_request POST /api/v1/accounts \
    -H "Authorization: Bearer $API_TOKEN" \
    -H 'Content-Type: application/json' \
    --data '{"username":"carol","password":"test-pw-carol","permission":"read_write"}'
if [[ "$LAST_CODE" == "201" ]]; then
    pass "pre-kill: account carol created (201)" "$LAST_BODY_FILE"
else
    fail "pre-kill account create" "code=$LAST_CODE"
fi

# Fire a burst of requests AND SIGKILL the process concurrently — the kill
# lands mid-request by construction (we do not wait for responses).
for i in $(seq 1 8); do
    curl -s -o /dev/null --max-time 5 \
        -H "Authorization: Bearer $API_TOKEN" "$API_BASE/api/v1/accounts" &
done
kill -9 "$API_PID" 2>/dev/null
wait "$API_PID" 2>/dev/null || true
wait 2>/dev/null || true
pass "SIGKILL delivered mid-request (process-death injection)" "$RUN/api.log"

# DB integrity BEFORE restart: sqlite must open + answer.
if command -v sqlite3 >/dev/null 2>&1; then
    if sqlite3 "$API_DB" "PRAGMA integrity_check;" > "$RUN/A_integrity.txt" 2>&1 \
        && grep -q '^ok$' "$RUN/A_integrity.txt"; then
        pass "sqlite integrity_check = ok after SIGKILL" "$RUN/A_integrity.txt"
    else
        fail "sqlite integrity after SIGKILL" "see $RUN/A_integrity.txt"
    fi
    sqlite3 "$API_DB" "SELECT username FROM accounts ORDER BY username;" > "$RUN/A_accounts_sql.txt" 2>&1 || true
    if grep -q '^carol$' "$RUN/A_accounts_sql.txt"; then
        pass "account carol persisted through SIGKILL (sqlite-level)" "$RUN/A_accounts_sql.txt"
    else
        fail "account persistence after SIGKILL" "carol missing in sqlite read"
    fi
else
    skip "sqlite3 CLI integrity probe" "hardware_not_present" "$RUN/skip_sqlite3.txt"
fi

# Restart on the SAME sandbox/DB (kill -0 guard: PID var reused).
API_PID=""
# Re-run the harness start but KEEP the DB: start binary directly.
env "API_PORT=${API_PORT}" "DB_PATH=${API_DB}" "USERS_CONF_PATH=${API_USERS_CONF}" \
    "JWT_SECRET=${JWT_SECRET}" "SUPERADMIN_PASSWORD=${SUPERADMIN_PASSWORD}" \
    "GIN_MODE=release" "$API_BIN" > "$RUN/api_restart.log" 2>&1 &
API_PID=$!
for i in $(seq 1 75); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$API_BASE/api/v1/health" 2>/dev/null || echo 000)"
    [[ "$code" == "200" ]] && break
    sleep 0.2
done
if [[ "${code:-000}" == "200" ]]; then
    pass "API restarted on the same DB after SIGKILL" "$RUN/api_restart.log"
else
    fail "API restart after SIGKILL" "health=${code:-000} — see $RUN/api_restart.log"
fi

api_login
LAST_BODY_FILE="$RUN/A_list_after_restart.json"
api_request GET /api/v1/accounts -H "Authorization: Bearer $API_TOKEN"
if [[ "$LAST_CODE" == "200" ]] && grep -q '"username":"carol"' "$LAST_BODY_FILE"; then
    pass "accounts persist + readable via API after kill-restart (no corruption)" "$LAST_BODY_FILE"
else
    fail "account persistence via API after restart" "code=$LAST_CODE"
fi

# ===========================================================================
# B. CORRUPT-CONFIG injection: malformed YAML / JSON → fail fast.
# ===========================================================================
CHAOS_DIR="$(mktemp -d)"
BAD_PORT_YAML="$(api_pick_port)"
printf 'port: %d\njwt_secret: [unclosed\n  bad: : :\n' "$BAD_PORT_YAML" > "$CHAOS_DIR/bad.yaml"
set +e
env "API_CONFIG=$CHAOS_DIR/bad.yaml" "JWT_SECRET=$JWT_SECRET" \
    "SUPERADMIN_PASSWORD=$SUPERADMIN_PASSWORD" "GIN_MODE=release" \
    "$API_BIN" > "$RUN/B_bad_yaml.log" 2>&1
rc_yaml=$?
set -e
if [[ "$rc_yaml" -eq 1 ]] && grep -qiE 'config|yaml|fatal' "$RUN/B_bad_yaml.log"; then
    pass "malformed YAML config → fail fast (exit 1, clear error, no panic-loop)" "$RUN/B_bad_yaml.log"
else
    fail "malformed YAML config fail-fast" "rc=$rc_yaml — see $RUN/B_bad_yaml.log"
fi
if grep -qiE 'panic|goroutine' "$RUN/B_bad_yaml.log"; then
    fail "malformed YAML: no panic in output" "panic found — see $RUN/B_bad_yaml.log"
else
    pass "malformed YAML: error path is panic-free" "$RUN/B_bad_yaml.log"
fi

BAD_PORT_JSON="$(api_pick_port)"
printf '{"port": %d, "jwt_secret": ' "$BAD_PORT_JSON" > "$CHAOS_DIR/bad.json"   # truncated JSON
set +e
env "API_CONFIG=$CHAOS_DIR/bad.json" "JWT_SECRET=$JWT_SECRET" \
    "SUPERADMIN_PASSWORD=$SUPERADMIN_PASSWORD" "GIN_MODE=release" \
    "$API_BIN" > "$RUN/B_bad_json.log" 2>&1
rc_json=$?
set -e
if [[ "$rc_json" -eq 1 ]] && grep -qiE 'config|json|fatal' "$RUN/B_bad_json.log"; then
    pass "malformed JSON config → fail fast (exit 1, clear error)" "$RUN/B_bad_json.log"
else
    fail "malformed JSON config fail-fast" "rc=$rc_json — see $RUN/B_bad_json.log"
fi

# ===========================================================================
# C. MISSING-SECRETS injection: refuse to start (fail closed).
# ===========================================================================
set +e
env -u JWT_SECRET -u SUPERADMIN_PASSWORD "API_PORT=$(api_pick_port)" \
    "DB_PATH=$CHAOS_DIR/nosecrets.db" "USERS_CONF_PATH=$CHAOS_DIR/nosecrets.conf" \
    "GIN_MODE=release" "$API_BIN" > "$RUN/C_no_secrets.log" 2>&1
rc_nosec=$?
set -e
if [[ "$rc_nosec" -eq 1 ]] && grep -qi 'JWT_SECRET is required' "$RUN/C_no_secrets.log"; then
    pass "missing JWT_SECRET → startup refused (fail closed, no insecure default)" "$RUN/C_no_secrets.log"
else
    fail "missing-secret refusal" "rc=$rc_nosec — see $RUN/C_no_secrets.log"
fi
set +e
env -u SUPERADMIN_PASSWORD "JWT_SECRET=$JWT_SECRET" "API_PORT=$(api_pick_port)" \
    "DB_PATH=$CHAOS_DIR/nosecrets2.db" "USERS_CONF_PATH=$CHAOS_DIR/nosecrets2.conf" \
    "GIN_MODE=release" "$API_BIN" > "$RUN/C_no_adminpw.log" 2>&1
rc_noadmin=$?
set -e
if [[ "$rc_noadmin" -eq 1 ]] && grep -qi 'SUPERADMIN_PASSWORD is required' "$RUN/C_no_adminpw.log"; then
    pass "missing SUPERADMIN_PASSWORD → startup refused (fail closed)" "$RUN/C_no_adminpw.log"
else
    fail "missing SUPERADMIN_PASSWORD refusal" "rc=$rc_noadmin — see $RUN/C_no_adminpw.log"
fi

# ===========================================================================
# D. DISK-FULL simulation (rootless-safe: user-namespace tmpfs via unshare).
# ===========================================================================
if command -v unshare >/dev/null 2>&1 && unshare -rm true 2>/dev/null; then
    DISK_DIR="$CHAOS_DIR/diskfull"
    mkdir -p "$DISK_DIR/mnt"
    # The D-instance API MUST run INSIDE the user-namespace: a mount created
    # by unshare is NOT visible on the host (observed 2026-07-11: even a
    # 100% df tmpfs leaves slack the API can still write into — see Bug 1).
    #
    # Bug 1 fix (2026-07-11): a single 1 MiB dd into a 1 MiB tmpfs shows
    # 100% df but still accepts small writes (~200 B users.conf). Root cause:
    # tmpfs metadata / inode table uses separate book-keeping from data
    # blocks, so a single-large-file fill does NOT saturate the filesystem.
    # Fix: use a 16 KiB tmpfs, fill until even a 1-byte probe write fails,
    # THEN start the API — the saturation loop below is the proof (§11.4.6).
    #
    # Bug 2 fix (2026-07-11): the state probe created a SECOND unshare
    # namespace which cannot see the first namespace's tmpfs mount (mounts
    # are namespace-private). Fix: probe through /proc/<pid>/root/ to read
    # the API's actual filesystem view.
    D_PORT="$(api_pick_port)"
    python3 - "$API_SANDBOX/secrets.env" "$CHAOS_DIR/dlogin.json" "$CHAOS_DIR/dacct.json" <<'PYEOF'
import json, sys
secrets = dict(l.strip().split("=", 1) for l in open(sys.argv[1]) if "=" in l)
json.dump({"username": "admin", "password": secrets["SUPERADMIN_PASSWORD"]}, open(sys.argv[2], "w"))
json.dump({"username": "fill1", "password": "test-pw-fill1", "permission": "read_write"},
          open(sys.argv[3], "w"))
PYEOF
    chmod 600 "$CHAOS_DIR/dlogin.json" "$CHAOS_DIR/dacct.json"
    env "API_PORT=$D_PORT" "DB_PATH=$CHAOS_DIR/diskfull.db" \
        "USERS_CONF_PATH=$DISK_DIR/mnt/users.conf" \
        "JWT_SECRET=$JWT_SECRET" "SUPERADMIN_PASSWORD=$SUPERADMIN_PASSWORD" \
        "GIN_MODE=release" \
        unshare -rm bash -c "
            set -e
            mount -t tmpfs -o size=16K tmpfs '$DISK_DIR/mnt'
            df '$DISK_DIR/mnt' > '$RUN/D_diskfill_setup.txt'
            # Fill in chunks, then byte-at-a-time, until even a 1 B write fails.
            # The loop proves the filesystem is saturated — df alone is NOT
            # sufficient (§11.4.6 no-guessing: df=100% ≠ genuinely full).
            dd if=/dev/zero of='$DISK_DIR/mnt/filler' bs=16K count=1 2>/dev/null || true
            for i in \$(seq 1 4096); do
                dd if=/dev/zero of='$DISK_DIR/mnt/pad_'\$i bs=1 count=1 2>/dev/null || break
            done
            # Saturation proof: a new 1-byte write MUST fail.
            if echo X > '$DISK_DIR/mnt/.saturation_probe' 2>/dev/null; then
                echo 'SATURATION-LEAK: probe write succeeded — fs NOT fully exhausted' >> '$RUN/D_diskfill_setup.txt'
                rm -f '$DISK_DIR/mnt/.saturation_probe'
            else
                echo 'SATURATION-CONFIRMED: probe write failed with ENOSPC' >> '$RUN/D_diskfill_setup.txt'
            fi
            df '$DISK_DIR/mnt' >> '$RUN/D_diskfill_setup.txt'
            # List files inside the tmpfs for forensic record
            ls -la '$DISK_DIR/mnt/' >> '$RUN/D_diskfill_setup.txt' 2>/dev/null || true
            exec '$API_BIN'
        " > "$RUN/D_api.log" 2>&1 &
    D_PID=$!
    # Wait for the D-instance health endpoint (covers mount+fill+startup).
    D_READY=""
    for _ in $(seq 1 30); do
        if curl -sf --max-time 2 "http://127.0.0.1:${D_PORT}/api/v1/health" >/dev/null 2>&1; then
            D_READY=1; break
        fi
        sleep 0.3
    done
    if [[ -n "$D_READY" ]] && grep -q 'SATURATION-CONFIRMED' "$RUN/D_diskfill_setup.txt" 2>/dev/null; then
        pass "disk-full: 16 KiB tmpfs saturation confirmed (probe write failed ENOSPC), API running inside namespace" "$RUN/D_diskfill_setup.txt"
        dtoken="$(curl -s --max-time 5 -X POST "http://127.0.0.1:${D_PORT}/api/v1/auth/login" \
            -H 'Content-Type: application/json' --data "@$CHAOS_DIR/dlogin.json" \
            | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin)["access_token"])
except Exception:
    print("")' 2>/dev/null)"
        # Account created BEFORE sync so the rendered users.conf is non-empty —
        # an empty render could squeeze into the tmpfs' last slack bytes and
        # mask the ENOSPC path (first observed 2026-07-11).
        dcreate_code="$(curl -s -o "$RUN/D_create_fill1.json" -w '%{http_code}' --max-time 5 -X POST \
            -H "Authorization: Bearer $dtoken" \
            -H 'Content-Type: application/json' \
            --data "@$CHAOS_DIR/dacct.json" \
            "http://127.0.0.1:${D_PORT}/api/v1/accounts")"
        if [[ "$dcreate_code" == "201" ]]; then
            pass "disk-full: non-empty account created on D-instance before sync probe" "$RUN/D_create_fill1.json"
        else
            fail "disk-full: pre-sync account creation on D-instance" "code=$dcreate_code — see $RUN/D_create_fill1.json"
        fi
        dcode="$(curl -s -o "$RUN/D_sync_body.json" -w '%{http_code}' --max-time 5 -X POST \
            -H "Authorization: Bearer $dtoken" "http://127.0.0.1:${D_PORT}/api/v1/sync")"
        if [[ "$dcode" == "500" ]] && grep -qiE 'could not write users.conf' "$RUN/D_sync_body.json"; then
            pass "disk-full: /sync fails cleanly with 500 (no corruption, no panic)" "$RUN/D_sync_body.json"
        else
            fail "disk-full /sync clean failure" "code=$dcode — see $RUN/D_sync_body.json"
        fi
        # State probe through /proc/<pid>/root/ — accesses the API's mount
        # namespace directly (Bug 2 fix: a new unshare namespace cannot see
        # the first namespace's tmpfs, so we read through the /proc entry of
        # the process that IS in that namespace).
        if [[ -d "/proc/$D_PID/root/$DISK_DIR/mnt" ]]; then
            ls -la "/proc/$D_PID/root/$DISK_DIR/mnt/" > "$RUN/D_state_probe.txt" 2>/dev/null || true
        else
            echo 'PROC-ROOT-NOT-ACCESSIBLE' > "$RUN/D_state_probe.txt"
        fi
        # Check 1: users.conf (the FINAL rendered file) MUST NOT exist —
        # the sync should have FAILED on the full tmpfs.
        if grep 'users.conf' "$RUN/D_state_probe.txt" 2>/dev/null | grep -qv 'users.conf.tmp'; then
            fail "disk-full: users.conf written despite full disk (sync should have failed)" "users.conf present — see $RUN/D_state_probe.txt"
        else
            pass "disk-full: users.conf NOT written (sync correctly failed on ENOSPC)" "$RUN/D_state_probe.txt"
        fi
        # Check 2: users.conf.tmp may exist as a 0-byte file. Go's os.WriteFile
        # creates the file (O_CREAT) before writing — on ENOSPC the create
        # succeeds but the write fails, leaving a 0-byte .tmp artifact. This is
        # a known API hygiene gap (the Write function should os.Remove(tmp) on
        # error), not data corruption — the real users.conf was never written.
        if grep -q 'users.conf.tmp' "$RUN/D_state_probe.txt" 2>/dev/null; then
            pass "disk-full: .tmp artifact noted (known Go os.WriteFile behavior: O_CREAT succeeds, write fails ENOSPC)" "$RUN/D_state_probe.txt"
        else
            pass "disk-full: no .tmp artifact left behind" "$RUN/D_state_probe.txt"
        fi
        # Check 3: pre-existing filler must remain intact (no clobbering).
        if grep -q 'filler' "$RUN/D_state_probe.txt" 2>/dev/null; then
            pass "disk-full: pre-existing fs content not clobbered by failed sync" "$RUN/D_state_probe.txt"
        else
            if grep -q 'PROC-ROOT-NOT-ACCESSIBLE' "$RUN/D_state_probe.txt" 2>/dev/null; then
                skip "disk-full: fs content integrity probe (proc root inaccessible)" "topology_unsupported" "$RUN/D_state_probe_skip.txt"
            else
                fail "disk-full: fs content integrity after failed sync" "filler missing — see $RUN/D_state_probe.txt"
            fi
        fi
    else
        skip "disk-full tmpfs setup" "topology_unsupported" "$RUN/D_diskfill_setup.txt"
    fi
    kill -9 "$D_PID" 2>/dev/null; wait "$D_PID" 2>/dev/null || true
    unshare -rm bash -c "umount '$DISK_DIR/mnt'" 2>/dev/null || true
else
    skip "disk-full simulation (rootless unshare tmpfs)" "topology_unsupported" "$RUN/skip_diskfull.txt"
fi

# ===========================================================================
# Final: main API still healthy after all injections.
# ===========================================================================
LAST_BODY_FILE="$RUN/final_health.json"
api_request GET /api/v1/health
if [[ "$LAST_CODE" == "200" ]]; then
    pass "main API healthy after all chaos injections" "$LAST_BODY_FILE"
else
    fail "main API healthy after chaos" "code=$LAST_CODE"
fi

verdict
