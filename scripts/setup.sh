#!/usr/bin/env bash
# ============================================================================
# setup.sh — first-time setup for the SFTP Enterprise system
# ----------------------------------------------------------------------------
# Purpose:
#   Idempotent first-time (and re-runnable) setup:
#     1. Create .env from .env.example (ONLY if missing; --force to regenerate)
#     2. Generate JWT_SECRET + SUPERADMIN_PASSWORD via `openssl rand` and write
#        them into .env (chmod 600) — values are NEVER printed (§11.4.10)
#     3. Create data/ directories (host-side SFTP data root + DB location)
#     4. Print next-steps guidance
#
# Usage:
#   scripts/setup.sh [--force] [--dry-run] [--help]
#
#   --force     Regenerate .env even if it exists (the existing file is first
#               copied to .env.bak.<timestamp> — NEVER silently destroyed).
#   --dry-run   Print exactly what WOULD be done; write nothing, change nothing.
#   --help      This help.
#
# Inputs:
#   .env.example (tracked template) · openssl on PATH.
#
# Outputs:
#   .env (git-ignored, chmod 600) containing JWT_SECRET + SUPERADMIN_PASSWORD;
#   data/ + data/sftp directories (git-ignored).
#
# Side-effects:
#   Writes .env and data/ ONLY under the project root resolved from the
#   script's own location (§11.4.177). On --force the previous .env is backed
#   up, never deleted. No credentials are ever printed to stdout/stderr/logs.
#
# Dependencies:
#   bash ≥ 4, openssl, coreutils (cp, chmod, mkdir, mktemp, stat).
#
# Cross-references:
#   docs/scripts/setup.md · .env.example · scripts/sftp_ctl.sh ·
#   scripts/backup.sh · constitution §11.4.10 (credentials), §11.4.30 (.env
#   git-ignored), §11.4.18 (script docs), §12 (host safety).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_EXAMPLE="$ROOT/.env.example"
ENV_FILE="$ROOT/.env"
DATA_DIR="$ROOT/data"
SFTP_DATA_DIR="$ROOT/data/sftp"

FORCE=0
DRY_RUN=0

usage() {
    sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)    FORCE=1 ;;
        --dry-run)  DRY_RUN=1 ;;
        --help|-h)  usage; exit 0 ;;
        *)
            echo "ERROR: unknown option '$1'" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

note() { echo "(setup) $*"; }

require_openssl() {
    if ! command -v openssl >/dev/null 2>&1; then
        echo "ERROR: openssl is required to generate secrets but was not found on PATH." >&2
        return 1
    fi
}

# generate a URL/filesystem-safe random secret (never echoed by callers)
gen_secret() {
    openssl rand -base64 "$1" | tr -d '\n'
}

set_env_key() {
    # set_env_key <file> <KEY> <VALUE> — replace existing KEY= or append
    local file="$1" key="$2" value="$3"
    if grep -qE "^${key}=" "$file"; then
        # sed with | delimiter; escape sed-sensitive chars in the value
        local escaped
        escaped="$(printf '%s' "$value" | sed -e 's/[&|\\]/\\&/g')"
        sed -i "s|^${key}=.*|${key}=${escaped}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

main() {
    if [[ ! -f "$ENV_EXAMPLE" ]]; then
        echo "ERROR: template missing: $ENV_EXAMPLE" >&2
        return 1
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        note "DRY RUN — no files will be written. Planned actions:"
        if [[ -f "$ENV_FILE" && "$FORCE" -eq 0 ]]; then
            note "  .env already exists → would KEEP it (use --force to regenerate)"
        elif [[ -f "$ENV_FILE" && "$FORCE" -eq 1 ]]; then
            note "  would back up existing .env → .env.bak.<timestamp>"
            note "  would write fresh .env from $ENV_EXAMPLE"
            note "  would generate JWT_SECRET + SUPERADMIN_PASSWORD (openssl rand) into .env"
            note "  would chmod 600 .env"
        else
            note "  would create .env from $ENV_EXAMPLE"
            note "  would generate JWT_SECRET + SUPERADMIN_PASSWORD (openssl rand) into .env"
            note "  would chmod 600 .env"
        fi
        note "  would ensure directories: $DATA_DIR , $SFTP_DATA_DIR"
        note "DRY RUN complete — nothing changed."
        return 0
    fi

    require_openssl

    # --- .env -----------------------------------------------------------------
    if [[ -f "$ENV_FILE" && "$FORCE" -eq 0 ]]; then
        note ".env already exists → keeping it (re-run with --force to regenerate)."
        note "ensuring JWT_SECRET / SUPERADMIN_PASSWORD are present ..."
        changed=0
        if ! grep -qE '^JWT_SECRET=.+' "$ENV_FILE" || grep -qE '^JWT_SECRET=<set-via-setup-script>' "$ENV_FILE"; then
            set_env_key "$ENV_FILE" "JWT_SECRET" "$(gen_secret 48)"
            changed=1
            note "  JWT_SECRET generated → written to .env (value never printed, §11.4.10)"
        fi
        if ! grep -qE '^SUPERADMIN_PASSWORD=.+' "$ENV_FILE"; then
            set_env_key "$ENV_FILE" "SUPERADMIN_PASSWORD" "$(gen_secret 24)"
            changed=1
            note "  SUPERADMIN_PASSWORD generated → written to .env (value never printed, §11.4.10)"
        fi
        [[ "$changed" -eq 0 ]] && note "  both secrets already present — untouched."
        chmod 600 "$ENV_FILE"
    else
        if [[ -f "$ENV_FILE" ]]; then
            backup="$ENV_FILE.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            cp -p "$ENV_FILE" "$backup"
            chmod 600 "$backup"
            note "existing .env backed up → $backup (--force requested)"
        fi
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        set_env_key "$ENV_FILE" "JWT_SECRET" "$(gen_secret 48)"
        set_env_key "$ENV_FILE" "SUPERADMIN_PASSWORD" "$(gen_secret 24)"
        note ".env created at $ENV_FILE (chmod 600, git-ignored per §11.4.30)"
        note "  JWT_SECRET + SUPERADMIN_PASSWORD generated via openssl rand"
        note "  (values intentionally NOT printed — §11.4.10; read them from .env as the operator)"
    fi

    # --- data directories ------------------------------------------------------
    mkdir -p "$DATA_DIR" "$SFTP_DATA_DIR"
    note "data directories ensured: $DATA_DIR , $SFTP_DATA_DIR"

    # --- next steps ------------------------------------------------------------
    cat <<EOF

(setup) DONE. Next steps:
  1. Review/edit .env (ports, DB driver, Firebase flags) — it is chmod 600 + git-ignored.
  2. Prepare the atmoz user spec: cp users.conf.example users.conf  (then edit; git-ignored).
  3. Start the stack:        scripts/sftp_ctl.sh start
  4. Check stack health:     scripts/sftp_ctl.sh status
  5. (Optional) auto-start at login: scripts/sftp_ctl.sh install  (systemd --user)
  6. (Optional) Firebase web config: scripts/firebase_config.sh --check
EOF
}

main
