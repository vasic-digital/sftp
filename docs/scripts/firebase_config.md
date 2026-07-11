# firebase_config.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T19:05:00Z

## Overview

`scripts/firebase_config.sh` acquires the Firebase **web app SDK config**
dynamically via the `firebase` CLI (`firebase apps:sdkconfig WEB <app-id>`) and
writes it to `web/src/firebase-config.json` (git-ignored per §11.4.30 —
`firebase-config*.json`). Project and app ids come from `.env`
(`FIREBASE_PROJECT_ID`, `FIREBASE_WEB_APP_ID`) or `--project` / `--app`
overrides. The fetched config is **never printed to stdout** — only the
destination path (§11.4.10). A `--check` mode reports whether the config file
already exists and is valid JSON.

## Prerequisites

- bash ≥ 4
- For fetching: `firebase` CLI on PATH (`npm install -g firebase-tools`) and an
  active `firebase login` session
- For `--check` validation: `jq` OR `python3` (either is sufficient; if neither
  is present, `--check` exits 3 and fetch writes with an explicit warning)

## Usage examples

```bash
scripts/firebase_config.sh --check                       # is web/src/firebase-config.json present + valid?
scripts/firebase_config.sh                               # fetch using ids from .env
scripts/firebase_config.sh --project sftp-prod --app 1:123456789:web:abcdef
```

`.env` entries consumed (see `.env.example`):

```bash
FIREBASE_PROJECT_ID=sftp-enterprise-dev
FIREBASE_WEB_APP_ID=1:1234567890:web:0123456789abcdef   # add this line for your project
```

Discover app ids with: `firebase apps:list --project <id>`.

## Edge cases

- **`firebase` CLI missing** → exit 2 with the exact install command
  (`npm install -g firebase-tools`) and the `firebase login` reminder.
- **No project/app id anywhere** → exit 2 with guidance to set the `.env` keys
  or pass `--project`/`--app`.
- **`--check`, file absent** → exit 1 (informational — fetch has not run yet).
- **`--check`, invalid JSON** → exit 1 advising re-fetch.
- **`--check`, no validator installed** → exit 3 (file exists but cannot be validated).
- **`apps:sdkconfig` fails** (bad login, wrong ids) → exit 1 with a diagnostic
  pointing at `firebase login` and `firebase apps:list`; the temp file is removed.
- **Fetched payload is not valid JSON** → refused (exit 1); nothing is written.
- **Unknown option** → exit 2 + usage on stderr.

## Internal behaviour

1. Resolves `ROOT` from the script's own location (§11.4.177); `.env` is parsed
   as plain `KEY=VALUE` lines, never `source`d.
2. Fetch writes the SDK config to a `mktemp` file first (`--json -o <tmp>`, with
   a stdout-capture fallback for older firebase-tools), validates it with
   `jq`/`python3`, pretty-prints into `web/src/firebase-config.json`, chmod 600,
   and removes the temp file.
3. `--check` validates the existing file with `jq -e .` (python3 `json.load`
   fallback) and reports presence/validity without printing contents.

## Related scripts

- `scripts/setup.sh` — `.env` bootstrap (holds the FIREBASE_* ids).
- `web/` — consumes `src/firebase-config.json` at runtime (STREAM-3).
- Constitution: §11.4.10 (credentials), §11.4.30 (firebase-config*.json git-ignored).

## Last verified

2026-07-11 — `bash -n` clean, shellcheck clean; `--check` absent/valid-fixture
paths and missing-ids exit 2 proven by `tests/test_scripts_smoke.sh`. Live
fetch requires the operator's Firebase session (`firebase login`).
