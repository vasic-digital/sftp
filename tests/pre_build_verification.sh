#!/usr/bin/env bash
# pre_build_verification.sh — Constitution inheritance gate.
# Verifies ALL invariants before build/merge.
# Constitution §1.1: this gate MUST be paired with a meta-test mutation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FAIL_COUNT=0

pass()  { echo "  ✓ $1"; }
fail()  { echo "  ✗ $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# --- Invariant 1: constitution/ directory exists
echo "=== Invariant 1: constitution/ directory ==="
if [[ -d "${PROJECT_ROOT}/constitution" ]]; then
    pass "constitution/ exists"
else
    fail "constitution/ directory missing"
fi

# --- Invariant 2: Constitution.md with §11.4 anchor
echo "=== Invariant 2: Constitution.md §11.4 anchor ==="
CI_CONST="${PROJECT_ROOT}/constitution/Constitution.md"
if [[ -f "${CI_CONST}" ]] && grep -qF '§11.4 End-user quality guarantee — forensic anchor' "${CI_CONST}"; then
    pass "Constitution.md contains §11.4 anchor"
else
    fail "Constitution.md missing §11.4 anchor"
fi

# --- Invariant 3: CLAUDE.md with anti-bluff anchor
echo "=== Invariant 3: CLAUDE.md anti-bluff anchor ==="
CI_CLAUDE="${PROJECT_ROOT}/constitution/CLAUDE.md"
if [[ -f "${CI_CLAUDE}" ]] && grep -qF 'MANDATORY ANTI-BLUFF COVENANT' "${CI_CLAUDE}"; then
    pass "CLAUDE.md contains MANDATORY ANTI-BLUFF COVENANT"
else
    fail "CLAUDE.md missing MANDATORY ANTI-BLUFF COVENANT"
fi

# --- Invariant 4: AGENTS.md with anti-bluff anchor
echo "=== Invariant 4: AGENTS.md anti-bluff anchor ==="
CI_AGENTS="${PROJECT_ROOT}/constitution/AGENTS.md"
if [[ -f "${CI_AGENTS}" ]] && grep -qF 'Anti-bluff covenant' "${CI_AGENTS}"; then
    pass "AGENTS.md contains Anti-bluff covenant"
else
    fail "AGENTS.md missing Anti-bluff covenant"
fi

# --- Invariant 5: parent CLAUDE.md references submodule
echo "=== Invariant 5: parent CLAUDE.md references constitution ==="
if [[ -f "${PROJECT_ROOT}/CLAUDE.md" ]] && grep -qF 'constitution/CLAUDE.md' "${PROJECT_ROOT}/CLAUDE.md"; then
    pass "CLAUDE.md references constitution/CLAUDE.md"
else
    fail "CLAUDE.md does not reference constitution/CLAUDE.md"
fi

# --- Invariant 6: parent AGENTS.md references submodule
echo "=== Invariant 6: parent AGENTS.md references constitution ==="
if [[ -f "${PROJECT_ROOT}/AGENTS.md" ]] && grep -qF 'constitution/AGENTS.md' "${PROJECT_ROOT}/AGENTS.md"; then
    pass "AGENTS.md references constitution/AGENTS.md"
else
    fail "AGENTS.md does not reference constitution/AGENTS.md"
fi

# --- Summary
echo ""
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo "✓ ALL CONSTITUTION INHERITANCE INVARIANTS PASS"
    exit 0
else
    echo "✗ ${FAIL_COUNT} CONSTITUTION INHERITANCE INVARIANT(S) FAILED"
    exit 1
fi
