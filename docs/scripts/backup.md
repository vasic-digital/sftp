# backup.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T19:05:00Z

## Overview

`scripts/backup.sh` creates integrity-verified `tar.gz` backups of the
operator-facing state — `config/`, every SQLite database under `data/`, and
`users.conf` — into `backups/<UTC-timestamp>.tar.gz` (mode 600; `backups/` is
git-ignored per §11.4.30). It also lists backups and restores them. Restore is
a destructive-class operation: it requires an explicit `--yes`, prints a
preview of every member it will overwrite, and takes a verified pre-restore
safety copy first (§9 data safety). File **contents** are never printed —
`users.conf` may carry credentials (§11.4.10).

## Prerequisites

- bash ≥ 4, `tar`, `gzip`, `date`, `stat`
- Something to back up (a fresh clone without `config/`, `data/*.db`, or
  `users.conf` is handled gracefully — the run skips with a notice)

## Usage examples

```bash
scripts/backup.sh                          # create backups/20260711T190000Z.tar.gz
scripts/backup.sh --list                   # list archives newest-first with sizes
scripts/backup.sh --restore backups/20260711T190000Z.tar.gz --yes
scripts/backup.sh --restore 20260711T190000Z.tar.gz --yes   # bare name resolved under backups/
```

## Edge cases

- **Nothing to back up yet** → exit 0 with a notice (no empty archive created);
  the message points at `scripts/setup.sh`.
- **Integrity failure after create** (`tar -tzf` or `gzip -t` fails) → the
  partial archive is removed and the script exits 1 — a backup is only declared
  OK after both checks pass.
- **`--restore` without `--yes`** → exit 2 with the exact re-run command;
  nothing is touched (proven by the smoke test: a corrupted member stays corrupted).
- **`--restore` of an unreadable/non-tar.gz file** → exit 1 before any preview.
- **Missing members** (e.g. no `users.conf` yet) → skipped with a notice;
  backups of partially-initialised systems stay possible.
- **Safety copy** → `backups/pre-restore-<timestamp>.tar.gz` of the CURRENT
  state, created and integrity-checked BEFORE extraction; if the safety copy
  fails integrity, the restore aborts.
- **Unknown option** → exit 2 + usage on stderr.

## Internal behaviour

1. Resolves `ROOT` from the script's own location (§11.4.177).
2. `collect_members` enumerates `config`, each `data/*.db|*.sqlite|*.sqlite3`,
   and `users.conf` that actually exist.
3. Create: `tar -czf` from the project root with relative member paths →
   chmod 600 → verify with `tar -tzf` AND `gzip -t` → report size.
4. List: `find -printf '%T@ %s %f'` sorted by mtime descending.
5. Restore: locate archive (direct path or under `backups/`) → integrity check
   → require `--yes` → print `PREVIEW` member list (`tar -tzf`, paths only) →
   verified safety copy → extract into the project root.

## Related scripts

- `scripts/setup.sh` — initialises the state that gets backed up.
- `scripts/sftp_ctl.sh` — `status` to verify the system after a restore.
- Constitution: §9 (data safety), §11.4.10 (credentials), §11.4.30 (backups/ ignored).

## Last verified

2026-07-11 — `bash -n` clean, shellcheck clean; create + `tar -tzf` listing +
`--list` + refuse-without-`--yes` + restore-with-safety-copy all proven by
`tests/test_scripts_smoke.sh` in a mktemp sandbox.
