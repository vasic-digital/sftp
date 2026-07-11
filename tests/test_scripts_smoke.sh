#!/usr/bin/env bash
# ============================================================================
# test_scripts_smoke.sh — smoke test for the SFTP system-management scripts
# ----------------------------------------------------------------------------
# Purpose:
#   Anti-bluff smoke test (§11.4): genuinely EXERCISES setup.sh, backup.sh,
#   sftp_ctl.sh, firebase_config.sh inside a mktemp sandbox — not just parsing.
#
#   Checks:
#     1. bash -n parses every script cleanly
#     2. every script --help exits 0
#     3. setup.sh run in a sandbox copy produces .env (mode 600) containing
#        JWT_SECRET + SUPERADMIN_PASSWORD (asserted via KEY NAMES only —
#        values are never printed, §11.4.10)
#     4. setup.sh is idempotent on re-run and --dry-run writes nothing
#     5. setup.sh --force backs up the previous .env
#     6. backup.sh produces a tar.gz that `tar -tzf` lists; --list works
#     7. backup.sh --restore without --yes refuses (exit 2); with --yes
#        restores after a pre-restore safety copy
#     8. sftp_ctl.sh status exits 0 gracefully with NO containers running
#     9. firebase_config.sh --check behaves (exit 1 when config absent;
#        exit 0 on a valid fixture)
#    10. no script contains `sudo` or bare `docker ` (§11.4.161)
#
# Usage:
#   tests/test_scripts_smoke.sh
#
# Inputs:
#   The four scripts under scripts/ + .env.example + config/ from the repo.
#
# Outputs:
#   PASS/FAIL lines per check with short evidence; final verdict line.
#   Exit 0 ONLY when every check PASSes.
#
# Side-effects:
#   One mktemp -d sandbox, removed via trap on EXIT (§11.4.14). Nothing under
#   the real project root is modified. No containers are started.
#
# Dependencies:
#   bash ≥ 4, openssl, tar, gzip, grep, stat; jq or python3 optional (check 9).
#
# Cross-references:
#   scripts/setup.sh · scripts/backup.sh · scripts/sftp_ctl.sh ·
#   scripts/firebase_config.sh · constitution §11.4 (anti-bluff), §11.4.5
#   (captured evidence), §11.4.14 (cleanup), §11.4.161 (rootless-only).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL: $1 — $2"; }

check() {
    # check <description> <command...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc" "command exited non-zero: $*"
    fi
}

# newest non-pre-restore backup archive under a dir (glob-based, no ls|grep)
newest_backup() {
    find "$1" -maxdepth 1 -name '*.tar.gz' ! -name 'pre-restore-*' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-
}

SCRIPTS=(setup.sh backup.sh sftp_ctl.sh firebase_config.sh)

echo "=== SFTP scripts smoke test ==="
echo "sandbox: $SANDBOX (auto-removed on exit)"
echo

# --- 1. bash -n on every script ----------------------------------------------
for s in "${SCRIPTS[@]}"; do
    check "bash -n scripts/$s" bash -n "$ROOT/scripts/$s"
done
check "bash -n tests/test_scripts_smoke.sh" bash -n "$ROOT/tests/test_scripts_smoke.sh"

# --- 2. --help exits 0 --------------------------------------------------------
for s in "${SCRIPTS[@]}"; do
    check "scripts/$s --help exits 0" bash "$ROOT/scripts/$s" --help
done

# --- 3+4+5. setup.sh in a sandbox copy -----------------------------------------
# Build a sandboxed mini-project with copies of the scripts (§11.4.177: scripts
# resolve ROOT from their own location, so copies act on the sandbox).
mkdir -p "$SANDBOX/proj/scripts" "$SANDBOX/proj/config" "$SANDBOX/proj/deploy" "$SANDBOX/proj/web/src"
cp "$ROOT/scripts/setup.sh" "$ROOT/scripts/backup.sh" "$ROOT/scripts/sftp_ctl.sh" "$ROOT/scripts/firebase_config.sh" "$SANDBOX/proj/scripts/"
cp "$ROOT/.env.example" "$SANDBOX/proj/.env.example"
cp "$ROOT/deploy/docker-compose.yml" "$SANDBOX/proj/deploy/"
cp -r "$ROOT/config/." "$SANDBOX/proj/config/" 2>/dev/null || true
printf 'user1:x:1001:1001:upload\n' > "$SANDBOX/proj/users.conf"
SB="$SANDBOX/proj"

if bash "$SB/scripts/setup.sh" > "$SANDBOX/setup1.out" 2>&1; then
    pass "setup.sh first run exits 0"
else
    fail "setup.sh first run" "exit non-zero"
fi

if [[ -f "$SB/.env" ]]; then
    pass "setup.sh created .env"
else
    fail "setup.sh created .env" ".env missing in sandbox"
fi

if [[ "$(stat -c%a "$SB/.env" 2>/dev/null)" == "600" ]]; then
    pass ".env permissions are 600"
else
    fail ".env permissions are 600" "got $(stat -c%a "$SB/.env" 2>/dev/null || echo missing)"
fi

# Key NAMES only — values never printed (§11.4.10)
if grep -qE '^JWT_SECRET=.+' "$SB/.env"; then
    pass ".env contains JWT_SECRET (key-name check only)"
else
    fail ".env contains JWT_SECRET" "key absent or empty"
fi
if grep -qE '^SUPERADMIN_PASSWORD=.+' "$SB/.env"; then
    pass ".env contains SUPERADMIN_PASSWORD (key-name check only)"
else
    fail ".env contains SUPERADMIN_PASSWORD" "key absent or empty"
fi

# Values must be non-placeholder and differ from each other (compared silently)
jwt_val="$(grep -E '^JWT_SECRET=' "$SB/.env" | cut -d= -f2-)"
sa_val="$(grep -E '^SUPERADMIN_PASSWORD=' "$SB/.env" | cut -d= -f2-)"
if [[ -n "$jwt_val" && "$jwt_val" != "<set-via-setup-script>" && -n "$sa_val" && "$jwt_val" != "$sa_val" ]]; then
    pass "generated secrets are non-placeholder and distinct"
else
    fail "generated secrets are non-placeholder and distinct" "placeholder or duplicate detected"
fi

# setup output must NOT leak the secret values (§11.4.10)
if [[ -n "$jwt_val" ]] && grep -qF "$jwt_val" "$SANDBOX/setup1.out"; then
    fail "setup.sh does not print JWT_SECRET value" "value leaked into stdout"
elif [[ -n "$sa_val" ]] && grep -qF "$sa_val" "$SANDBOX/setup1.out"; then
    fail "setup.sh does not print SUPERADMIN_PASSWORD value" "value leaked into stdout"
else
    pass "setup.sh never prints secret values (§11.4.10)"
fi

if [[ -d "$SB/data" ]]; then
    pass "setup.sh created data/ dir"
else
    fail "setup.sh created data/ dir" "missing"
fi

# idempotent re-run keeps the same secret
if bash "$SB/scripts/setup.sh" >/dev/null 2>&1; then
    jwt_val2="$(grep -E '^JWT_SECRET=' "$SB/.env" | cut -d= -f2-)"
    if [[ "$jwt_val" == "$jwt_val2" ]]; then
        pass "setup.sh idempotent re-run keeps secrets"
    else
        fail "setup.sh idempotent re-run keeps secrets" "secret changed without --force"
    fi
else
    fail "setup.sh re-run exits 0" "exit non-zero"
fi

# --dry-run writes nothing: snapshot .env hash, dry-run, compare
hash_before="$(sha256sum "$SB/.env" | cut -d' ' -f1)"
if bash "$SB/scripts/setup.sh" --dry-run > "$SANDBOX/dryrun.out" 2>&1; then
    hash_after="$(sha256sum "$SB/.env" | cut -d' ' -f1)"
    if [[ "$hash_before" == "$hash_after" ]]; then
        pass "--dry-run wrote nothing"
    else
        fail "--dry-run wrote nothing" ".env changed"
    fi
else
    fail "setup.sh --dry-run exits 0" "exit non-zero"
fi
if grep -qi "dry run" "$SANDBOX/dryrun.out"; then
    pass "--dry-run announces itself"
else
    fail "--dry-run announces itself" "no dry-run notice in output"
fi

# --force regenerates + backs up
if bash "$SB/scripts/setup.sh" --force >/dev/null 2>&1; then
    if compgen -G "$SB/.env.bak.*" > /dev/null; then
        pass "--force created .env backup"
    else
        fail "--force created .env backup" "no .env.bak.* found"
    fi
    jwt_val3="$(grep -E '^JWT_SECRET=' "$SB/.env" | cut -d= -f2-)"
    if [[ "$jwt_val3" != "$jwt_val" ]]; then
        pass "--force regenerated JWT_SECRET"
    else
        fail "--force regenerated JWT_SECRET" "unchanged"
    fi
else
    fail "setup.sh --force exits 0" "exit non-zero"
fi

# --- 6. backup.sh create + list ------------------------------------------------
if bash "$SB/scripts/backup.sh" > "$SANDBOX/backup1.out" 2>&1; then
    pass "backup.sh create exits 0"
else
    fail "backup.sh create" "exit non-zero"
fi
archive="$(newest_backup "$SB/backups")"
if [[ -n "$archive" ]]; then
    pass "backup archive created"
    # Materialise the listing ONCE to a file, then grep the file. Piping
    # `tar -tzf | grep -q` directly is a SIGPIPE race under pipefail (grep -q
    # exits on first match while tar keeps writing → tar dies with 141) —
    # the file-based check is deterministic (§11.4.50).
    if tar -tzf "$archive" > "$SANDBOX/listing1.txt" 2>/dev/null; then
        pass "archive lists cleanly via tar -tzf"
    else
        fail "archive lists cleanly via tar -tzf" "tar -tzf failed"
    fi
    if grep -q 'users.conf' "$SANDBOX/listing1.txt"; then
        pass "archive contains users.conf"
    else
        fail "archive contains users.conf" "not listed"
    fi
    if grep -q '^config/' "$SANDBOX/listing1.txt"; then
        pass "archive contains config/"
    else
        fail "archive contains config/" "not listed"
    fi
else
    fail "backup archive created" "none under sandbox backups/"
fi
# SQLite DB member coverage: create a dummy DB and re-backup
printf 'dummy' > "$SB/data/sftp.db"
bash "$SB/scripts/backup.sh" >/dev/null 2>&1
archive2="$(newest_backup "$SB/backups")"
if [[ -n "$archive2" ]] && tar -tzf "$archive2" > "$SANDBOX/listing2.txt" 2>/dev/null && grep -q 'data/sftp.db' "$SANDBOX/listing2.txt"; then
    pass "archive includes data/*.db when present"
else
    fail "archive includes data/*.db when present" "db not listed"
fi
if bash "$SB/scripts/backup.sh" --list > "$SANDBOX/backuplist.out" 2>&1 && grep -q '.tar.gz' "$SANDBOX/backuplist.out"; then
    pass "backup.sh --list shows archives"
else
    fail "backup.sh --list shows archives" "empty or errored"
fi

# --- 7. restore gate ------------------------------------------------------------
# Corrupt a member, then restore with and without --yes
echo "CORRUPTED" > "$SB/users.conf"
if bash "$SB/scripts/backup.sh" --restore "$archive2" > "$SANDBOX/restore_no_yes.out" 2>&1; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 2 ]] && grep -q 'CORRUPTED' "$SB/users.conf"; then
    pass "restore without --yes refused (exit 2, nothing changed)"
else
    fail "restore without --yes refused" "rc=$rc or file changed"
fi
if bash "$SB/scripts/backup.sh" --restore "$archive2" --yes > "$SANDBOX/restore_yes.out" 2>&1; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 0 ]] && grep -q 'user1' "$SB/users.conf"; then
    pass "restore --yes restored users.conf"
else
    fail "restore --yes restored users.conf" "rc=$rc or content missing"
fi
if compgen -G "$SB/backups/pre-restore-*.tar.gz" > /dev/null; then
    pass "restore made pre-restore safety copy"
else
    fail "restore made pre-restore safety copy" "none found"
fi
if grep -q 'PREVIEW' "$SANDBOX/restore_yes.out"; then
    pass "restore printed preview of members"
else
    fail "restore printed preview of members" "no PREVIEW line"
fi

# --- 8. sftp_ctl.sh status with no containers -----------------------------------
# Run from the sandbox project (compose file present, nothing running).
if bash "$SB/scripts/sftp_ctl.sh" status > "$SANDBOX/status.out" 2>&1; then
    pass "sftp_ctl.sh status exits 0 with no stack running"
else
    fail "sftp_ctl.sh status exits 0 with no stack running" "exit non-zero"
fi
if grep -q 'SFTP_PORT' "$SANDBOX/status.out"; then
    pass "status reports SFTP_PORT listener"
else
    fail "status reports SFTP_PORT listener" "absent"
fi
if grep -q 'API_PORT' "$SANDBOX/status.out"; then
    pass "status reports API_PORT listener"
else
    fail "status reports API_PORT listener" "absent"
fi
# .env port override honoured (7721 → custom)
printf 'SFTP_PORT=9999\nAPI_PORT=9998\n' >> "$SB/.env"
bash "$SB/scripts/sftp_ctl.sh" status > "$SANDBOX/status2.out" 2>&1 || true
if grep -q 'SFTP_PORT=9999' "$SANDBOX/status2.out"; then
    pass "status honours .env SFTP_PORT override"
else
    fail "status honours .env SFTP_PORT override" "still default"
fi
if grep -q 'API_PORT=9998' "$SANDBOX/status2.out"; then
    pass "status honours .env API_PORT override"
else
    fail "status honours .env API_PORT override" "still default"
fi
if bash "$SB/scripts/sftp_ctl.sh" boguscmd >/dev/null 2>&1; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 2 ]]; then
    pass "sftp_ctl.sh unknown command → exit 2"
else
    fail "sftp_ctl.sh unknown command → exit 2" "rc=$rc"
fi

# --- 9. firebase_config.sh --check ----------------------------------------------
if bash "$SB/scripts/firebase_config.sh" --check >/dev/null 2>&1; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 1 ]]; then
    pass "firebase_config.sh --check → exit 1 when config absent"
else
    fail "firebase_config.sh --check → exit 1 when config absent" "rc=$rc"
fi
printf '{"apiKey":"fixture","projectId":"fixture"}\n' > "$SB/web/src/firebase-config.json"
if bash "$SB/scripts/firebase_config.sh" --check >/dev/null 2>&1; then
    rc=0
else
    rc=$?
fi
if command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
    if [[ "$rc" -eq 0 ]]; then
        pass "firebase_config.sh --check → exit 0 on valid JSON fixture"
    else
        fail "firebase_config.sh --check → exit 0 on valid JSON fixture" "rc=$rc"
    fi
else
    if [[ "$rc" -eq 3 ]]; then
        pass "firebase_config.sh --check → exit 3 (no validator available)"
    else
        fail "firebase_config.sh --check → exit 3 (no validator)" "rc=$rc"
    fi
fi
# fetch without ids → exit 2 (no project/app anywhere)
mv "$SB/.env" "$SB/.env.hidden"
if bash "$SB/scripts/firebase_config.sh" >/dev/null 2>&1; then
    rc=0
else
    rc=$?
fi
if [[ "$rc" -eq 2 ]]; then
    pass "firebase_config.sh fetch without ids → exit 2 with guidance"
else
    fail "firebase_config.sh fetch without ids → exit 2" "rc=$rc"
fi
mv "$SB/.env.hidden" "$SB/.env"

# --- 10. forbidden commands scan (§11.4.161) --------------------------------------
# Scan CODE lines only — comments stripped first, so a doc block that NAMES
# the prohibition ("never touches sudo/rootful docker") is not a false hit.
forbidden=0
for s in "${SCRIPTS[@]}"; do
    code_only="$(grep -vE '^[[:space:]]*#' "$ROOT/scripts/$s")"
    if printf '%s\n' "$code_only" | grep -qE '\bsudo\b'; then
        fail "scripts/$s contains no sudo" "sudo found in code"
        forbidden=1
    fi
    if printf '%s\n' "$code_only" | grep -qE '(^|[^a-zA-Z_./-])docker( |$)'; then
        fail "scripts/$s contains no rootful docker invocation" "docker found in code"
        forbidden=1
    fi
done
if [[ "$forbidden" -eq 0 ]]; then
    pass "no script contains sudo or rootful docker (§11.4.161)"
fi
# host-power scan (§12)
if grep -nE 'systemctl (suspend|hibernate|poweroff|reboot)|loginctl (terminate|lock-session)|rfkill' "$ROOT"/scripts/*.sh >/dev/null 2>&1; then
    fail "no host-power/session commands (§12)" "found"
else
    pass "no host-power/session commands (§12)"
fi

echo
echo "=== verdict: PASS=$PASS FAIL=$FAIL ==="
if [[ "$FAIL" -eq 0 ]]; then
    echo "ALL CHECKS PASSED"
    exit 0
else
    echo "SMOKE TEST FAILED"
    exit 1
fi
