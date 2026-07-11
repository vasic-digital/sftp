# Challenges Bank — SFTP Enterprise Management System

| Field | Value |
|---|---|
| **Revision:** | 1 |
| **Last modified:** | 2026-07-11T21:00:00Z |
| Description | Challenges framework overview, run instructions, and contribution guide |
| Authority | §11.4.27/.52 (HelixQA full incorporation + autonomous validation) |
| Maintainer | STREAM-5 (QA automation) |

## What are Challenges?

Challenges are **machine-readable, autonomous validation probes** that exercise
a specific SFTP-API endpoint, flow, or subsystem and produce a deterministic
PASS/FAIL/SKIP verdict with captured evidence (§11.4.5/§11.4.69). A green
Challenge run means the feature genuinely works end-to-end for the user — never
a metadata-only or grep-based claim (§11.4 anti-bluff covenant).

Each Challenge entry in `sftp_challenges.yaml` declares:

| Field | Meaning |
|---|---|
| `id` | Stable unique identifier (`CH-SFTP-NNN`) |
| `name` | Human-readable short name |
| `category` | `api` / `web` / `container` / `firebase` |
| `description` | What this Challenge validates and why |
| `execute` | Shell command(s) that produce a verdict (array or string) |
| `expected` | Assertion: HTTP status, JSON body keys, exit code, or output pattern |
| `depends_on` | Optional list of other Challenge ids this one requires to pass first |
| `evidence` | Path(s) where captured evidence is written |
| `severity` | `critical` (release-blocker) / `high` / `medium` / `low` |

## How to run

### Run a single Challenge

```bash
bash tests/api/lib_api.sh           # source the shared test library
bash tests/api/test_api_lifecycle.sh   # executes CH-SFTP-001 through CH-SFTP-004
```

### Run the full Challenge bank

When the HelixQA integration (`qa/helixqa/`) is wired, the bank is dispatched
as part of the HelixQA autonomous QA session:

```bash
# Full bank (all 6 Challenges):
bash qa/helixqa/sftp_suites.yaml     # run via HelixQA orchestrator

# Or manually:
bash tests/api/test_api_lifecycle.sh
bash tests/api/test_api_stress.sh
bash tests/api/test_api_chaos.sh
node web/scripts/screenshots.mjs
```

### Expected runtime

| Challenge | ~Wall-clock |
|---|---|
| CH-SFTP-001 (health) | < 1 s |
| CH-SFTP-002 (login) | < 2 s |
| CH-SFTP-003 (CRUD) | < 5 s |
| CH-SFTP-004 (public guard) | < 2 s |
| CH-SFTP-005 (Firebase degrade) | < 3 s |
| CH-SFTP-006 (Web SPA) | < 30 s |

Total bank: ~45 s headless, longer with screenshots.

## Adding a new Challenge

1. **Choose the next available id** — `CH-SFTP-NNN` where NNN is the next
   unused sequence number. Check `sftp_challenges.yaml` for the current maximum.
2. **Add an entry** to `sftp_challenges.yaml` following the schema above.
   Every new entry MUST include a `description` with at least 40 characters
   naming SUBJECT + PROBLEM/GOAL (§11.4.91).
3. **Write the test script** (or extend an existing one) under `tests/api/`
   or `web/scripts/`. The script MUST use `ab_pass_with_evidence` /
   `ab_skip_with_reason` per §11.4.69 — never bare `echo PASS`.
4. **Produce captured evidence** — the test MUST write its evidence to
   `qa-results/<challenge-id>/<run-id>/`. No evidence, no PASS (§11.4.83).
5. **Register in HelixQA** — add a suite entry in `qa/helixqa/sftp_suites.yaml`
   mapping the new Challenge to its test script(s).
6. **Validate the YAML** — run `python3 -c "import yaml; yaml.safe_load(open('qa/challenges/sftp_challenges.yaml'))"`
   before committing. Malformed YAML is a release blocker.

## Current coverage

| # | ID | Category | Severity |
|---|---|---|---|
| 1 | CH-SFTP-001 | api | critical |
| 2 | CH-SFTP-002 | api | critical |
| 3 | CH-SFTP-003 | api | critical |
| 4 | CH-SFTP-004 | api | high |
| 5 | CH-SFTP-005 | firebase | medium |
| 6 | CH-SFTP-006 | web | critical |

## Related documents

- `qa/challenges/sftp_challenges.yaml` — machine-readable bank
- `qa/helixqa/README.md` — HelixQA integration
- `qa/helixqa/sftp_suites.yaml` — suite registration
- `tests/api/` — test scripts (lifecycle, stress, chaos)
- `web/scripts/screenshots.mjs` — §11.4.170 host-rendered visual proof harness
- `docs/CONTINUATION.md` — session resumption
- `docs/Issues.md` — workable-item tracker
