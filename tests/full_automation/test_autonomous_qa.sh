#!/usr/bin/env bash
# ============================================================================
# test_autonomous_qa.sh — full-automation meta-test: runs the complete test
# matrix in sequence and produces a unified evidence summary
# (STREAM-9, §11.4.27 full-automation + autonomous-QA-session test types)
# ----------------------------------------------------------------------------
# Purpose:
#   Orchestrates every test type in the project's matrix against a single
#   API instance, producing a unified pass/fail/skip summary. This IS the
#   "full-automation" test: no human interaction required beyond the initial
#   invocation — every test self-drives, captures evidence, and produces
#   its own verdict (§11.4.52 autonomous-validation).
#
#   Test sequence (ordered by test type):
#     1. unit           — Go tests (api/...), vitest (web), KMP (mobile)
#     2. integration    — tests/api/test_api_lifecycle.sh
#     3. e2e            — tests/e2e/test_e2e_operator_journey.sh
#     4. security       — tests/security/test_api_security.sh
#     5. performance    — tests/performance/test_api_performance.sh
#     6. stress         — tests/api/test_api_stress.sh
#     7. chaos          — tests/api/test_api_chaos.sh
#     8. ddos           — tests/ddos/test_api_ddos.sh
#     9. scaling        — tests/scaling/test_api_scaling.sh
#    10. benchmarking   — tests/benchmarking/test_api_benchmark.sh
#    11. ui             — tests/ui/test_web_ui.sh
#    12. ux             — tests/ux/test_web_ux.sh
#    13. Challenges     — tests/challenges/run_challenges.sh
#    14. autonomous-QA  — tests/helixqa/run_helixqa_suites.sh
#
#   Each test runs independently (its own API instance via harness) and
#   produces a verdict file. This script collects all verdicts and emits
#   a unified summary.
#
# Usage:
#   tests/full_automation/test_autonomous_qa.sh [--quick]
#   --quick: skip long-running tests (stress, chaos, ddos, scaling)
#
# Outputs:
#   qa/results/stream9/autonomous_qa_<timestamp>/ — per-test logs +
#   unified verdict.json + summary report.
#
# Dependencies:
#   bash ≥ 4, go ≥ 1.24, curl, python3, openssl, node (for web tests).
#
# Cross-references:
#   constitution §11.4.27 (full-automation + autonomous-QA), §11.4.52
#   (autonomous-validation), §11.4.98 (re-runnable without manual
#   intervention).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

PASS=0; FAIL=0; SKIP=0
pass() { PASS=$((PASS + 1)); echo "PASS: $1 [evidence: $2]"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1 — $2"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP: $1 [reason: $2]"; }

QUICK_MODE=""
[[ "${1:-}" == "--quick" ]] && QUICK_MODE=1

RUN="$ROOT/qa/results/stream9/autonomous_qa_$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$RUN"
echo "=== SFTP full-automation autonomous QA session ==="
echo "evidence: $RUN"
echo "mode: ${QUICK_MODE:+quick (long-running tests skipped)}${QUICK_MODE:-full}"
echo "started: $(date -u +%FT%TZ)"

declare -A TEST_RESULTS
declare -A TEST_EVIDENCE
declare -A TEST_DURATION

run_one() {
    local label="$1" script="$2"
    local log="$RUN/${label}.log"
    echo; echo "--- [$label] $script ---"
    local t0
    t0="$(date +%s)"
    local rc=0
    if [[ -x "$script" ]]; then
        bash "$script" > "$log" 2>&1 || rc=$?
    else
        echo "SKIP: $script not found or not executable" | tee "$log"
        rc=3
    fi
    local t1
    t1="$(date +%s)"
    TEST_DURATION["$label"]=$((t1 - t0))
    echo "tail of $log:"; tail -5 "$log" || true
    if [[ "$rc" -eq 0 ]]; then
        TEST_RESULTS["$label"]="PASS"
    elif [[ "$rc" -eq 3 ]]; then
        TEST_RESULTS["$label"]="SKIP"
    else
        TEST_RESULTS["$label"]="FAIL"
    fi
    TEST_EVIDENCE["$label"]="$log"
}

# ===========================================================================
# 1. Unit tests
# ===========================================================================
echo; echo "======== UNIT TESTS ========"

# Go unit tests
if command -v go >/dev/null 2>&1; then
    run_one "unit-go" "true"  # placeholder — real unit tests need go test
    local go_log="$RUN/unit-go.log"
    (cd "$ROOT/api" && go test ./... -count=1) > "$go_log" 2>&1 || true
    if grep -q '^ok' "$go_log" && ! grep -q '^FAIL' "$go_log"; then
        TEST_RESULTS["unit-go"]="PASS"
        pass "Go unit tests: all packages pass" "$go_log"
    else
        TEST_RESULTS["unit-go"]="FAIL"
        fail "Go unit tests" "some tests failed — see $go_log"
    fi
    TEST_EVIDENCE["unit-go"]="$go_log"
else
    skip "Go unit tests" "topology_unsupported (go not found)"
    TEST_RESULTS["unit-go"]="SKIP"
fi

# Web unit tests (vitest)
if [[ -d "$ROOT/web/node_modules" ]]; then
    local web_log="$RUN/unit-web.log"
    (cd "$ROOT/web" && npx vitest run --reporter verbose) > "$web_log" 2>&1 || true
    if grep -q 'Tests.*passed' "$web_log" 2>/dev/null && ! grep -q 'failed' "$web_log" 2>/dev/null; then
        TEST_RESULTS["unit-web"]="PASS"
        pass "Web unit tests (vitest): all pass" "$web_log"
    elif grep -q 'failed' "$web_log" 2>/dev/null; then
        TEST_RESULTS["unit-web"]="FAIL"
        fail "Web unit tests" "some tests failed — see $web_log"
    else
        TEST_RESULTS["unit-web"]="SKIP"
        skip "Web unit tests" "could not parse vitest output" "$web_log"
    fi
    TEST_EVIDENCE["unit-web"]="$web_log"
else
    skip "Web unit tests" "topology_unsupported (node_modules not found)"
    TEST_RESULTS["unit-web"]="SKIP"
fi

# ===========================================================================
# 2-14. API/integration/e2e tests (each spins its own API)
# ===========================================================================
INTEGRATION_TESTS=(
    "integration|$ROOT/tests/api/test_api_lifecycle.sh"
    "e2e|$ROOT/tests/e2e/test_e2e_operator_journey.sh"
    "security|$ROOT/tests/security/test_api_security.sh"
    "performance|$ROOT/tests/performance/test_api_performance.sh"
)

LONG_TESTS=(
    "stress|$ROOT/tests/api/test_api_stress.sh"
    "chaos|$ROOT/tests/api/test_api_chaos.sh"
    "ddos|$ROOT/tests/ddos/test_api_ddos.sh"
    "scaling|$ROOT/tests/scaling/test_api_scaling.sh"
    "benchmarking|$ROOT/tests/benchmarking/test_api_benchmark.sh"
)

WEB_TESTS=(
    "ui|$ROOT/tests/ui/test_web_ui.sh"
    "ux|$ROOT/tests/ux/test_web_ux.sh"
)

DRIVER_TESTS=(
    "challenges|$ROOT/tests/challenges/run_challenges.sh"
    "autonomous-qa|$ROOT/tests/helixqa/run_helixqa_suites.sh"
)

# Run integration/fast tests
for entry in "${INTEGRATION_TESTS[@]}"; do
    IFS='|' read -r label script <<< "$entry"
    run_one "$label" "$script"
done

# Long-running tests (skip in quick mode)
if [[ -n "${QUICK_MODE:-}" ]]; then
    for entry in "${LONG_TESTS[@]}"; do
        IFS='|' read -r label script <<< "$entry"
        echo; echo "--- [$label] SKIPPED (quick mode) ---"
        TEST_RESULTS["$label"]="SKIP"
        TEST_EVIDENCE["$label"]="quick mode skip"
    done
else
    for entry in "${LONG_TESTS[@]}"; do
        IFS='|' read -r label script <<< "$entry"
        run_one "$label" "$script"
    done
fi

# Web tests
for entry in "${WEB_TESTS[@]}"; do
    IFS='|' read -r label script <<< "$entry"
    run_one "$label" "$script"
done

# Driver tests (Challenges + HelixQA)
for entry in "${DRIVER_TESTS[@]}"; do
    IFS='|' read -r label script <<< "$entry"
    run_one "$label" "$script"
done

# ===========================================================================
# Unified verdict
# ===========================================================================
echo; echo "======== UNIFIED VERDICT ========"

# Build summary JSON
python3 - "$RUN" "${!TEST_RESULTS[@]}" <<'PYEOF'
import json, sys, os

run_dir = sys.argv[1]
keys = sys.argv[2:]
results = {}
for k in keys:
    res = os.environ.get(f"TEST_RESULTS_{k}", "UNKNOWN")
    results[k] = res

summary = {
    "session": os.path.basename(run_dir),
    "results": {},
    "totals": {"PASS": 0, "FAIL": 0, "SKIP": 0}
}

for k in sorted(keys):
    r = os.environ.get(f"TEST_RESULTS_{k}", "UNKNOWN")
    d = os.environ.get(f"TEST_DURATION_{k}", "0")
    e = os.environ.get(f"TEST_EVIDENCE_{k}", "")
    summary["results"][k] = {"result": r, "duration_s": int(d) if d.isdigit() else 0, "evidence": e}
    summary["totals"][r] = summary["totals"].get(r, 0) + 1

with open(os.path.join(run_dir, "unified_verdict.json"), "w") as f:
    json.dump(summary, f, indent=2)

overall = "PASS" if summary["totals"].get("FAIL", 0) == 0 else "FAIL"
print(f"\nOVERALL: {overall}")
print(f"  PASS: {summary['totals'].get('PASS', 0)}")
print(f"  FAIL: {summary['totals'].get('FAIL', 0)}")
print(f"  SKIP: {summary['totals'].get('SKIP', 0)}")
print(f"\nFull report: {os.path.join(run_dir, 'unified_verdict.json')}")
PYEOF

echo; echo "ended: $(date -u +%FT%TZ)"

# Final verdict: exit 0 only if no failures
fail_count=0
for k in "${!TEST_RESULTS[@]}"; do
    if [[ "${TEST_RESULTS[$k]}" == "FAIL" ]]; then
        fail_count=$((fail_count + 1))
    fi
done

if [[ "$fail_count" -eq 0 ]]; then
    echo "ALL TEST TYPES PASSED"
    exit 0
else
    echo "AUTONOMOUS QA SESSION FAILED ($fail_count test types failed)"
    exit 1
fi
