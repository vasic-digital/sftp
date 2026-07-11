#!/usr/bin/env bash
#===============================================================================
# commit_all.sh — governed commit wrapper for the SFTP enterprise project
#===============================================================================
# Purpose:      Single sanctioned path for committing the main repo. Enforces
#               working-tree quiescence (§11.4.84), pre-commit secret/artifact
#               audit (§11.4.10/§11.4.30), and releases the lock immediately
#               after commit (§11.4.88) with a detached background push.
# Usage:        scripts/commit_all.sh "<commit message>" [--sync-push] [--no-push]
# Inputs:       $1 = commit message (required); optional flags.
# Outputs:      exit 0 committed (+push dispatched); exit 1 blocked; exit 3 nothing to commit.
# Side-effects: creates git commit; may dispatch background push_all.sh.
# Dependencies: git, bash; scripts/push_all.sh for the push step.
# Cross-refs:   constitution §11.4.84 (quiescence), §11.4.88 (background push),
#               §11.4.10/§11.4.30 (secret/artifact audit), §11.4.113 (no force-push).
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MSG="${1:-}"
SYNC_PUSH=0
DO_PUSH=1
for arg in "${@:2}"; do
  case "$arg" in
    --sync-push) SYNC_PUSH=1 ;;
    --no-push)   DO_PUSH=0 ;;
    *) echo "ERROR: unknown flag: $arg" >&2; exit 1 ;;
  esac
done

if [[ -z "$MSG" ]]; then
  echo "ERROR: commit message required: commit_all.sh \"<msg>\" [--sync-push] [--no-push]" >&2
  exit 1
fi

# --- Single-writer lock with stale-reap (§11.4.180): reap only if holder PID is dead ---
LOCK=".git/.commit_all.lock"
if [[ -f "$LOCK" ]]; then
  HOLDER="$(cat "$LOCK" 2>/dev/null || echo "")"
  if [[ -n "$HOLDER" ]] && kill -0 "$HOLDER" 2>/dev/null; then
    echo "BLOCKED: another commit_all.sh (PID $HOLDER) is running" >&2
    exit 1
  fi
  echo "REAPED stale commit lock (holder '${HOLDER:-unknown}' not alive)" >&2
  rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

# --- Quiescence check (§11.4.84): no mutation markers, no in-flight mutation gate ---
MUTATION_MARKERS='MUTATED for paired|// always pass|// MUTATION|# MUTATION|_mutated_'
if git grep -nE "$MUTATION_MARKERS" -- . ':(exclude)scripts/commit_all.sh' 2>/dev/null; then
  echo "ABORT: mutation markers present in tracked files (§11.4.84 quiescence violated)" >&2
  exit 1
fi
if [[ -f .git/MUTATION_IN_PROGRESS ]]; then
  echo "ABORT: .git/MUTATION_IN_PROGRESS present — a mutation gate is live (§11.4.84)" >&2
  exit 1
fi

# --- Nothing to commit? exit 3 (informational) ---
if git diff --quiet && git diff --cached --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
  echo "nothing-to-commit"
  exit 3
fi

# --- Secret + forbidden-artifact audit on what WOULD be staged (§11.4.10/§11.4.30) ---
SECRET_PATTERNS='BEGIN [A-Z ]*PRIVATE KEY|api[_-]?key\s*[:=]\s*["'"'"']?[A-Za-z0-9]{20,}|password\s*[:=]\s*["'"'"']?[^"'"'"'\s#]{8,}|secret\s*[:=]\s*["'"'"']?[A-Za-z0-9]{16,}'
CHANGED="$(git diff --name-only; git ls-files --others --exclude-standard)"
LEAK=0
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  case "$f" in
    # Tracked templates/examples are mandated (§11.4.77) — exempt them explicitly.
    .env.example|*/.env.example|*.env.example) ;;
    .env|.env.*|*.pem|*.key|*.crt|secrets/*|google-services.json|GoogleService-Info.plist)
      echo "ABORT: forbidden file would be tracked: $f (§11.4.10/§11.4.30)" >&2; LEAK=1 ;;
  esac
  # skip binary-ish and this script itself when content-scanning
  case "$f" in scripts/commit_all.sh) continue;; esac
  if grep -EqI "$SECRET_PATTERNS" "$f" 2>/dev/null; then
    echo "ABORT: secret-like pattern in $f — audit before commit (§11.4.10)" >&2
    grep -EnI "$SECRET_PATTERNS" "$f" | sed 's/=.*$/=<redacted>/' >&2 || true
    LEAK=1
  fi
done <<< "$CHANGED"
[[ "$LEAK" -eq 0 ]] || exit 1

# --- Stage + commit (explicit file list from git status; never blind -A of forbidden classes) ---
git add -A
git commit -m "$MSG"

echo "COMMITTED: $(git rev-parse --short HEAD)"

# --- Push policy (§11.4.88): lock released (trap), push detached unless --sync-push ---
if [[ "$DO_PUSH" -eq 1 ]]; then
  if [[ "$SYNC_PUSH" -eq 1 ]]; then
    scripts/push_all.sh
  else
    mkdir -p qa-results/push
    LOG="qa-results/push/push_$(date -u +%Y%m%dT%H%M%SZ).log"
    nohup scripts/push_all.sh > "$LOG" 2>&1 &
    disown
    echo "PUSH dispatched in background -> $LOG"
  fi
fi
