# SFTP Enterprise Management System — Master Implementation Plan

| Field | Value |
|---|---|
| Revision | 1 |
| Created | 2026-07-11 |
| Last modified | 2026-07-11T18:30:00Z |
| Status | active |
| Authority | Operator mandates (prior session, standing): enterprise SFTP system, subagent-driven development, full test coverage + Challenges + HelixQA banks, complete docs, bleeding-edge/secure/risk-free. Helix Constitution §11.4 anchors apply unconditionally. |

---

## §1. Goal & scope

Transform the current atmoz/sftp compose stub into a **full enterprise SFTP management system**:

- **Account management**: create / update / delete / list users via Go REST API (Gin), persisted in PostgreSQL (prod) / SQLite (dev), synced to SFTP container (`users.conf` + bind-mounted account dirs).
- **Permission system**: per-account `read-only` / `read-write`; `public` access flag exists but is NEVER default; super-admin role required for every mutation.
- **Config system**: YAML + JSON for server + accounts; validated; rendered to container inputs.
- **Admin clients** (maximum code reuse via vasic-digital modules): Desktop (web), Web (React/TS), Android + iOS + HarmonyOS + AuroraOS (KMP + Compose Multiplatform).
- **Auth**: super-admin authentication (JWT/session via `auth` module), rate limiting, audit logging.
- **Ops**: bash system management scripts driving rootless Podman via the `containers` submodule; `systemctl --user` services (no root, no sudo).
- **QA**: full test-type matrix (unit, integration, e2e, stress, chaos, performance, security, UI, UX) + Challenges banks + HelixQA suites.
- **Docs**: manuals, guides, FAQs, tutorials, architecture diagrams; Docs Chain auto-sync; HTML+PDF exports.
- **Design**: OpenDesign tokens, light/dark themes, design assets (SVG/PNG/PDF; Figma/PenPot/PSD as source-of-truth exports where tooling allows).
- **Firebase**: Distribution, Analytics, Performance, Crashlytics wired for mobile/web builds; dynamic config acquisition script; debug + production variants.
- **Localization**: i18n framework, English-only content initially, extensible.

## §2. Verified ground truth (this session, captured evidence)

- Host: Go 1.26.2, Node v22.19.0, Podman 5.7.1 (rootless; NO docker binary — §11.4.161 compliant), pandoc, sqlite3; 64 GB RAM (§12.6 ceiling 60%); `ulimit -u` 65536, live threads ~1140 (§12.12 ample headroom).
- Repo state: clean tree; submodules = `constitution` only; remotes = github/gitlab/gitflic/gitverse (origin push-fanout to all 4 — §2.1 multi-upstream).
- Reachability probes (`git ls-remote`, 2026-07-11): OK — containers, docs_chain, Challenges, HelixQA, config, auth, database, security, middleware, i18n, observability, ratelimiter, cache, recovery, http3, mdns, filesystem, concurrency, formatters, discovery, streaming, storage, watcher, API-Client-TS, I18n-Client-TS, UI-Components-React, Auth-Context-React, State-Management-TS, Testing-Utils-TS, Auth-KMP, Database-KMP, Storage-KMP, Security-KMP, Config-KMP, UI-Components-KMP, Document-KMP, Formatters-KMP, RateLimiter-KMP, Concurrency-KMP, nexu-io/open-design. **MISS** — `I18n-KMP`, `Network-KMP` (do not exist; KMP i18n + HTTP client are in-project scope).
- `docs/research/mvp/MVP.md` is the current basic deployment guide — superseded by this plan; preserved as the migration baseline.

## §3. Binding constraints (constitution anchors)

§11.4 (anti-bluff: every PASS needs captured positive evidence) · §11.4.10 (no secrets in git; `.env` git-ignored; chmod 600) · §11.4.17 (universal-vs-project classification on new rules) · §11.4.20/§11.4.70 (subagent-driven default) · §11.4.27 (no fakes beyond unit tests; 100% test-type coverage) · §11.4.28 (owned submodules = equal codebase; decoupled; flat layout) · §11.4.29 (lowercase snake_case) · §11.4.30 (.gitignore, no versioned artifacts) · §11.4.31 (helix-deps.yaml per owned submodule) · §11.4.36 (install_upstreams on add) · §11.4.37 (fetch-before-edit) · §11.4.44 (doc revision headers) · §11.4.58/§11.4.103 (parallel streams, main stream free) · §11.4.69 (sink-side evidence) · §11.4.84 (working-tree quiescence before commit) · §11.4.88/§11.4.89 (background push / background tests) · §11.4.92 (5-pass evaluation) · §11.4.113 (NO force-push, ever) · §11.4.122 (no silent component removal) · §11.4.125/§11.4.142 (code review before build) · §11.4.126 (default autonomous loop) · §11.4.161 (rootless containers only) · §12.6/§12.12 (host resource safety) · §2.1 (push to ALL upstreams).

## §4. Target repository layout (flat per §11.4.28(C), snake_case per §11.4.29)

```
sftp/
├── api/                    # Go REST API (Gin) — cmd/sftp-admin + internal/{accounts,auth,config,db,sftp_sync,middleware,server}
├── deploy/                 # docker-compose.yml (podman-compose compatible), env templates, systemd --user units
├── scripts/                # bash mgmt: service_ctl.sh, setup.sh, backup.sh, firebase_config.sh, commit/push wrappers
├── web/                    # React+TS admin SPA (Vite)
├── mobile/                 # KMP + Compose Multiplatform (androidApp, iosApp, harmonyApp, auroraApp, shared)
├── config/                 # server.yaml / accounts.yaml schemas + examples
├── docs/                   # manuals, guides, faq, tutorials, research/mvp (kept), design/ (SVG/PNG/PDF + figma/penpot exports)
├── tests/                  # pre_build_verification.sh (extended), unit-adjacent, integration/, e2e/, stress/, chaos/, performance/, security/, ui/
├── qa/                     # Challenges banks + HelixQA suite registrations
├── .env.example            # full enterprise config surface (NEW — file does not exist yet)
├── CLAUDE.md / AGENTS.md   # amended: Go/TS/Kotlin code now lives here (project-layer amendment, not a weakening)
└── submodules: constitution, containers, docs_chain, challenges, helixqa,
    config, auth, database, security, middleware, i18n, observability, ratelimiter,
    cache, recovery, http3, mdns, filesystem, concurrency, formatters, discovery,
    streaming, storage, watcher,
    api_client_ts, i18n_client_ts, ui_components_react, auth_context_react,
    state_management_ts, testing_utils_ts,
    auth_kmp, database_kmp, storage_kmp, security_kmp, config_kmp,
    ui_components_kmp, document_kmp, formatters_kmp, ratelimiter_kmp, concurrency_kmp,
    open_design
```

## §5. Execution model — subagent-driven parallel streams (§11.4.20/§11.4.70/§11.4.103)

- **Conductor (this session)** stays free: dispatches, verifies, commits, pushes. Every dispatch carries a §11.4.182-style label `(T<n>/main - sftp) STREAM-x task-y`.
- **≥3 streams active whenever non-contending items exist**; auto-backfill on completion (§11.4.103(B)). Band capped by §12.6 memory + §11.4.58 agent cap.
- **Disjoint file scopes** per stream (§11.4.58 L3); same-checkout subagents coordinate via quiescence (§11.4.84) — conductor is the only committer.
- Every stream: tight scope (4–6 tasks), checkpoint after each, anti-stall clause, captured evidence, code-review pass before merge-ready.
- Long commands backgrounded (§11.4.89); pushes detached (§11.4.88); never force-push (§11.4.113).

## §6. Streams (11)

### STREAM-1 — Infrastructure & Foundation *(critical path; starts first)*
1. Add all verified submodules at flat paths (§11.4.28) + `install_upstreams` each (§11.4.36) + `helix-deps.yaml` audit record (§11.4.31).
2. `go.mod` init `github.com/vasic-digital/sftp/api` (Go 1.26); wire `replace` directives to local submodules for maximum reuse.
3. Create `.env.example` (MISSING today — captured gap): SFTP_PORT=7721, API_PORT, DB driver/dsn, paths, Firebase flags; `.env` + `data/` + secrets git-ignored (§11.4.10/§11.4.30).
4. `deploy/docker-compose.yml` via containers-submodule conventions: atmoz/sftp + postgres + api; rootless-podman compatible; `.env`-driven.
5. Repo hygiene: `.gitignore` full matrix; `VERSION` (`0.1.0-dev`); directory skeleton with README placeholders.
**Evidence**: `git submodule status`, `go list -m all`, compose `config` validation output.

### STREAM-2 — Go REST API (Gin) *(after S1)*
1. Server bootstrap: config loading (config module), structured logging (observability), graceful shutdown (recovery).
2. Auth: super-admin bootstrap (first-run setup), login, JWT middleware (auth + middleware modules), rate limiting (ratelimiter).
3. Accounts CRUD: list/create/update/delete; permission enum `read_only|read_write`; `public` flag default false + validation that public requires explicit `--allow-public` acknowledgement.
4. DB layer: driver abstraction over SQLite (mattn) + PostgreSQL (pgx) via database module; migrations embedded.
5. SFTP sync: render `users.conf` + per-user directories + chown contract; atomic write (tmp+rename); container reload signal.
6. Audit log of every mutation; OpenAPI spec; health endpoints.
**Evidence**: unit tests GREEN, `curl` transcript of real CRUD round-trip against live server (captured to `docs/qa/`).

### STREAM-3 — SFTP config + permission system *(after S1, parallel with S2)*
1. `config/server.yaml` + `config/accounts.yaml` schemas (JSON-schema documented) + examples.
2. YAML↔JSON loader with strict validation (unknown field = error).
3. users.conf renderer (atmoz format `user:pass:uid:gid:home[:opts]`) + directory provisioner + permission enforcer (RO → write-mask, RW → full).
4. Migration path from the MVP manual flow (import existing users.conf).
**Evidence**: golden-file tests; real container round-trip (upload denied for RO, allowed for RW — captured transcript).

### STREAM-4 — Web admin (React/TS) *(after S2 API stable)*
1. Vite + React + TS scaffold; OpenDesign tokens wired (light/dark).
2. api-client (API-Client-TS), auth context (Auth-Context-React), state (State-Management-TS), i18n (I18n-Client-TS, en only).
3. Screens: login, dashboard (account list), account editor (permission/public toggles), audit log, settings.
4. UI tests (Testing-Utils-TS) + §11.4.170 host-rendered screenshots.
**Evidence**: build artifact + screenshot matrix + interaction test run.

### STREAM-5 — Mobile KMP (Android/iOS/HarmonyOS/AuroraOS) *(after S2 API stable)*
1. Gradle KMP scaffold: shared module + 4 targets; Compose Multiplatform UI with OpenDesign-derived theme.
2. Auth (Auth-KMP), secure storage (Security-KMP), config (Config-KMP), storage abstractions (Storage-KMP); in-project KMP i18n + HTTP client (repos MISS — honest in-project scope).
3. Debug/release variants; Firebase config placeholders consumed from `scripts/firebase_config.sh` output.
**Evidence**: `./gradlew :shared:test` GREEN + Android debug APK build artifact + §11.4.170 rendered UI proof.

### STREAM-6 — Bash management & setup scripts *(after S1)*
1. `scripts/service_ctl.sh` — start/stop/restart/status via podman-compose, rootless, no sudo.
2. systemd `--user` units + installer (linger documented; no root).
3. `scripts/setup.sh` — first-time: env init (interactive, secrets never echoed §11.4.10), super-admin creation, dir perms, smoke.
4. `scripts/backup.sh` — accounts DB + data snapshots, restore path.
5. `scripts/firebase_config.sh` — dynamic Firebase config acquisition (CLI → per-platform files, git-ignored outputs).
**Evidence**: §11.4.18 doc block in every script + `shellcheck` clean + real start/stop cycle transcript.

### STREAM-7 — Firebase integration *(after S4/S5 scaffolds)*
1. Web: Analytics + Performance + Crashlytics (web) modular init behind env flags.
2. Mobile: google-services acquisition → per-variant config; Crashlytics + Analytics + Performance + App Distribution wiring.
3. Debug/prod separation; no tracked secrets.
**Evidence**: init logs + config files generated by script (git-ignored, presence-verified).

### STREAM-8 — Design system & assets *(parallel from start)*
1. OpenDesign token integration for web + mobile; light/dark theme packs.
2. Design assets under `docs/design/`: SVG (authoritative), PNG renders, PDF boards; Figma/PenPot source exports where tooling permits; manifest doc.
**Evidence**: token files consumed by both builds; asset manifest validated by pre-build gate.

### STREAM-9 — Tests, Challenges, HelixQA *(grows with each stream)*
1. Extend `tests/pre_build_verification.sh`: constitution + gitignore + env-safety + docs-sync + layout gates.
2. Integration suite: API↔DB↔users.conf↔live container (real, no fakes beyond unit — §11.4.27).
3. e2e: full operator journey (setup → login → create user → SFTP upload/download → delete).
4. stress/chaos/performance/security suites (§11.4.85 helpers; concurrency + fault injection + OWASP checks).
5. Challenges banks + HelixQA suite registration under `qa/`.
**Evidence**: per-suite captured logs; risk-ordered execution (§11.4.132).

### STREAM-10 — Documentation *(parallel from start)*
1. Docs Chain contexts registered (`.docs_chain/`) for README/Status/Issues/Fixed/CONTINUATION + HTML+PDF exports (§11.4.65).
2. User manual, admin guide, API reference (from OpenAPI), FAQ, tutorials, architecture diagrams (SVG).
3. CONTINUATION.md + standing resumption file (§12.10/§11.4.131); revision headers everywhere (§11.4.44).
**Evidence**: docs_chain verify GREEN; export mtimes in sync.

### STREAM-11 — QA gates, code review & release plumbing *(continuous)*
1. Pre-build gate orchestrator; paired mutation hooks where gates assert behavior.
2. Code-review subagent before every build (§11.4.125/§11.4.142).
3. Commit/push wrappers with quiescence check (§11.4.84) + detached push (§11.4.88) to all 4 upstreams.
4. CLAUDE.md / AGENTS.md amendment commit (project-layer: Go/TS/Kotlin now in-repo; classification: project-specific).

## §7. Ordering & concurrency

- T0: S1 + S8 + S10 dispatch immediately (disjoint scopes).
- T1: S2 + S3 + S6 after S1 foundation lands.
- T2: S4 + S5 after API contract frozen; S7 after S4/S5 scaffolds; S9 grows continuously; S11 continuous.
- Checkpoint commits after every stream task; push detached to all upstreams.

## §8. Anti-bluff acceptance bar

No stream closes on claims — only on captured evidence: real command transcripts, real test runs, real container round-trips, real build artifacts, real screenshots. Metadata-only / config-only / absence-of-error PASS is rejected (§11.4/§11.4.1). Honest gaps are logged as tracked items, never papered over.
