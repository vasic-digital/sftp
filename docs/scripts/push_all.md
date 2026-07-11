# push_all.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T18:40:00Z

## Overview

`scripts/push_all.sh` pushes the current branch + tags to **every configured
upstream** (github, gitlab, gitflic, gitverse) per the §2.1 multi-upstream norm.
Per-remote flocking lets parallel invocations serialize per remote only
(§11.4.88(C)). Force-push is absolutely forbidden (§11.4.113).

## Prerequisites

- git, bash ≥ 4; the four remotes configured (`git remote -v` — installed via `install_upstreams` from `upstreams/`).

## Usage examples

```bash
scripts/push_all.sh          # push current branch + tags to all upstreams
```

Usually invoked indirectly by `commit_all.sh` (detached) or after a manual
merge-onto-latest-main integration.

## Edge cases

- **Remote not configured** → skipped with a notice, not an error.
- **Push already in flight for a remote** → skipped (other remotes still pushed); dead-holder locks are reaped (§11.4.180).
- **Non-fast-forward rejection** → exit `1` with the remediation recipe:
  `git fetch --all --prune --tags; git merge <remote>/<branch>; resolve (union, no loss); re-run`. NEVER `--force` (§11.4.113).
- **Partial failure** → remotes that succeeded stay pushed; exit code is `1`; re-running is idempotent (already-current remotes report up-to-date).

## Internal behaviour

1. Determine current branch.
2. For each of github/gitlab/gitflic/gitverse: acquire `.git/.push.<remote>.lock` (reap-if-dead), `git push <remote> <branch> --tags`, record OK/FAIL, release lock.
3. Exit `0` only if every configured remote succeeded.

## Related scripts

- `scripts/commit_all.sh` — the governed commit entry point that dispatches this script.
- Constitution: §2.1, §11.4.88, §11.4.113, §11.4.180.

## Last verified

2026-07-11 — syntax-checked (`bash -n`); first production push pending STREAM-1 foundation batch.
