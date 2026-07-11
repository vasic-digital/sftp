# SFTP Project — Issues (workable items)

**Revision:** 4
**Last modified:** 2026-07-11T23:00:00Z

Tracked per §11.4.15/§11.4.16/§11.4.54. Status vocabulary: Queued | In progress | Ready for testing | In testing | Reopened | Operator-blocked | Fixed (→ Fixed.md) / Implemented (→ Fixed.md) / Completed (→ Fixed.md). Type: Bug | Feature | Task.

---

## §1. [ATM-001] Infrastructure & Foundation — submodules, env, compose, go.mod, layout

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Priority:** TOP (critical path — unblocks ATM-002/003/006)

Add all verified owned submodules at flat paths (§11.4.28) with install_upstreams (§11.4.36) + helix-deps.yaml records (§11.4.31); create the missing `.env.example` (full enterprise config surface); `.gitignore` matrix (§11.4.30 — `.env`, data, secrets, build outputs, `.db-wal/.db-shm`); `deploy/docker-compose.yml` (atmoz/sftp + postgres + api, rootless-podman compatible); `go.mod` for `api/` (Go 1.26) with `replace` directives to local module submodules; directory skeleton + placeholder READMEs; `VERSION = 0.1.0-dev`.
**Acceptance:** `git submodule status` lists all modules; `go list -m all` resolves; `podman-compose -f deploy/docker-compose.yml config` validates; no secret in tracked files (grep audit captured).
**Scope:** `.gitmodules`, `deploy/`, `.env.example`, `.gitignore`, `api/go.mod`, `VERSION`, `*/README.md` placeholders.

## §2. [ATM-002] Go REST API (Gin) — accounts, super-admin auth, DB, SFTP sync, audit

**Status:** In testing (core landed in 6460e5e, 5/5 pkgs GREEN; awaiting STREAM-9 integration evidence)
**Type:** Feature
**Priority:** TOP

Gin server: config load (config module), logging (observability), recovery; super-admin bootstrap + login + JWT middleware (auth/middleware) + rate limiting (ratelimiter); accounts CRUD with `read_only|read_write` permission enum and never-default `public` flag (explicit acknowledgement required); DB abstraction SQLite (dev) / PostgreSQL (prod) via database module with embedded migrations; atomic users.conf render + per-user directory provisioning + container reload; audit log; OpenAPI spec; `/healthz` `/readyz`.
**Acceptance:** unit tests GREEN; real curl CRUD round-trip transcript in `docs/qa/ATM-002/`; OpenAPI served; code-review GO (§11.4.125/§11.4.142).
**Scope:** `api/` (except go.mod from ATM-001), `docs/qa/ATM-002/`.

## §3. [ATM-003] SFTP config + permission system — YAML/JSON, renderer, migration

**Status:** Completed (→ Fixed.md) — config_schemas/ + validate_config.sh selftest 4-bad/1-good, in 6460e5e
**Type:** Feature
**Priority:** TOP

`config/server.yaml` + `config/accounts.yaml` with JSON-schema docs + examples; strict loader (unknown field = error); users.conf renderer (atmoz format) + directory provisioner + permission enforcement (RO write-mask / RW full); import of existing users.conf (MVP migration path); golden-file tests; real container round-trip evidence (RO upload denied, RW upload allowed).
**Acceptance:** golden tests GREEN; captured container transcript in `docs/qa/ATM-003/`.
**Scope:** `config/`, `api/internal/config*` (shared with ATM-002 — coordinated via conductor), `docs/qa/ATM-003/`.

## §6. [ATM-006] Bash management scripts — service ctl, setup, backup, firebase config

**Status:** Completed (→ Fixed.md) — 4 scripts + systemd + 44/44 smoke PASS + shellcheck clean, in 6460e5e
**Type:** Task
**Priority:** TOP

`scripts/service_ctl.sh` (start/stop/restart/status, rootless podman-compose, no sudo); systemd `--user` units + installer; `scripts/setup.sh` (first-time env init — secrets never echoed per §11.4.10, super-admin creation, smoke); `scripts/backup.sh` (DB + data snapshots + restore); `scripts/firebase_config.sh` (dynamic Firebase config acquisition, git-ignored outputs). Every script: §11.4.18 doc block + `docs/scripts/<name>.md` + shellcheck clean.
**Acceptance:** real start/stop cycle transcript in `docs/qa/ATM-006/`; docs present for every script.
**Scope:** `scripts/` (non-testing), `deploy/systemd/`, `docs/scripts/`.

## §8. [ATM-008] Design system & assets — OpenDesign, themes, asset formats

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Priority:** MIDDLE

OpenDesign tokens integrated into web + mobile builds; light/dark theme packs; `docs/design/` assets: SVG authoritative + PNG renders + PDF boards + Figma/PenPot/PSD exports where tooling permits; asset manifest + pre-build gate validation.
**Acceptance:** tokens consumed by both builds; manifest gate GREEN; assets present per manifest.
**Scope:** `docs/design/`, `web/src/theme/`, `mobile/**/theme/`.

## §9. [ATM-009] Test matrix, Challenges banks, HelixQA suites

**Status:** In progress (STREAM-9 dispatched 2026-07-11; API lifecycle evidence being captured under qa/results/stream9/)
**Type:** Task
**Priority:** TOP (gates every closure)

Extend `tests/pre_build_verification.sh` (constitution, gitignore, env-safety, docs-sync, layout, asset-manifest gates); integration suite (API↔DB↔users.conf↔live container — real, §11.4.27 no fakes beyond unit); e2e operator journey; stress/chaos/performance/security suites (§11.4.85); Challenges banks + HelixQA registration under `qa/`; risk-ordered execution (§11.4.132).
**Acceptance:** per-suite captured logs in `qa-results/` (git-ignored) + curated summaries in `docs/qa/`; gates GREEN on a clean tree.
**Scope:** `tests/`, `qa/`, `qa-results/` (ignored).

## §10. [ATM-010] Documentation — manuals, guides, FAQ, tutorials, diagrams, Docs Chain

**Status:** In progress (core set done in c5e68b9; continues per stream)
**Type:** Task
**Priority:** MIDDLE

Docs Chain contexts (`.docs_chain/`) for README/Status/Issues/Fixed/CONTINUATION + HTML+PDF exports (§11.4.65); user manual, admin guide, API reference (from OpenAPI), FAQ, tutorials, architecture diagrams (SVG); revision headers (§11.4.44); standing resumption file discipline (§11.4.131).
**Acceptance:** `docs_chain verify` GREEN; exports in sync (mtime check); every doc has revision header.
**Scope:** `docs/` (shared with conductor; disjoint from `docs/qa/<ATM-*>` per stream), `.docs_chain/`.

## §11. [ATM-011] Gates, code review, release plumbing, governance amendment

**Status:** In progress (commit wrapper hardened + self-validated; per-task/final code review + release plumbing continue)
**Type:** Task
**Priority:** TOP (continuous)

Commit/push wrappers with quiescence check (§11.4.84) + detached push to all upstreams (§11.4.88); code-review subagent before every build (§11.4.125/§11.4.142); paired mutations for behavioral gates (§1.1); CLAUDE.md/AGENTS.md amendment (Go/TS/Kotlin now in-repo — project-specific classification per §11.4.17); release tag naming `sftp-<version>` (§11.4.151) gated on full retest (§11.4.40) + manual QA (§11.4.185).
**Acceptance:** wrapper used for every commit; review GO recorded per batch; amendment commit lands in Phase 1.
**Scope:** `scripts/commit_all.sh`, `scripts/push_all.sh`, `CLAUDE.md`, `AGENTS.md`, `.claude/`.
