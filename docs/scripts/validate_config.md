# validate_config.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T16:30:36Z
**Script:** `scripts/validate_config.sh` (in-source doc block at file top, §11.4.18)

## Overview

Offline validator for the SFTP account configuration. It validates
`config_schemas/accounts.yaml` and `config_schemas/accounts.json` against
`config_schemas/schema/accounts.schema.json` (JSON Schema draft 2020-12) and
pinpoints every violation with a JSON path + message. `--selftest` turns it
into its own anti-bluff gate: the negative fixtures in
`config_schemas/schema/fixtures/bad-*` MUST be rejected and the positive
`good-*` fixture MUST be accepted, or the script exits non-zero. A validator
that passes its bad fixtures is a §11.4 bluff — this gate makes that
mechanically visible.

No network access is used or required.

## Prerequisites

- `python3` (≥ 3.8) on `PATH` — required.
- python3 `jsonschema` + `yaml` (PyYAML) — primary backend. Verified present on
  the build host: jsonschema 4.25.1, PyYAML 6.0.3, Python 3.13.12.
- If `jsonschema` is missing, the script automatically uses its **documented
  structural fallback** (see "Internal behaviour"). Both backends were
  exercised on 2026-07-11 (fallback forced via a shadowing `jsonschema.py`
  that raises ImportError) — both produce identical verdicts and exit codes.

## Usage examples

```bash
# Validate the two canonical example files (exit 0 on conform):
scripts/validate_config.sh

# Anti-bluff self-test over the fixtures (exit 0 only if bad-* FAIL, good-* PASS):
scripts/validate_config.sh --selftest

# Validate a different config directory (e.g. a deployment checkout):
scripts/validate_config.sh --dir /etc/sftp-enterprise/config_schemas

# Quiet mode (summary only) — suitable for CI:
scripts/validate_config.sh --selftest --quiet
```

Typical output (default mode):

```
VALID config_schemas/accounts.yaml
VALID config_schemas/accounts.json
VALIDATION PASS: accounts.yaml + accounts.json conform to accounts.schema.json
```

On violation, the first pinpointed error plus any remaining ones:

```
INVALID config_schemas/accounts.yaml	/accounts/0/permission: 'execute' is not one of ['read_only', 'read_write', 'public']
VALIDATION FAIL: see INVALID lines above
```

## Edge cases

- **Parse errors** (malformed YAML/JSON) are reported as `INVALID <file> /: parse error: …` with exit 1 — a syntactically broken config never silently passes.
- **Missing files / missing schema / missing python3** are environment errors: exit 2 with an `ERROR:` line (distinct from validation failure, exit 1).
- **`--selftest` with < 5 fixtures** is an environment error (exit 2): the gate refuses to run against a gutted fixture set.
- **Fallback backend**: identical verdict shape and exit codes; it enforces exactly the constraints listed in "Internal behaviour" — it is a hardcoded mirror of the current schema, not a general JSON-Schema evaluator.
- **YAML/JSON parity**: `accounts.yaml` and `accounts.json` share one schema; divergence between them is caught by validating both in the same run.

## Internal behaviour

1. Parse CLI (`--dir`, `--selftest`, `--quiet`); locate `python3`; require `<dir>/schema/accounts.schema.json`.
2. Embedded python loads the schema; selects backend (`jsonschema` if importable, else structural fallback).
3. Per file: load (PyYAML for `.yaml`, `json` for `.json`), collect errors (sorted by JSON path), print `VALID`/`INVALID` + first error + `also` lines.
4. Default mode: strict over `accounts.yaml` + `accounts.json` (exit 1 on any INVALID).
5. `--selftest` mode: report-mode over every `bad-*`/`good-*` fixture; a `bad-*` yielding VALID or a `good-*` yielding INVALID flips the run to exit 1 ("validator is bluff-capable").

Fallback-enforced constraints (hardcoded mirror of the schema): `version == 1`;
`accounts` is a list; per account: required `username` + `permission`; username
regex `^[a-z_][a-z0-9_-]{0,31}$`; permission enum `read_only|read_write|public`;
`uid`/`gid` integers 0–65535; `home` regex `^/sftp_data/<username>$`;
`enabled`/`public_acknowledged` boolean; `comment` string; no unknown
properties; `permission == public ⇒ public_acknowledged === true`.

## Related scripts / docs

- `config_schemas/README.md` — schema semantics, permission model, render pipeline.
- `config_schemas/schema/accounts.schema.json` — the schema itself.
- `users.conf.example` — the atmoz render of the example accounts.
- `docs/research/mvp/MVP.md` — atmoz/sftp evidence (line grammar, ownership, restart-to-reload).
- `scripts/commit_all.sh` — conductor-owned commit wrapper (this script never commits).
- Other script guides: `docs/scripts/commit_all.md`, `docs/scripts/push_all.md`.

## Last verified

2026-07-11 — `bash -n` + `sh -n` clean; default run exit 0 (both example files VALID); `--selftest` exit 0 (4 bad rejected, 1 good accepted); fallback backend forced and re-verified (exit 0 both modes). Outputs captured in `qa/results/STREAM-3-report.md`.
