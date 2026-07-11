#!/usr/bin/env bash
#===============================================================================
# push_all.sh — multi-upstream push for the SFTP enterprise project
#===============================================================================
# Purpose:      Push current branch + tags to EVERY configured upstream remote
#               (§2.1 multi-upstream norm). Per-remote flock so parallel
#               invocations serialize per remote only (§11.4.88(C)).
#               Force-push is ABSOLUTELY FORBIDDEN (§11.4.113): if a remote
#               rejects non-fast-forward, we STOP and instruct merge-onto-latest
#               -main integration — never force.
# Usage:        scripts/push_all.sh
# Inputs:       none (operates on current branch of cwd repo).
# Outputs:      exit 0 all remotes pushed/already-current; exit 1 a remote failed.
# Side-effects: network pushes; per-remote lock files under .git/.
# Dependencies: git, bash.
# Cross-refs:   §2.1, §11.4.88, §11.4.113, §11.4.180 (stale-lock reap).
#===============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
FAILED=0

for REMOTE in github gitlab gitflic gitverse; do
  git remote get-url "$REMOTE" >/dev/null 2>&1 || { echo "skip: remote $REMOTE not configured"; continue; }
  LOCK=".git/.push.${REMOTE}.lock"
  if [[ -f "$LOCK" ]]; then
    HOLDER="$(cat "$LOCK" 2>/dev/null || echo "")"
    if [[ -n "$HOLDER" ]] && kill -0 "$HOLDER" 2>/dev/null; then
      echo "skip: $REMOTE push in progress (PID $HOLDER)"
      continue
    fi
    echo "REAPED stale push lock for $REMOTE (holder '${HOLDER:-unknown}' not alive)" >&2
    rm -f "$LOCK"
  fi
  echo $$ > "$LOCK"
  echo "==> pushing $BRANCH to $REMOTE ..."
  if git push "$REMOTE" "$BRANCH" --tags 2>&1; then
    echo "OK  $REMOTE"
  else
    rc=$?
    echo "FAIL $REMOTE (exit $rc)" >&2
    echo "     If this was a non-fast-forward rejection: per §11.4.113 force-push is" >&2
    echo "     FORBIDDEN. Run: git fetch --all --prune --tags; git merge $REMOTE/$BRANCH;" >&2
    echo "     resolve conflicts (union, no commit loss); then re-run push_all.sh." >&2
    FAILED=1
  fi
  rm -f "$LOCK"
done

exit "$FAILED"
