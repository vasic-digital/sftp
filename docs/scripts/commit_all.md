# commit_all.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T18:40:00Z

## Overview

`scripts/commit_all.sh` is the **only sanctioned commit path** for the main repo
(constitution: MANDATORY COMMIT & PUSH CONSTRAINTS). It enforces working-tree
quiescence (§11.4.84), a pre-commit secret/forbidden-artifact audit
(§11.4.10/§11.4.30), single-writer locking with provably-stale-lock reap
(§11.4.180), and detached background push (§11.4.88).

## Prerequisites

- git, bash ≥ 4
- `scripts/push_all.sh` present and executable
- Run from anywhere — the script resolves the repo root itself

## Usage examples

```bash
# Standard commit + detached background push to all 4 upstreams
scripts/commit_all.sh "ATM-001: wire foundation submodules + env matrix"

# Commit without pushing (offline / pre-review state)
scripts/commit_all.sh "ATM-010: draft guides" --no-push

# Commit + synchronous push (reserved for integration steps that must
# confirm remote state before continuing)
scripts/commit_all.sh "ATM-011: merge upstream/main integration" --sync-push
```

## Edge cases

- **Nothing to commit** → exit `3`, prints `nothing-to-commit` (informational, not an error).
- **Another commit in flight** → exit `1` with the holder PID; if the holder PID is dead the stale lock is reaped automatically and the run proceeds.
- **Mutation markers** (`MUTATED for paired`, `// always pass`, `.git/MUTATION_IN_PROGRESS`) → ABORT exit `1` (quiescence violated — a paired-mutation gate may be live).
- **Secret-like content or forbidden file class** (`.env`, `*.pem`, `*.key`, `google-services.json`, …) → ABORT exit `1` naming the file/pattern. Fix by un-staging, adding to `.gitignore`, or scrubbing.
- **Push fails on one remote** → the commit is already durable locally; `qa-results/push/<ts>.log` holds the failure; per §11.4.113 force-push is forbidden — integrate via fetch + merge and re-run `scripts/push_all.sh`.

## Internal behaviour

1. Resolve repo root; acquire `.git/.commit_all.lock` (reap-if-dead first).
2. Quiescence scan: mutation markers + in-flight mutation gate flag.
3. Empty-check → exit 3.
4. Secret/artifact audit over every changed file (content patterns + filename classes).
5. `git add -A` + `git commit -m <msg>` (forbidden classes already excluded by the audit + `.gitignore`).
6. Release lock via trap; dispatch `push_all.sh` detached (`nohup … & disown`) unless `--sync-push`/`--no-push`.

## Related scripts

- `scripts/push_all.sh` — the detached push worker (multi-upstream fan-out).
- `scripts/service_ctl.sh` *(planned, STREAM-6)* — stack lifecycle.
- Constitution: §2.1, §9.2, §11.4.10, §11.4.30, §11.4.84, §11.4.88, §11.4.113, §11.4.180.

## Last verified

2026-07-11 — syntax-checked (`bash -n`), first production use pending STREAM-1 foundation batch.
