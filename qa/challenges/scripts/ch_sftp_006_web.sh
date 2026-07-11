#!/usr/bin/env bash
# ============================================================================
# CH-SFTP-006 — Web SPA loads all screens without runtime errors
# ----------------------------------------------------------------------------
# Challenge: The React/TypeScript admin SPA MUST render all screens in both
# light and dark themes WITHOUT console errors. Validated via Playwright
# headless Chromium host-rendered pixel proof per §11.4.170.
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WEB_DIR="$ROOT/web"
SCRIPTS_DIR="$WEB_DIR/scripts"
SCREENSHOTS_SCRIPT="$SCRIPTS_DIR/screenshots.mjs"

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "  PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "  FAIL: $1"; }

echo "[CH-SFTP-006] Web SPA visual-proof challenge"

# --- Prerequisites ---
if [[ ! -f "$SCREENSHOTS_SCRIPT" ]]; then
    fail "screenshots.mjs not found at $SCREENSHOTS_SCRIPT"
    exit 1
fi

# Check Node.js.
if ! command -v node &>/dev/null; then
    fail "Node.js not found on PATH"
    exit 1
fi
pass "Node.js available: $(node --version)"

# Check npm/node_modules.
if [[ ! -d "$WEB_DIR/node_modules" ]]; then
    echo "[CH-SFTP-006] Installing web dependencies ..."
    cd "$WEB_DIR"
    npm install --silent || {
        fail "npm install failed"
        exit 1
    }
fi
pass "web/node_modules present"

# Check if vite build output exists.
if [[ ! -d "$WEB_DIR/dist" ]]; then
    echo "[CH-SFTP-006] Building web app (vite build) ..."
    cd "$WEB_DIR"
    npx vite build --logLevel silent || {
        fail "vite build failed"
        exit 1
    }
fi
pass "web/dist build output present"

# Check Playwright.
if ! node -e "require('playwright')" 2>/dev/null; then
    echo "[CH-SFTP-006] Installing playwright ..."
    cd "$WEB_DIR"
    npm install --silent playwright || {
        fail "playwright install failed"
        exit 1
    }
fi
pass "playwright module available"

# Check Playwright browsers.
if ! npx playwright install chromium --with-deps 2>/dev/null; then
    echo "[CH-SFTP-006] WARNING: playwright browser install had issues, trying anyway"
fi

# --- Create output directory ---
OUT_DIR="$ROOT/qa/results/stream4/screenshots"
mkdir -p "$OUT_DIR"

# --- Run screenshots harness ---
echo "[CH-SFTP-006] Running screenshot harness ..."
cd "$WEB_DIR"
if node "$SCREENSHOTS_SCRIPT" 2>&1; then
    pass "Playwright screenshot harness completed without errors"
else
    EXIT_CODE=$?
    fail "screenshot harness failed with exit code ${EXIT_CODE}"
fi

# --- Verify output files ---
SCREENSHOT_COUNT=$(find "$OUT_DIR" -name '*.png' 2>/dev/null | wc -l)
if [[ $SCREENSHOT_COUNT -ge 5 ]]; then
    pass "generated ${SCREENSHOT_COUNT} screenshot files (>= 5 expected)"
else
    fail "only ${SCREENSHOT_COUNT} screenshots generated (expected >= 5)"
fi

# --- Report ---
echo ""
echo "CH-SFTP-006: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL"
if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0
