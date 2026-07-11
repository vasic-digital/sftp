# SFTP Project — Fixed (closed items)

**Revision:** 3
**Last modified:** 2026-07-11T23:00:00Z

Archive of closed workable items, tracked per §11.4.19 (fixed-document column alignment) and §11.4.33 (type-aware closure vocabulary).

**Migration rule (atomic, §11.4.19):** when an item in `docs/Issues.md` reaches a terminal status — `Fixed (→ Fixed.md)` for Type `Bug`, `Implemented (→ Fixed.md)` for Type `Feature`, `Completed (→ Fixed.md)` for Type `Task`, or `Obsolete (→ Fixed.md)` per §11.4.90 — it moves into this file **in the same commit**: the heading + full body leave `Issues.md`, disappear from `docs/Issues_Summary.md` (open-only), and appear in `docs/Fixed_Summary.md` (closed-only). No item may exist in both files.

**Entry format:** every heading carries a `**Status:**` line (terminal closure value) and a `**Type:**` line (`Bug | Feature | Task`) within 8 non-blank lines, plus the evidence citation (test log / captured proof) that justified closure. Items with `reopens_count > 0` additionally carry a `docs/issues/<ATM-NNN>/Reopens.md` history per §11.4.55.

---

## §F1. [ATM-001] Infrastructure & Foundation — submodules, env, compose, go.mod, layout

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9, pushed to github+gitlab+gitflic+gitverse)

25 owned submodules staged at flat paths (§11.4.28) with `.helix-manifest.yaml` audit record (§11.4.31) + multi-upstream remotes installed in all 24 recipe-bearing submodules (§11.4.36, `open_design` third-party exempt); `.env.example` full surface; `.gitignore` matrix incl. compiled-binary class; `deploy/docker-compose.yml` (atmoz/sftp + postgres + api, rootless); `api/go.mod` Go 1.26 with `replace` directives to all 19 `digital.vasic.*` submodules; blank-import bootstrap compiles.
**Evidence:** `go build ./...` + `go vet ./...` exit 0 against all 19 real submodule packages; every blank-import path verified on disk (19/19 OK); secret scan clean (no key material; compose `POSTGRES_PASSWORD` uses `${POSTGRES_PASSWORD:-CHANGE_ME}` indirection); compose YAML parses; push log `qa-results/push/push_20260711T155549Z.log` (4/4 upstreams OK).

## §F2. [ATM-008] Design system & assets — OpenDesign, themes, asset formats

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9)

OpenDesign token set (color/typography/spacing/radius/elevation/tokens.json, light+dark) + 5 SVG assets (logo, server, user-ro, user-rw, admin) + boards/README + RENDER.md; web TS bindings (`web/src/theme/opendesign/{tokens,theme,index}.ts`); KMP bindings (`mobile/shared/.../theme/{Tokens,SftpTheme}.kt`); `open_design` submodule staged.
**Evidence:** all 6 token JSONs parse (python json.load OK); all 5 SVGs well-formed (ElementTree parse OK).

## §F3. [ATM-010] Documentation core set — guides, FAQ, tutorials, architecture, Docs Chain contexts

**Status:** Completed (→ Fixed.md)
**Type:** Task
**Closed:** 2026-07-11 (commit c5e68b9) — core set; ATM-010 remains open for per-stream doc growth.

4 guides (deployment, user-management, security, troubleshooting), FAQ, 2 tutorials (quickstart, api_quickstart), 2 architecture docs (overview, permissions_model), design manifest + READMEs, Docs Chain consumer contexts ×5 (issues/fixed/status/continuation/readme_links), script guides (commit_all, push_all), Status + Status_Summary pair.
**Evidence:** all 5 docs_chain context YAMLs parse (yaml.safe_load OK); revision headers spot-checked present on delivered docs (§11.4.44).

## §F4. [ATM-004] Web admin — React/TS SPA, OpenDesign, i18n, UI tests

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-4 DONE)

Vite + React + TS; OpenDesign tokens (light/dark); API-Client-TS, Auth-Context-React, State-Management-TS, I18n-Client-TS (en); screens: login, dashboard, account editor (permission/public toggles), audit log, settings; Testing-Utils-TS UI tests; §11.4.170 host-rendered screenshot proof per screen × {light,dark}.
**Evidence:** `npm run build` exit 0 (49 modules, tsc strict); 19/19 vitest PASS; 11 host-rendered Playwright screenshots (all routes × {light,dark}, plus public-guard state) with zero runtime errors; full report at `qa/results/STREAM-4-report.md`.
**Scope:** `web/`.

## §F5. [ATM-005] Mobile clients — KMP + Compose Multiplatform (Android/iOS/HarmonyOS/AuroraOS)

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-5 DONE, fix applied)

Gradle KMP scaffold (shared + 4 targets); Auth-KMP, Security-KMP, Config-KMP, Storage-KMP; in-project KMP i18n + HTTP client (I18n-KMP/Network-KMP do not exist — honest in-project scope per §11.4.6); debug/release variants; Firebase config placeholders; 20 .kt files across commonMain (13), androidMain (3), iosMain (3), harmonyosMain (0: honest SKIP per §11.4.3), auroraosMain (0: honest SKIP per §11.4.3), commonTest (1).
**Evidence:** Fix applied — TokenStorage interface extraction resolved final-class subclassing error per `qa/results/STREAM-5-fix-report.md`; `compileDebugKotlinAndroid` exit 0; 7/7 tests PASS ×2 deterministic consistency (§11.4.50); full reports at `qa/results/STREAM-5-report.md` + `qa/results/STREAM-5-fix-report.md`.
**Scope:** `mobile/`.

## §F6. [ATM-007] Firebase integration — Admin SDK, config, graceful degrade, fail-fast

**Status:** Implemented (→ Fixed.md)
**Type:** Feature
**Closed:** 2026-07-11 (STREAM-7 DONE + REVIEW-A fix applied)

Firebase Admin SDK v4.21.0 optional subsystem: disabled-by-default (`FIREBASE_ENABLED=false`), fail-fast on misconfiguration (clear actionable error naming the exact env var or path), graceful degrade when disabled (all hooks safe no-ops). Wired into `/api/v1/health` endpoint reporting Firebase status (`disabled`/`connected`/`unhealthy`). Code review REVIEW-A: 7 findings (1 HIGH, 2 MEDIUM, 4 LOW) all remediated with captured evidence.
**Evidence:** `go build ./...` + `go vet ./...` exit 0; 7 firebase tests + full api/ suite GREEN; runtime smoke (disabled → API serves, enabled-without-project-id → fatal exit 1); code review REVIEW-A all findings fixed (`qa/results/REVIEW-A-fix-report.md`); full reports at `qa/results/STREAM-7-report.md` + `qa/results/REVIEW-A-firebase.md` + `qa/results/REVIEW-A-fix-report.md`.
**Scope:** `api/internal/firebase/`, `api/internal/config/config.go` (Firebase fields), `api/cmd/sftp-api/main.go` (wiring), `api/internal/api/router.go` (health endpoint), `config_schemas/firebase.yaml`, `docs/firebase/`, `.env.example`.
