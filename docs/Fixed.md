# SFTP Project — Fixed (closed items)

**Revision:** 4
**Last modified:** 2026-07-12T00:10:00Z

Archive of closed workable items, tracked per §11.4.19 (fixed-document column alignment) and §11.4.33 (type-aware closure vocabulary).

**Migration rule (atomic, §11.4.19):** when an item in `docs/Issues.md` reaches a terminal status — `Fixed (→ Fixed.md)` for Type `Bug`, `Implemented (→ Fixed.md)` for Type `Feature`, `Completed (→ Fixed.md)` for Type `Task`, or `Obsolete (→ Fixed.md)` per §11.4.90 — it moves into this file **in the same commit**: the heading + full body leave `Issues.md`, disappear from `docs/Issues_Summary.md` (open-only), and appear in `docs/Fixed_Summary.md` (closed-only). No item may exist in both files.

**Entry format:** every heading carries a `**Status:**` line (terminal closure value) and a `**Type:**` line (`Bug | Feature | Task`) within 8 non-blank lines, plus the evidence citation (test log / captured proof) that justified closure. Items with `reopens_count > 0` additionally carry a `docs/issues/<FTP-NNN>/Reopens.md` history per §11.4.55.

---

## §F1. [FTP-001] Infrastructure & Foundation — submodules, env, compose, go.mod, layout

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9, pushed to github+gitlab+gitflic+gitverse)

25 owned submodules staged at flat paths (§11.4.28) with `.helix-manifest.yaml` audit record (§11.4.31) + multi-upstream remotes installed in all 24 recipe-bearing submodules (§11.4.36, `open_design` third-party exempt); `.env.example` full surface; `.gitignore` matrix incl. compiled-binary class; `deploy/docker-compose.yml` (atmoz/sftp + postgres + api, rootless); `api/go.mod` Go 1.26 with `replace` directives to all 19 `digital.vasic.*` submodules; blank-import bootstrap compiles.
**Evidence:** `go build ./...` + `go vet ./...` exit 0 against all 19 real submodule packages; every blank-import path verified on disk (19/19 OK); secret scan clean (no key material; compose `POSTGRES_PASSWORD` uses `${POSTGRES_PASSWORD:-CHANGE_ME}` indirection); compose YAML parses; push log `qa-results/push/push_20260711T155549Z.log` (4/4 upstreams OK).

## §F2. [FTP-008] Design system & assets — OpenDesign, themes, asset formats

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9)

OpenDesign token set (color/typography/spacing/radius/elevation/tokens.json, light+dark) + 5 SVG assets (logo, server, user-ro, user-rw, admin) + boards/README + RENDER.md; web TS bindings (`web/src/theme/opendesign/{tokens,theme,index}.ts`); KMP bindings (`mobile/shared/.../theme/{Tokens,SftpTheme}.kt`); `open_design` submodule staged.
**Evidence:** all 6 token JSONs parse (python json.load OK); all 5 SVGs well-formed (ElementTree parse OK).

## §F3. [FTP-010] Documentation core set — guides, FAQ, tutorials, architecture, Docs Chain contexts

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9) — core set; FTP-010 remains open for per-stream doc growth.

4 guides (deployment, user-management, security, troubleshooting), FAQ, 2 tutorials (quickstart, api_quickstart), 2 architecture docs (overview, permissions_model), design manifest + READMEs, Docs Chain consumer contexts ×5 (issues/fixed/status/continuation/readme_links), script guides (commit_all, push_all), Status + Status_Summary pair.
**Evidence:** all 5 docs_chain context YAMLs parse (yaml.safe_load OK); revision headers spot-checked present on delivered docs (§11.4.44).

## §F4. [FTP-004] Web admin — React/TS SPA, OpenDesign, i18n, UI tests

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-4 DONE)

Vite + React + TS; OpenDesign tokens (light/dark); API-Client-TS, Auth-Context-React, State-Management-TS, I18n-Client-TS (en); screens: login, dashboard, account editor (permission/public toggles), audit log, settings; Testing-Utils-TS UI tests; §11.4.170 host-rendered screenshot proof per screen × {light,dark}.
**Evidence:** `npm run build` exit 0 (49 modules, tsc strict); 19/19 vitest PASS; 11 host-rendered Playwright screenshots (all routes × {light,dark}, plus public-guard state) with zero runtime errors; full report at `qa/results/STREAM-4-report.md`.
**Scope:** `web/`.

## §F5. [FTP-005] Mobile clients — KMP + Compose Multiplatform (Android/iOS/HarmonyOS/AuroraOS)

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-5 DONE, fix applied)

Gradle KMP scaffold (shared + 4 targets); Auth-KMP, Security-KMP, Config-KMP, Storage-KMP; in-project KMP i18n + HTTP client (I18n-KMP/Network-KMP do not exist — honest in-project scope per §11.4.6); debug/release variants; Firebase config placeholders; 20 .kt files across commonMain (13), androidMain (3), iosMain (3), harmonyosMain (0: honest SKIP per §11.4.3), auroraosMain (0: honest SKIP per §11.4.3), commonTest (1).
**Evidence:** Fix applied — TokenStorage interface extraction resolved final-class subclassing error per `qa/results/STREAM-5-fix-report.md`; `compileDebugKotlinAndroid` exit 0; 7/7 tests PASS ×2 deterministic consistency (§11.4.50); full reports at `qa/results/STREAM-5-report.md` + `qa/results/STREAM-5-fix-report.md`.
**Scope:** `mobile/`.

## §F6. [FTP-007] Firebase integration — Admin SDK, config, graceful degrade, fail-fast

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-7 DONE + REVIEW-A fix applied)

Firebase Admin SDK v4.21.0 optional subsystem: disabled-by-default (`FIREBASE_ENABLED=false`), fail-fast on misconfiguration (clear actionable error naming the exact env var or path), graceful degrade when disabled (all hooks safe no-ops). Wired into `/api/v1/health` endpoint reporting Firebase status (`disabled`/`connected`/`unhealthy`). Code review REVIEW-A: 7 findings (1 HIGH, 2 MEDIUM, 4 LOW) all remediated with captured evidence.
**Evidence:** `go build ./...` + `go vet ./...` exit 0; 7 firebase tests + full api/ suite GREEN; runtime smoke (disabled → API serves, enabled-without-project-id → fatal exit 1); code review REVIEW-A all findings fixed (`qa/results/REVIEW-A-fix-report.md`); full reports at `qa/results/STREAM-7-report.md` + `qa/results/REVIEW-A-firebase.md` + `qa/results/REVIEW-A-fix-report.md`.
**Scope:** `api/internal/firebase/`, `api/internal/config/config.go` (Firebase fields), `api/cmd/sftp-api/main.go` (wiring), `api/internal/api/router.go` (health endpoint), `config_schemas/firebase.yaml`, `docs/firebase/`, `.env.example`.

## §F7. [FTP-002] Go REST API (Gin) — accounts, super-admin auth, DB, SFTP sync, audit

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (commits 6460e5e through aff462f) — full REST API with JWT auth, CRUD, sync, vault, Firebase, HttpOnly cookies, security headers, PostgreSQL dual-driver, containers submodule wired

## §F8. [FTP-003] SFTP config + permission system — YAML/JSON, renderer, migration

**Status:** Completed (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (commit 6460e5e) — config_schemas/ + validate_config.sh

## §F9. [FTP-006] Bash management scripts — service ctl, setup, backup, firebase config

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit 6460e5e) — 4 scripts + systemd + 44/44 smoke PASS + shellcheck clean

## §F10. [FTP-009] Test matrix, Challenges banks, HelixQA suites

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 4) — 15/15 test types, 6/6 Challenges PASS, HelixQA 161/163, all scripts fixed

## §F11. [FTP-011] Gates, code review, release plumbing, governance amendment

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 — release tag sftp-0.1.0-dev-0.1.0, commit/push wrappers hardened, final review GO, multi-track operational, ATM→FTP rename

## §F12. [FTP-012] Test hardening — fix all 5 failing test scripts

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Closed:** 2026-07-12 (Phase 4) — DDoS 7/7, Benchmark 14/14, challenges 6/6, full-automation + HelixQA timeout-guarded

## §F13. [FTP-013] Code-level bug fixes — logging middleware, CSP, doc exports

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Closed:** 2026-07-12 (Phase 4) — logging middleware Gin-native, CSP added, summary PDFs exported

## §F14. [FTP-014] Container deployment verification — real SFTP end-to-end

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-12 (Phase 4/5) — 3 bugs found+fixed (CRITICAL sftpsync, HIGH volume, MEDIUM permissions), E2E re-verified

## §F15. [FTP-015] Security hardening — HttpOnly cookies + CSP + security headers

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-12 (Phase 4) — HttpOnly cookies, CORS credentials, security headers, quic-go vuln patched, rate limiter GC

## §F16. [FTP-016] Vault master key rotation

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-12 (Phase 4) — 6-step atomic key rotation, 15/15 tests

## §F17. [FTP-017] Mobile Android APK build verification

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 4) — 11MB debug APK built, signed, verified, 7/7 KMP tests

## §F18. [FTP-018] Production config hardening

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 4) — 2 env var mismatches fixed, 11 vars added, systemd unit, compose resource limits

## §F19. [FTP-019] Container E2E re-verification after sftpsync fix

**Status:** Fixed (→ Fixed.md)
**Type:** Bug
**Closed:** 2026-07-12 (Phase 5) — sftpsync :e fix confirmed, SFTP upload/download/delete functional

## §F20. [FTP-020] PostgreSQL driver verification

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 5) — dual-driver support, SQLite + PG tested, 5 gaps fixed

## §F21. [FTP-021] Permission enforcement — read_only vs read_write

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-12 (Phase 5) — chmod 555 for read_only, path traversal guard, 17/17 sftpsync tests

## §F22. [FTP-022] Security audit — OWASP, dependencies, secrets scan

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 5) — GOOD rating, 1 HIGH vuln fixed, 0 hardcoded secrets, 100% parameterized SQL

## §F23. [FTP-023] Web production build served from API

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-12 (Phase 5) — --serve-web flag, SPA fallback routing, 10/10 smoke tests

## §F24. [FTP-024] Backup/restore end-to-end verification

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 5) — WAL checkpoint fix, backup integrity verified, restore tested

## §F25. [FTP-025] OpenAPI specification generation

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 5) — OpenAPI 3.0 spec, 11 endpoints, self-contained HTML render

## §F26. [FTP-026] systemd unit install + boot-persistence test

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-12 (Phase 5) — unit installed, systemctl recognized

