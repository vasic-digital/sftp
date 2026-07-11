# HelixQA Suite Registration — SFTP Enterprise Management System

| Field | Value |
|---|---|
| **Revision:** | 1 |
| **Last modified:** | 2026-07-11T21:00:00Z |
| Description | HelixQA integration overview: suite registration, run instructions, and how to add suites |
| Authority | §11.4.27 (HelixQA full incorporation — "HelixQA MUST BE used with all possible written tests suites") |
| Maintainer | STREAM-5 (QA automation) |

## What is HelixQA?

HelixQA is the **autonomous QA execution engine** required by §11.4.27.
It dispatches registered test suites against the SFTP API + Web SPA, collects
captured evidence per §11.4.5/§11.4.69, and produces a structured PASS/FAIL/SKIP
verdict with per-suite evidence paths.

HelixQA autonomous sessions drive end-to-end execution of every registered test
bank with captured wire evidence per check (§11.4.27(B)). The engine is consumed
as a project dependency (the `HelixDevelopment/HelixQA` submodule) — this
directory registers the SFTP project's suites as DATA, never engine code
(§11.4.28 decoupling, §11.4.177 project-agnostic tooling).

## Suite registration

Suites are declared in `qa/helixqa/sftp_suites.yaml`. Each suite entry
carries:

| Field | Meaning |
|---|---|
| `name` | Stable unique suite identifier (e.g. `api-lifecycle`) |
| `display_name` | Human-readable label |
| `category` | `api` / `web` / `container` / `integration` |
| `command` | Shell command(s) that execute the suite |
| `working_dir` | Working directory for the command (relative to project root) |
| `expected_exit` | Expected exit code (0 for PASS) |
| `timeout_seconds` | Maximum wall-clock before forced termination |
| `challenges` | List of Challenge ids this suite exercises |
| `evidence_dir` | Where captured evidence lands |
| `severity` | `critical` / `high` / `medium` / `low` |
| `requires_api` | Whether the API must be running before suite dispatch |

## How to run

### Individual suite (manual)

```bash
# API lifecycle (CH-SFTP-001 through CH-SFTP-004):
bash tests/api/test_api_lifecycle.sh

# API stress (sustained load + concurrent contention):
bash tests/api/test_api_stress.sh

# API chaos (process-death, network-fault, resource-exhaustion):
bash tests/api/test_api_chaos.sh

# Web screenshot harness (4 screens x 2 themes):
node web/scripts/screenshots.mjs

# Go unit tests:
cd api && go test ./...

# Web unit tests:
cd web && npx vitest run
```

### Full autonomous HelixQA session

When the HelixQA engine is initialized in the project, all six suites
dispatch as a single autonomous QA session:

```bash
# Register + run all suites (dispatches via HelixQA engine):
helixqa run --project sftp --suites qa/helixqa/sftp_suites.yaml
```

The engine produces:
- `qa-results/helixqa/<session-id>/status.json` — per-suite verdicts
- `qa-results/helixqa/<session-id>/evidence/` — captured evidence per suite
- `qa-results/helixqa/<session-id>/stream.jsonl` — real-time event stream (§11.4.116)

## Adding a new suite

1. **Add an entry** to `sftp_suites.yaml` with all required fields.
2. **Ensure the test script exists** and is executable (`chmod +x`).
3. **Map Challenges** — list the Challenge ids from
   `qa/challenges/sftp_challenges.yaml` that this suite exercises.
4. **Validate the YAML** — run
   `python3 -c "import yaml; yaml.safe_load(open('qa/helixqa/sftp_suites.yaml'))"`.
5. **Run the suite standalone** to confirm it passes before registering.
6. **Update this README's suite table** (below) to include the new entry.

## Current suite coverage

| # | Suite name | Category | Challenges | Timeout |
|---|---|---|---|---|
| 1 | api-lifecycle | api | CH-SFTP-001..004 | 120 s |
| 2 | api-stress | api | CH-SFTP-003 | 300 s |
| 3 | api-chaos | api | CH-SFTP-003 | 300 s |
| 4 | web-screenshots | web | CH-SFTP-006 | 120 s |
| 5 | go-tests | api | — (unit) | 120 s |
| 6 | web-tests | web | — (unit) | 120 s |

## Related documents

- `qa/helixqa/sftp_suites.yaml` — machine-readable suite registration
- `qa/challenges/README.md` — Challenges framework
- `qa/challenges/sftp_challenges.yaml` — Challenge bank
- `tests/api/` — test scripts
- `web/scripts/screenshots.mjs` — §11.4.170 host-rendered proof harness
- `constitution/Constitution.md` §11.4.27 — HelixQA mandate
- `constitution/Constitution.md` §11.4.116 — real-time sync channel
