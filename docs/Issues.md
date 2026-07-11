# SFTP Project — Issues (workable items)

**Revision:** 5
**Last modified:** 2026-07-11T20:05:00Z

Tracked per §11.4.15/§11.4.16/§11.4.54. Status vocabulary: Queued | In progress | Ready for testing | In testing | Reopened | Operator-blocked | Fixed (→ Fixed.md) / Implemented (→ Fixed.md) / Completed (→ Fixed.md). Type: Bug | Feature | Task.

---

## §1. [FTP-001] Infrastructure & Foundation — submodules, env, compose, go.mod, layout

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Priority:** TOP (critical path — unblocks FTP-002/003/006)

Add all verified owned submodules at flat paths (§11.4.28) with install_upstreams (§11.4.36) + helix-deps.yaml records (§11.4.31); create the missing `.env.example` (full enterprise config surface); `.gitignore` matrix (§11.4.30 — `.env`, data, secrets, build outputs, `.db-wal/.db-shm`); `deploy/docker-compose.yml` (atmoz/sftp + postgres + api, rootless-podman compatible); `go.mod` for `api/` (Go 1.26) with `replace` directives to local module submodules; directory skeleton + placeholder READMEs; `VERSION = 0.1.0-dev`.
**Acceptance:** `git submodule status` lists all modules; `go list -m all` resolves; `podman-compose -f deploy/docker-compose.yml config` validates; no secret in tracked files (grep audit captured).
**Scope:** `.gitmodules`, `deploy/`, `.env.example`, `.gitignore`, `api/go.mod`, `VERSION`, `*/README.md` placeholders.

## §2. [FTP-002] Go REST API (Gin) — accounts, super-admin auth, DB, SFTP sync, audit

**Status:** Implemented (→ Fixed.md) — full REST API with JWT auth, CRUD, sync, vault, Firebase; 85+ tests GREEN; manual QA 10/10 PASS; release tag sftp-0.1.0-dev-0.1.0
**Type:** Feature
**Priority:** TOP

Gin server: config load (config module), logging (observability), recovery; super-admin bootstrap + login + JWT middleware (auth/middleware) + rate limiting (ratelimiter); accounts CRUD with `read_only|read_write` permission enum and never-default `public` flag (explicit acknowledgement required); DB abstraction SQLite (dev) / PostgreSQL (prod) via database module with embedded migrations; atomic users.conf render + per-user directory provisioning + container reload; audit log; OpenAPI spec; `/healthz` `/readyz`.
**Acceptance:** unit tests GREEN; real curl CRUD round-trip transcript in `docs/qa/FTP-002/`; OpenAPI served; code-review GO (§11.4.125/§11.4.142).
**Scope:** `api/` (except go.mod from FTP-001), `docs/qa/FTP-002/`.

## §3. [FTP-003] SFTP config + permission system — YAML/JSON, renderer, migration

**Status:** Completed (→ Fixed.md) — config_schemas/ + validate_config.sh selftest 4-bad/1-good, in 6460e5e
**Type:** Feature
**Priority:** TOP

`config/server.yaml` + `config/accounts.yaml` with JSON-schema docs + examples; strict loader (unknown field = error); users.conf renderer (atmoz format) + directory provisioner + permission enforcement (RO write-mask / RW full); import of existing users.conf (MVP migration path); golden-file tests; real container round-trip evidence (RO upload denied, RW upload allowed).
**Acceptance:** golden tests GREEN; captured container transcript in `docs/qa/FTP-003/`.
**Scope:** `config/`, `api/internal/config*` (shared with FTP-002 — coordinated via conductor), `docs/qa/FTP-003/`.

## §6. [FTP-006] Bash management scripts — service ctl, setup, backup, firebase config

**Status:** Completed (→ Fixed.md) — 4 scripts + systemd + 44/44 smoke PASS + shellcheck clean, in 6460e5e
**Type:** Task
**Priority:** TOP

`scripts/service_ctl.sh` (start/stop/restart/status, rootless podman-compose, no sudo); systemd `--user` units + installer; `scripts/setup.sh` (first-time env init — secrets never echoed per §11.4.10, super-admin creation, smoke); `scripts/backup.sh` (DB + data snapshots + restore); `scripts/firebase_config.sh` (dynamic Firebase config acquisition, git-ignored outputs). Every script: §11.4.18 doc block + `docs/scripts/<name>.md` + shellcheck clean.
**Acceptance:** real start/stop cycle transcript in `docs/qa/FTP-006/`; docs present for every script.
**Scope:** `scripts/` (non-testing), `deploy/systemd/`, `docs/scripts/`.

## §8. [FTP-008] Design system & assets — OpenDesign, themes, asset formats

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Priority:** MIDDLE

OpenDesign tokens integrated into web + mobile builds; light/dark theme packs; `docs/design/` assets: SVG authoritative + PNG renders + PDF boards + Figma/PenPot/PSD exports where tooling permits; asset manifest + pre-build gate validation.
**Acceptance:** tokens consumed by both builds; manifest gate GREEN; assets present per manifest.
**Scope:** `docs/design/`, `web/src/theme/`, `mobile/**/theme/`.

## §9. [FTP-009] Test matrix, Challenges banks, HelixQA suites

**Status:** In progress — 15/15 test types covered, 6/6 Challenges PASS (100%), HelixQA 161/163 GREEN; 5 test scripts have minor failures pending fixes (FTP-012)
**Type:** Task
**Priority:** TOP (gates every closure)

Extend `tests/pre_build_verification.sh` (constitution, gitignore, env-safety, docs-sync, layout, asset-manifest gates); integration suite (API↔DB↔users.conf↔live container — real, §11.4.27 no fakes beyond unit); e2e operator journey; stress/chaos/performance/security suites (§11.4.85); Challenges banks + HelixQA registration under `qa/`; risk-ordered execution (§11.4.132).
**Acceptance:** per-suite captured logs in `qa-results/` (git-ignored) + curated summaries in `docs/qa/`; gates GREEN on a clean tree.
**Scope:** `tests/`, `qa/`, `qa-results/` (ignored).

## §10. [FTP-010] Documentation — manuals, guides, FAQ, tutorials, diagrams, Docs Chain

**Status:** In progress (core set done in c5e68b9; continues per stream)
**Type:** Task
**Priority:** MIDDLE

Docs Chain contexts (`.docs_chain/`) for README/Status/Issues/Fixed/CONTINUATION + HTML+PDF exports (§11.4.65); user manual, admin guide, API reference (from OpenAPI), FAQ, tutorials, architecture diagrams (SVG); revision headers (§11.4.44); standing resumption file discipline (§11.4.131).
**Acceptance:** `docs_chain verify` GREEN; exports in sync (mtime check); every doc has revision header.
**Scope:** `docs/` (shared with conductor; disjoint from `docs/qa/<FTP-*>` per stream), `.docs_chain/`.

## §11. [FTP-011] Gates, code review, release plumbing, governance amendment

**Status:** In progress (commit wrapper hardened + self-validated; per-task/final code review + release plumbing continue)
**Type:** Task
**Priority:** TOP (continuous)

Commit/push wrappers with quiescence check (§11.4.84) + detached push to all upstreams (§11.4.88); code-review subagent before every build (§11.4.125/§11.4.142); paired mutations for behavioral gates (§1.1); CLAUDE.md/AGENTS.md amendment (Go/TS/Kotlin now in-repo — project-specific classification per §11.4.17); release tag naming `sftp-<version>` (§11.4.151) gated on full retest (§11.4.40) + manual QA (§11.4.185).
**Acceptance:** wrapper used for every commit; review GO recorded per batch; amendment commit lands in Phase 1.
**Scope:** `scripts/commit_all.sh`, `scripts/push_all.sh`, `CLAUDE.md`, `AGENTS.md`, `.claude/`.

## §12. [FTP-012] Test hardening — fix all 5 failing test scripts

**Status:** In progress (fix agent dispatched 2026-07-11)
**Type:** Bug
**Priority:** TOP (blocks all validation)

5 test scripts have failures from the full test suite run: ddos (1/7 rate-limit threshold), benchmarking (2/14 timing thresholds), full-automation (bash `local` syntax error), challenges-driver (FAIL), helixqa-driver (bash `local` syntax error). All 5 must be fixed and verified PASS.
**Acceptance:** All 14 test scripts exit PASS against live API; evidence in `qa/results/TEST-FIXES-report.md`.
**Scope:** `tests/ddos/`, `tests/benchmarking/`, `tests/full_automation/`, `tests/challenges/`, `tests/helixqa/`.

## §13. [FTP-013] Code-level bug fixes — logging middleware, CSP, doc exports

**Status:** Queued
**Type:** Bug
**Priority:** TOP

Fix K2 (logging middleware reports 200 for 500 errors), K3 (no CSP header on web SPA), K6 (4 missing summary doc PDF exports), K7 (API reference PDF missing).
**Acceptance:** Each fix verified with captured evidence; docs exported to HTML+PDF.
**Scope:** `api/internal/api/router.go`, `web/index.html`, `docs/`.

## §14. [FTP-014] Container deployment verification — real SFTP end-to-end

**Status:** Queued
**Type:** Feature
**Priority:** MIDDLE

Verify the full container deployment: podman-compose up, SFTP upload/download through the atmoz/sftp container, permission enforcement (RO write denied, RW write allowed), directory provisioning, restart persistence. This was never tested on this host.
**Acceptance:** Real SFTP transcript with upload/download verification; container logs; permission enforcement proof.
**Scope:** `deploy/`, container runtime.

## §15. [FTP-015] Security hardening — HttpOnly cookies + CSP + security headers

**Status:** Queued
**Type:** Feature
**Priority:** MIDDLE

Migrate web token storage from localStorage to HttpOnly cookies (requires backend cookie handling + frontend credentials:'include'), add CSRF protection, security headers audit (X-Frame-Options, X-Content-Type-Options, HSTS).
**Acceptance:** Browser devtools screenshot showing HttpOnly cookie; security header audit GREEN.
**Scope:** `web/src/api/client.ts`, `web/src/auth/AuthContext.tsx`, `api/internal/api/`.

## §16. [FTP-016] Vault master key rotation

**Status:** Queued
**Type:** Feature
**Priority:** LOW

Implement Vault.RotateKey() — generate new master key, re-encrypt all entries, atomically replace key file. Add tests: rotate → all entries readable, old key can't decrypt. Add CLI command or API endpoint.
**Acceptance:** Unit tests GREEN; manual rotation verified with captured evidence.
**Scope:** `api/internal/vault/`.

## §17. [FTP-017] Mobile Android APK build verification

**Status:** Queued
**Type:** Task
**Priority:** LOW

Verify Gradle build produces debug APK, verify APK artifact, document host requirements for iOS/HarmonyOS/AuroraOS (honest SKIPs). 7/7 KMP tests must pass.
**Acceptance:** APK artifact present and valid; build output captured.
**Scope:** `mobile/`.

## §18. [FTP-018] Production config hardening + PostgreSQL verification

**Status:** Queued
**Type:** Task
**Priority:** LOW

Production-ready .env.example review, PostgreSQL driver verification (currently only SQLite tested), TLS/HTTPS setup guide, backup automation script verification.
**Acceptance:** Config validation passes; PostgreSQL start + query verified; backup restore tested.
**Scope:** `.env.example`, `deploy/`, `config_schemas/`.
