# setup.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T19:05:00Z

## Overview

`scripts/setup.sh` performs first-time (and safely repeatable) setup of the
SFTP Enterprise system: it creates `.env` from the tracked `.env.example`,
generates the two bootstrap secrets (`JWT_SECRET`, `SUPERADMIN_PASSWORD`) with
`openssl rand` into `.env` (chmod 600, git-ignored per §11.4.30), creates the
`data/` directories, and prints next-steps. Secret **values are never printed**
to stdout/stderr — only the fact that they were written and where (§11.4.10).

## Prerequisites

- bash ≥ 4, `openssl` on PATH, coreutils
- `.env.example` present in the project root (tracked template)

## Usage examples

```bash
scripts/setup.sh             # first-time setup (keeps an existing .env untouched)
scripts/setup.sh --dry-run   # print every planned action, write nothing
scripts/setup.sh --force     # regenerate .env (previous file → .env.bak.<UTC timestamp>)
```

## Edge cases

- **`.env` already exists, no `--force`** → kept as-is; the script only fills
  in `JWT_SECRET` if missing/placeholder and `SUPERADMIN_PASSWORD` if missing,
  and re-applies chmod 600. Re-running is idempotent — secrets are NOT rotated
  without `--force`.
- **`.env.example` missing** → exit 1 naming the expected path.
- **`openssl` absent** → exit 1 with an explicit error before any write.
- **`--dry-run`** → prints the exact action plan (including whether `.env`
  would be created, kept, or backed up) and changes nothing — verified by the
  smoke test via a before/after sha256 of `.env`.
- **`--force`** → the previous `.env` is copied to `.env.bak.<timestamp>`
  (chmod 600) BEFORE regeneration; nothing is silently destroyed (§9 data
  safety).
- **Unknown option** → exit 2 + usage on stderr.

## Internal behaviour

1. Resolves `ROOT` from the script's own location (§11.4.177) — no hardcoded paths.
2. Copies `.env.example` → `.env` (unless keeping an existing one), chmod 600.
3. `set_env_key` replaces-or-appends `KEY=VALUE` lines with sed-escaped values.
4. Secrets: `openssl rand -base64 48` (JWT) / `24` (superadmin), newlines stripped.
5. `mkdir -p data data/sftp`; prints the numbered next-steps block
   (users.conf → `sftp_ctl.sh start` → `status` → optional `install` / Firebase).

## Related scripts

- `scripts/sftp_ctl.sh` — stack start/status/install after setup.
- `scripts/backup.sh` — backs up the state setup.sh initialises.
- `scripts/firebase_config.sh` — optional step 6 in the next-steps block.
- Constitution: §11.4.10 (credentials), §11.4.30 (.env git-ignored), §9 (no silent destruction).

## Last verified

2026-07-11 — `bash -n` clean, shellcheck clean; first-run, idempotent re-run,
`--dry-run` no-write, and `--force` backup+regeneration all proven by
`tests/test_scripts_smoke.sh` in a mktemp sandbox.
