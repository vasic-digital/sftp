#!/usr/bin/env bash
# ============================================================================
# backup.sh — backup / restore for the SFTP Enterprise system
# ----------------------------------------------------------------------------
# Purpose:
#   Create integrity-verified tar.gz backups of the operator-facing state:
#     config/ (YAML/JSON schemas + examples), the SQLite DB under data/,
#     and users.conf (the rendered atmoz user spec).
#   Restore is destructive-class: it requires --yes, prints a preview of what
#   will be overwritten, and takes a pre-restore safety copy first.
#
# Usage:
#   scripts/backup.sh                      → create backups/<timestamp>.tar.gz
#   scripts/backup.sh --list               → list existing backups
#   scripts/backup.sh --restore <file> --yes
#                                          → restore (preview + safety copy)
#   scripts/backup.sh --help
#
# Inputs:
#   config/ · data/*.db (SQLite) · users.conf (any missing member is skipped
#   with a notice — backups of a partially-initialised system stay possible).
#
# Outputs:
#   backups/<UTC-timestamp>.tar.gz  (mode 600 — may embed .env-adjacent paths)
#   On --restore: pre-restore safety archive backups/pre-restore-<ts>.tar.gz
#
# Side-effects:
#   Creates files under backups/ only. --restore overwrites config/, data/*.db,
#   users.conf AFTER a verified safety copy. NEVER prints file *contents*
#   (users.conf may carry credentials — §11.4.10).
#
# Dependencies:
#   bash ≥ 4, tar, gzip, date, stat.
#
# Cross-references:
#   docs/scripts/backup.md · scripts/setup.sh · scripts/sftp_ctl.sh ·
#   constitution §11.4.10 (credentials), §11.4.30 (backups/ git-ignored),
#   §9 (data safety — preview + safety copy before any destructive step).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT/backups"

note() { echo "(backup) $*"; }

usage() {
    sed -n '2,34p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Collect existing backup members (relative paths). Echoes one per line.
collect_members() {
    local members=()
    [[ -d "$ROOT/config" ]] && members+=("config")
    if [[ -d "$ROOT/data" ]]; then
        while IFS= read -r db; do
            members+=("data/$(basename "$db")")
        done < <(find "$ROOT/data" -maxdepth 1 -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) | sort)
    fi
    [[ -f "$ROOT/users.conf" ]] && members+=("users.conf")
    printf '%s\n' "${members[@]}"
}

create_backup() {
    mkdir -p "$BACKUP_DIR"
    local ts out members
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    out="$BACKUP_DIR/$ts.tar.gz"

    members="$(collect_members || true)"
    if [[ -z "${members//[[:space:]]/}" ]]; then
        note "nothing to back up yet (no config/, no data/*.db, no users.conf)."
        note "run scripts/setup.sh first; skipping archive creation."
        return 0
    fi

    note "members included in this backup (paths only, never contents):"
    while IFS= read -r m; do note "  - $m"; done <<< "$members"

    # shellcheck disable=SC2086 # intentional word-split of newline list handled below
    (cd "$ROOT" && tar -czf "$out" $members)
    chmod 600 "$out"

    # Integrity gate: the archive must list AND test cleanly before success.
    if tar -tzf "$out" >/dev/null 2>&1 && gzip -t "$out" 2>/dev/null; then
        local size
        size="$(stat -c%s "$out")"
        note "backup OK: $out (${size} bytes, integrity verified: tar -tzf + gzip -t)"
    else
        rm -f "$out"
        echo "ERROR: archive integrity check FAILED — partial file removed." >&2
        return 1
    fi
}

list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]] || ! find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' | grep -q .; then
        note "no backups found under $BACKUP_DIR"
        return 0
    fi
    note "backups under $BACKUP_DIR:"
    find "$BACKUP_DIR" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %s %f\n' 2>/dev/null \
        | sort -rn \
        | while read -r _ size name; do
            printf '  %10s bytes  %s\n' "$size" "$name"
        done
}

restore_backup() {
    local archive="$1" yes="$2"
    if [[ ! -f "$archive" ]]; then
        # Allow a bare filename resolved under backups/
        if [[ -f "$BACKUP_DIR/$archive" ]]; then
            archive="$BACKUP_DIR/$archive"
        else
            echo "ERROR: backup not found: $1" >&2
            return 1
        fi
    fi
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        echo "ERROR: archive is not a readable tar.gz: $archive" >&2
        return 1
    fi
    if [[ "$yes" != "1" ]]; then
        echo "ERROR: restore is destructive-class and requires --yes." >&2
        echo "Re-run: scripts/backup.sh --restore '$archive' --yes" >&2
        return 2
    fi

    note "PREVIEW — members that will be extracted/overwritten (paths only):"
    tar -tzf "$archive" | sed 's/^/  - /'

    mkdir -p "$BACKUP_DIR"
    local safety
    safety="$BACKUP_DIR/pre-restore-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
    local members
    members="$(collect_members || true)"
    if [[ -n "${members//[[:space:]]/}" ]]; then
        # shellcheck disable=SC2086
        (cd "$ROOT" && tar -czf "$safety" $members)
        chmod 600 "$safety"
        if ! tar -tzf "$safety" >/dev/null 2>&1; then
            echo "ERROR: pre-restore safety copy failed integrity check — ABORTING restore." >&2
            rm -f "$safety"
            return 1
        fi
        note "pre-restore safety copy → $safety"
    else
        note "no current state to preserve (safety copy skipped)."
    fi

    (cd "$ROOT" && tar -xzf "$archive")
    note "restore complete from: $archive"
    note "verify with: scripts/sftp_ctl.sh status"
}

main() {
    local action="create" target="" yes=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list)     action="list" ;;
            --restore)  action="restore"; shift; target="${1:-}" ;;
            --yes)      yes=1 ;;
            --help|-h)  usage; exit 0 ;;
            *)
                echo "ERROR: unknown option '$1'" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done

    case "$action" in
        create)  create_backup ;;
        list)    list_backups ;;
        restore)
            if [[ -z "$target" ]]; then
                echo "ERROR: --restore requires a file argument." >&2
                exit 2
            fi
            restore_backup "$target" "$yes"
            ;;
    esac
}

main "$@"
