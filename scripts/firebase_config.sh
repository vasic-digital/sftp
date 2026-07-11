#!/usr/bin/env bash
# ============================================================================
# firebase_config.sh — dynamic Firebase web-app config acquisition
# ----------------------------------------------------------------------------
# Purpose:
#   Fetch the Firebase WEB app SDK config for this project via the `firebase`
#   CLI and write it to web/src/firebase-config.json (git-ignored, §11.4.30).
#   Project/app ids come from .env (FIREBASE_PROJECT_ID / FIREBASE_WEB_APP_ID)
#   or --project/--app overrides. The fetched config is NEVER printed to
#   stdout — only the destination file path (§11.4.10).
#
# Usage:
#   scripts/firebase_config.sh [--project <id>] [--app <id>] [--check] [--help]
#
#   --check       Report whether web/src/firebase-config.json exists and is
#                 valid JSON (jq if available, else python3). Exit 0 if valid,
#                 1 if missing/invalid, 3 if no JSON validator is available.
#   --project ID  Override FIREBASE_PROJECT_ID from .env.
#   --app ID      Override FIREBASE_WEB_APP_ID from .env.
#   --help        This help.
#
# Inputs:
#   .env (optional) — FIREBASE_PROJECT_ID, FIREBASE_WEB_APP_ID.
#   `firebase` CLI on PATH + an active `firebase login` session.
#
# Outputs:
#   web/src/firebase-config.json (git-ignored; contains the public-ish web SDK
#   config — still treated as sensitive: never echoed, never logged).
#
# Side-effects:
#   Writes one file under web/src/. No other mutation. Exit 2 when the
#   firebase CLI is missing (with the exact install command printed).
#
# Dependencies:
#   bash ≥ 4, firebase CLI (for fetch), jq OR python3 (for --check validation).
#
# Cross-references:
#   docs/scripts/firebase_config.md · .env.example · scripts/setup.sh ·
#   constitution §11.4.10 (credentials), §11.4.18 (script docs), §11.4.30
#   (firebase-config*.json git-ignored).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/web/src"
OUT_FILE="$OUT_DIR/firebase-config.json"

note() { echo "(firebase_config) $*"; }

usage() {
    sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

env_get() {
    local key="$1" line value
    if [[ -f "$ROOT/.env" ]]; then
        line="$(grep -E "^${key}=" "$ROOT/.env" | tail -n 1 || true)"
        if [[ -n "$line" ]]; then
            value="${line#*=}"
            value="${value%%#*}"
            value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
            [[ -n "$value" ]] && { printf '%s' "$value"; return 0; }
        fi
    fi
    return 1
}

check_existing() {
    if [[ ! -f "$OUT_FILE" ]]; then
        note "config NOT present: $OUT_FILE"
        return 1
    fi
    if command -v jq >/dev/null 2>&1; then
        if jq -e . "$OUT_FILE" >/dev/null 2>&1; then
            note "config present and VALID JSON: $OUT_FILE"
            return 0
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$OUT_FILE" 2>/dev/null; then
            note "config present and VALID JSON: $OUT_FILE"
            return 0
        fi
    else
        note "config present but no JSON validator (jq/python3) available: $OUT_FILE"
        return 3
    fi
    note "config present but INVALID JSON: $OUT_FILE — re-run fetch to regenerate."
    return 1
}

fetch_config() {
    local project="$1" app="$2"
    if [[ -z "$project" || -z "$app" ]]; then
        echo "ERROR: Firebase project id and web app id are required." >&2
        echo "Set FIREBASE_PROJECT_ID + FIREBASE_WEB_APP_ID in .env, or pass" >&2
        echo "--project <id> --app <id>. (App ids: firebase apps:list)" >&2
        return 2
    fi
    if ! command -v firebase >/dev/null 2>&1; then
        echo "ERROR: 'firebase' CLI not found on PATH." >&2
        echo "Install with:" >&2
        echo "    npm install -g firebase-tools" >&2
        echo "then authenticate:" >&2
        echo "    firebase login" >&2
        return 2
    fi

    mkdir -p "$OUT_DIR"
    local tmp
    tmp="$(mktemp)"
    # SDK config is written to a temp file first — NEVER to stdout.
    if ! firebase apps:sdkconfig WEB "$app" --project "$project" --json -o "$tmp" >/dev/null 2>&1; then
        # Fallback for older firebase-tools without -o: capture stdout into the file.
        if ! firebase apps:sdkconfig WEB "$app" --project "$project" --json > "$tmp" 2>/dev/null; then
            rm -f "$tmp"
            echo "ERROR: firebase apps:sdkconfig failed. Check: firebase login status," >&2
            echo "project id '$project', and web app id '$app' (firebase apps:list)." >&2
            return 1
        fi
    fi

    # Validate before declaring success (jq → python3 → raw accept with warning)
    if command -v jq >/dev/null 2>&1; then
        if ! jq -e . "$tmp" >/dev/null 2>&1; then
            rm -f "$tmp"
            echo "ERROR: fetched payload is not valid JSON — refusing to write." >&2
            return 1
        fi
        jq . "$tmp" > "$OUT_FILE"
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 -c "import json,sys; json.dump(json.load(open(sys.argv[1])), open(sys.argv[2],'w'), indent=2)" "$tmp" "$OUT_FILE" 2>/dev/null; then
            rm -f "$tmp"
            echo "ERROR: fetched payload is not valid JSON — refusing to write." >&2
            return 1
        fi
    else
        cp "$tmp" "$OUT_FILE"
        note "WARNING: no jq/python3 to validate JSON — wrote payload unvalidated."
    fi
    rm -f "$tmp"
    chmod 600 "$OUT_FILE"
    note "Firebase web SDK config written → $OUT_FILE"
    note "(config contents intentionally NOT printed — §11.4.10; file is git-ignored)"
}

main() {
    local project="" app="" mode="fetch"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)    mode="check" ;;
            --project)  shift; project="${1:-}" ;;
            --app)      shift; app="${1:-}" ;;
            --help|-h)  usage; exit 0 ;;
            *)
                echo "ERROR: unknown option '$1'" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done

    if [[ "$mode" == "check" ]]; then
        check_existing
        exit $?
    fi

    [[ -z "$project" ]] && project="$(env_get FIREBASE_PROJECT_ID || true)"
    [[ -z "$app" ]] && app="$(env_get FIREBASE_WEB_APP_ID || true)"
    fetch_config "$project" "$app"
}

main "$@"
