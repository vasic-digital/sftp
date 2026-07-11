#!/usr/bin/env bash
# test_constitution_inheritance.sh — Comprehensive host-side inheritance test.
# Asserts ALL constitution inheritance invariants including that the
# meta-test mutation has been run and passes.
# Constitution §1.1: every gate has a paired mutation proving it works.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PASS=0
FAIL=0

pass()  { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail()  { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "=== Constitution Inheritance Test ==="

# --- 1. constitution submodule exists
echo "[1] constitution submodule"
if [[ -d "${PROJECT_ROOT}/constitution" ]]; then
    pass "constitution/ directory exists"
else
    fail "constitution/ directory missing"
fi

# --- 2. Submodule has a tracked commit
if git -C "${PROJECT_ROOT}" submodule status constitution 2>/dev/null | grep -qE '^\s[0-9a-f]+'; then
    pass "constitution submodule tracked in parent"
else
    fail "constitution submodule not tracked"
fi

# --- 3-5. Core file anchors
for test_case in \
    "constitution/Constitution.md|§11.4 End-user quality guarantee — forensic anchor" \
    "constitution/CLAUDE.md|MANDATORY ANTI-BLUFF COVENANT" \
    "constitution/AGENTS.md|Anti-bluff covenant"; do

    file="${test_case%%|*}"
    anchor="${test_case##*|}"
    echo "[anchor] ${file} → ${anchor}"
    if [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qF "${anchor}" "${PROJECT_ROOT}/${file}"; then
        pass "${file} contains anchor"
    else
        fail "${file} missing anchor: ${anchor}"
    fi
done

# --- 6-7. Parent inheritance pointers
for test_case in \
    "CLAUDE.md|constitution/CLAUDE.md" \
    "AGENTS.md|constitution/AGENTS.md"; do

    file="${test_case%%|*}"
    ref="${test_case##*|}"
    echo "[inherit] ${file} → ${ref}"
    if [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qF "${ref}" "${PROJECT_ROOT}/${file}"; then
        pass "${file} references ${ref}"
    else
        fail "${file} does not reference ${ref}"
    fi
done

# --- 8. Upstream remotes for constitution submodule
echo "[remotes] constitution submodule remotes"
cd "${PROJECT_ROOT}/constitution"
for remote_name in github gitlab gitflic gitverse; do
    if git remote get-url "${remote_name}" &>/dev/null; then
        pass "constitution remote: ${remote_name}"
    else
        fail "constitution missing remote: ${remote_name}"
    fi
done

# --- 9. Gate script exists and is executable
echo "[gate] pre-build verification gate"
if [[ -x "${PROJECT_ROOT}/tests/pre_build_verification.sh" ]]; then
    pass "tests/pre_build_verification.sh exists and executable"
else
    fail "tests/pre_build_verification.sh missing or not executable"
fi

# --- 10. Meta-test exists and is executable
echo "[gate] meta-test mutation script"
if [[ -x "${PROJECT_ROOT}/scripts/testing/meta_test_false_positive_proof.sh" ]]; then
    pass "meta_test_false_positive_proof.sh exists and executable"
else
    fail "meta_test_false_positive_proof.sh missing or not executable"
fi

# --- 11. Gate actually passes in current state
echo "[gate] gate passes on clean state"
cd "${PROJECT_ROOT}"
if bash tests/pre_build_verification.sh > /dev/null 2>&1; then
    pass "pre_build_verification.sh passes on clean state"
else
    fail "pre_build_verification.sh fails on clean state — fixing needed"
fi

# --- 12. Meta-test passes
echo "[gate] meta-test passes"
if bash scripts/testing/meta_test_false_positive_proof.sh > /dev/null 2>&1; then
    pass "meta_test_false_positive_proof.sh passes (all mutations caught)"
else
    fail "meta_test_false_positive_proof.sh fails — mutation(s) not caught by gate"
fi

# --- Summary
echo ""
echo "=== RESULTS: ${PASS} pass, ${FAIL} fail ==="
if [[ "${FAIL}" -eq 0 ]]; then
    echo "✓ ALL CONSTITUTION INHERITANCE TESTS PASS"
    exit 0
else
    echo "✗ ${FAIL} TEST(S) FAILED — fix per Constitution §11.4.4"
    exit 1
fi
