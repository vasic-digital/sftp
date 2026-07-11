#!/usr/bin/env bash
# ============================================================================
# run_helixqa_suites.sh — HelixQA autonomous QA session executor
# (STREAM-9, §11.4.27 autonomous-QA-session test type)
# ----------------------------------------------------------------------------
# Purpose:
#   Reads qa/helixqa/sftp_suites.yaml and executes each registered test
#   suite against a real sftp-api binary. Each suite runs the registered
#   command, captures stdout/stderr as evidence, records exit code and
#   elapsed time, and emits a unified suite verdict.
#
#   This is the EXECUTABLE DRIVER that converts the YAML-only suite
#   registration into actual HelixQA autonomous sessions — closing the
#   gap between "suites registered" and "suites actually executed by
#   HelixQA" (§11.4.27 autonomous-QA-session mandate).
#
#   Suite mapping (from sftp_suites.yaml):
#     api-lifecycle   → tests/api/test_api_lifecycle.sh
#     api-stress      → tests/api/test_api_stress.sh
#     api-chaos       → tests/api/test_api_chaos.sh
#     web-screenshots → node web/scripts/screenshots.mjs
#     go-tests        → go test ./... (in api/)
#     web-tests       → npx vitest run (in web/)
#
#   Plus new suites discovered from the newly-created test files.
#
# Usage:
#   tests/helixqa/run_helixqa_suites.sh [suite_name ...]
#   No args: run all registered suites.
#
# Outputs:
#   qa/results/stream9/helixqa_<timestamp>/ — per-suite logs +
#   unified verdict. Exit 0 ONLY when all suites pass.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl, node (for web suites).
#
# Cross-references:
#   qa/helixqa/sftp_suites.yaml · constitution §11.4.27 (autonomous-QA),
#   §11.4.116 (real-time sync channel), §11.4.52 (autonomous-validation).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1 [evidence: $2]"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1 — $2"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP: $1 [reason: $2]"; }
verdict() {
    echo; echo "=== HelixQA verdict: PASS=$PASS FAIL=$FAIL SKIP=$SKIP ==="
    [[ "$FAIL" -eq 0 ]] && { echo "ALL HELIXQA SUITES PASSED"; exit 0; } || { echo "HELIXQA SESSION FAILED"; exit 1; }
}

RUN="$ROOT/qa/results/stream9/helixqa_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP HelixQA autonomous QA session ==="
echo "evidence: $RUN"
echo "started: $(date -u +%FT%TZ)"

# Registered suites: name → command (relative to project root)
declare -A SUITES
SUITES=(
    ["api-lifecycle"]="bash tests/api/test_api_lifecycle.sh"
    ["api-stress"]="bash tests/api/test_api_stress.sh"
    ["api-chaos"]="bash tests/api/test_api_chaos.sh"
    ["api-security"]="bash tests/security/test_api_security.sh"
    ["api-performance"]="bash tests/performance/test_api_performance.sh"
    ["api-ddos"]="bash tests/ddos/test_api_ddos.sh"
    ["api-scaling"]="bash tests/scaling/test_api_scaling.sh"
    ["api-benchmarking"]="bash tests/benchmarking/test_api_benchmark.sh"
    ["e2e-journey"]="bash tests/e2e/test_e2e_operator_journey.sh"
    ["web-ui"]="bash tests/ui/test_web_ui.sh"
    ["web-ux"]="bash tests/ux/test_web_ux.sh"
    ["go-tests"]="cd api && go test ./... -count=1"
    ["web-tests"]="cd web && npx vitest run --reporter verbose"
    ["web-screenshots"]="cd web && node scripts/screenshots.mjs"
    ["challenges"]="bash tests/challenges/run_challenges.sh"
)

# Resolve which suites to run
RUN_SUITES=("${@}")
[[ ${#RUN_SUITES[@]} -eq 0 ]] && RUN_SUITES=("${!SUITES[@]}")

declare -A SUITE_RESULTS
declare -A SUITE_EVIDENCE
declare -A SUITE_DURATION

for suite_name in "${RUN_SUITES[@]}"; do
    cmd="${SUITES[$suite_name]:-}"
    if [[ -z "$cmd" ]]; then
        echo "Unknown suite: $suite_name"
        SUITE_RESULTS["$suite_name"]="SKIP"
        SUITE_EVIDENCE["$suite_name"]="unknown suite name"
        continue
    fi

    echo; echo "=== SUITE: $suite_name ==="
    log="$RUN/${suite_name}.log"
    t0=
    t0="$(date +%s)"
    rc=0

    # Execute in project root
    (cd "$ROOT" && eval "$cmd") > "$log" 2>&1 || rc=$?

    t1=
    t1="$(date +%s)"
    SUITE_DURATION["$suite_name"]=$((t1 - t0))
    SUITE_EVIDENCE["$suite_name"]="$log"

    echo "tail of $log:"; tail -5 "$log" 2>/dev/null || echo "(empty log)"
    if [[ "$rc" -eq 0 ]]; then
        SUITE_RESULTS["$suite_name"]="PASS"
        pass "suite $suite_name: PASS (${SUITE_DURATION[$suite_name]}s)" "$log"
    else
        SUITE_RESULTS["$suite_name"]="FAIL"
        fail "suite $suite_name: FAIL (rc=$rc, ${SUITE_DURATION[$suite_name]}s)" "see $log"
    fi
done

# Write unified HelixQA verdict
python3 - "$RUN" "${!SUITE_RESULTS[@]}" <<'PYEOF'
import json, sys, os

run_dir = sys.argv[1]
suite_names = sys.argv[2:]

summary = {
    "session": os.path.basename(run_dir),
    "suites": {},
    "totals": {"PASS": 0, "FAIL": 0, "SKIP": 0}
}

for name in sorted(suite_names):
    r = os.environ.get(f"SUITE_RESULTS_{name}", "UNKNOWN")
    d = os.environ.get(f"SUITE_DURATION_{name}", "0")
    e = os.environ.get(f"SUITE_EVIDENCE_{name}", "")
    summary["suites"][name] = {"result": r, "duration_s": int(d) if d.isdigit() else 0, "evidence": e}
    summary["totals"][r] = summary["totals"].get(r, 0) + 1

with open(os.path.join(run_dir, "helixqa_verdict.json"), "w") as f:
    json.dump(summary, f, indent=2)

overall = "PASS" if summary["totals"].get("FAIL", 0) == 0 else "FAIL"
print(f"\nHELIXQA OVERALL: {overall}")
print(f"  PASS: {summary['totals'].get('PASS', 0)}")
print(f"  FAIL: {summary['totals'].get('FAIL', 0)}")
print(f"  SKIP: {summary['totals'].get('SKIP', 0)}")
PYEOF

# Compute totals and emit verdict
total_pass=0; total_fail=0; total_skip=0
for sn in "${!SUITE_RESULTS[@]}"; do
    case "${SUITE_RESULTS[$sn]}" in
        PASS) total_pass=$((total_pass + 1));;
        FAIL) total_fail=$((total_fail + 1));;
        SKIP) total_skip=$((total_skip + 1));;
    esac
done

echo; echo "=== HelixQA session complete ==="
echo "  Total suites: ${#RUN_SUITES[@]}"
echo "  PASS: $total_pass"
echo "  FAIL: $total_fail"
echo "  SKIP: $total_skip"
echo "ended: $(date -u +%FT%TZ)"

[[ "$total_fail" -eq 0 ]] && exit 0 || exit 1
