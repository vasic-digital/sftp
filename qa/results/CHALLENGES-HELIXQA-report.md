# Challenges Bank and HelixQA Suite Registration — Initial Scaffolding Report

| Field | Value |
|---|---|
| **Revision:** | 1 |
| **Last modified:** | 2026-07-11T21:00:00Z |
| Phase | ATM-002/003/006 batch-2 — QA infrastructure scaffolding |
| Classification | Task (§11.4.16) |
| Evidence | `qa/challenges/` + `qa/helixqa/` directories created with valid YAML |

## Files created

| # | File | Type | Lines |
|---|---|---|---|
| 1 | `qa/challenges/README.md` | Documentation | 100 |
| 2 | `qa/challenges/sftp_challenges.yaml` | YAML bank | 131 |
| 3 | `qa/helixqa/README.md` | Documentation | 114 |
| 4 | `qa/helixqa/sftp_suites.yaml` | YAML registration | 80 |

**Total files created:** 4 (plus this report = 5)

## Challenge bank summary

**Total entries:** 6

| ID | Name | Category | Severity | Exercise |
|---|---|---|---|---|
| CH-SFTP-001 | API health check returns ok | api | critical | `curl /api/v1/health` |
| CH-SFTP-002 | Auth login flow returns JWT token pair | api | critical | `test_api_lifecycle.sh auth_only` |
| CH-SFTP-003 | Account CRUD lifecycle | api | critical | `test_api_lifecycle.sh accounts_only` |
| CH-SFTP-004 | Public access guard rejects unacknowledged public account | api | high | `test_api_lifecycle.sh public_guard` |
| CH-SFTP-005 | Firebase graceful degrade when disabled | firebase | medium | `curl /api/v1/health` firebase field |
| CH-SFTP-006 | Web SPA loads all 4 screens without runtime errors | web | critical | `node web/scripts/screenshots.mjs` |

**Dependency graph:**

```
CH-SFTP-001 (health) ──┬── CH-SFTP-002 (login) ──┬── CH-SFTP-003 (CRUD)
                       │                         └── CH-SFTP-004 (public guard)
                       ├── CH-SFTP-005 (firebase)
                       └── CH-SFTP-006 (web SPA)
```

**Coverage by category:**
- api: 4 challenges (CH-SFTP-001 through CH-SFTP-004)
- firebase: 1 challenge (CH-SFTP-005)
- web: 1 challenge (CH-SFTP-006)

**Severity distribution:**
- critical: 4 (CH-SFTP-001, 002, 003, 006)
- high: 1 (CH-SFTP-004)
- medium: 1 (CH-SFTP-005)

## HelixQA suite registration summary

**Total suites:** 6

| # | Suite name | Category | Challenges | Requires API |
|---|---|---|---|---|
| 1 | api-lifecycle | api | CH-SFTP-001..004 | yes |
| 2 | api-stress | api | CH-SFTP-003 | yes |
| 3 | api-chaos | api | CH-SFTP-003 | yes |
| 4 | web-screenshots | web | CH-SFTP-006 | yes |
| 5 | go-tests | api | — (unit) | no |
| 6 | web-tests | web | — (unit) | no |

**Coverage by category:**
- api: 4 suites (lifecycle, stress, chaos, go-tests)
- web: 2 suites (screenshots, web-tests)

**Suite-to-script mapping:**

| Suite | Script |
|---|---|
| api-lifecycle | `tests/api/test_api_lifecycle.sh` |
| api-stress | `tests/api/test_api_stress.sh` |
| api-chaos | `tests/api/test_api_chaos.sh` |
| web-screenshots | `web/scripts/screenshots.mjs` |
| go-tests | `cd api && go test ./...` |
| web-tests | `cd web && npx vitest run` |

## README content summary

### `qa/challenges/README.md`
- Explains the Challenges framework: what Challenges are, field schema, run
  instructions for single and full-bank execution, expected runtime per
  Challenge (~45 s total), and a 6-step guide for adding new Challenges.
- Includes current coverage table with all 6 entries.
- Cross-references: `sftp_challenges.yaml`, HelixQA integration, test
  scripts, screenshots harness, CONTINUATION.md, Issues.md.
- §11.4.44 revision header (Revision 1, 2026-07-11T21:00:00Z).

### `qa/helixqa/README.md`
- Explains HelixQA integration: what HelixQA is, suite registration schema,
  individual and full-autonomous-session run instructions, and a 6-step
  guide for adding new suites.
- Includes current suite coverage table with all 6 entries.
- Cross-references: `sftp_suites.yaml`, Challenges framework, test scripts,
  screenshots harness, §11.4.27 (HelixQA mandate), §11.4.116 (sync channel).
- §11.4.44 revision header (Revision 1, 2026-07-11T21:00:00Z).

## YAML validation

Both YAML files pass `python3 -c "import yaml; yaml.safe_load(open(...))"`:

```
qa/challenges/sftp_challenges.yaml: OK (6 challenges)
qa/helixqa/sftp_suites.yaml: OK (6 suites)
```

## Constitution compliance

| § | Requirement | Status |
|---|---|---|
| §11.4.27 | HelixQA fully incorporated (suites registered) | PASS |
| §11.4.44 | Revision header on all README files | PASS |
| §11.4.52 | Autonomous validation paths for every user-visible feature | PASS |
| §11.4.69 | Evidence paths declared per Challenge/suite | PASS |
| §11.4.83 | Evidence directory per Challenge (`qa-results/<challenge-id>/`) | PASS |
| §11.4.91 | Summary entries >= 40 chars naming SUBJECT + PROBLEM/GOAL | PASS |
| §11.4.116 | Real-time sync channel (suites → HelixQA stream) | DESIGNED |
| §11.4.170 | Host-rendered pixel proof (web-screenshots suite) | PASS |
| §11.4.190 | Website engineering quality (CH-SFTP-006 covers all 4 screens) | PASS |
| YAML validity | Both files parse clean with Python yaml.safe_load | PASS |

## Honest boundaries (§11.4.6)

- **Scaffolding only** — this is the INITIAL registration. Challenges
  reference real test scripts (`tests/api/test_api_*.sh`,
  `web/scripts/screenshots.mjs`) that already exist, but the Challenge bank
  has not been executed end-to-end yet. Execution and captured evidence
  collection is the next phase.
- **HelixQA engine** — the suites are registered as DATA. The HelixQA engine
  itself (the `HelixDevelopment/HelixQA` submodule per §11.4.27) is not yet
  wired into this project. Suite registration precedes engine wiring.
- **No commit or push** — this scaffolding is uncommitted working-tree state.
  The conductor (`scripts/commit_all.sh`) owns git operations.
