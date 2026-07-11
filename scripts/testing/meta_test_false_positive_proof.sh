#!/usr/bin/env bash
# meta_test_false_positive_proof.sh — Meta-test: prove the inheritance gate
# is not itself a bluff gate (Constitution §1.1).
#
# Each mutation applies a surgical break to one invariant and asserts the
# gate reports FAIL. Restores on completion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
GATE_CMD="${PROJECT_ROOT}/tests/pre_build_verification.sh"

if [[ ! -x "${GATE_CMD}" ]]; then
    echo "ERROR: gate script not found: ${GATE_CMD}" >&2
    exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0

mutation() {
    local name="$1"       # mutation name
    local target="$2"     # file to mutate (relative to PROJECT_ROOT)
    local anchor="$3"     # text to remove/replace
    local replacement="$4" # replacement text (empty = delete the line)

    echo "  MUTATION: ${name}"

    local abs_target="${PROJECT_ROOT}/${target}"
    if [[ ! -f "${abs_target}" ]]; then
        echo "    SKIP: target file missing (${target})"
        return
    fi

    if ! grep -qF "${anchor}" "${abs_target}"; then
        echo "    SKIP: anchor not found in ${target}"
        return
    fi

    # Backup
    cp -- "${abs_target}" "${abs_target}.mut.bak"

    # Apply mutation
    if [[ -z "${replacement}" ]]; then
        # Delete line containing anchor
        grep -vF "${anchor}" "${abs_target}.mut.bak" > "${abs_target}"
    else
        # Replace anchor with non-matching text
        sed -i "s|${anchor}|${replacement}|g" "${abs_target}"
    fi

    # Run gate
    set +e
    if bash "${GATE_CMD}" > /dev/null 2>&1; then
        echo "    ✗ MUTATION FAILED — gate returned 0 (should have FAILed)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "    ✓ MUTATION PASS — gate correctly FAILed"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
    set -e

    # Restore
    mv -- "${abs_target}.mut.bak" "${abs_target}"
}

echo "=== CM-CONSTITUTION-INHERITANCE mutations ==="

# Mutation 1: Strip §11.4 anchor from Constitution.md
mutation \
    "CM-CONSTITUTION-INHERITANCE: strip §11.4 anchor" \
    "constitution/Constitution.md" \
    '§11.4 End-user quality guarantee — forensic anchor' \
    ""

# Mutation 2: Strip MANDATORY ANTI-BLUFF COVENANT from CLAUDE.md
mutation \
    "CM-CONSTITUTION-INHERITANCE: strip MANDATORY ANTI-BLUFF COVENANT" \
    "constitution/CLAUDE.md" \
    'MANDATORY ANTI-BLUFF COVENANT' \
    ""

# Mutation 3: Strip Anti-bluff covenant from AGENTS.md
mutation \
    "CM-CONSTITUTION-INHERITANCE: strip Anti-bluff covenant" \
    "constitution/AGENTS.md" \
    'Anti-bluff covenant' \
    ""

# Mutation 4: Remove constitution reference from CLAUDE.md
mutation \
    "CM-CONSTITUTION-INHERITANCE: strip constitution ref from CLAUDE.md" \
    "CLAUDE.md" \
    'constitution/CLAUDE.md' \
    ""

# Mutation 5: Remove constitution reference from AGENTS.md
mutation \
    "CM-CONSTITUTION-INHERITANCE: strip constitution ref from AGENTS.md" \
    "AGENTS.md" \
    'constitution/AGENTS.md' \
    ""

echo ""
if [[ "${FAIL_COUNT}" -eq 0 ]]; then
    echo "✓ ALL ${PASS_COUNT} MUTATIONS PASSED — gate is genuine"
    exit 0
else
    echo "✗ ${FAIL_COUNT}/${PASS_COUNT} MUTATION(S) FAILED — gate or mutation needs repair"
    exit 1
fi
