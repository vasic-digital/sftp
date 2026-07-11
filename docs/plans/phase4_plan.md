# SFTP Enterprise System — Phase 4 Plan

**Revision:** 1
**Last modified:** 2026-07-11T20:00:00Z
**Status:** active
**Prerequisite:** Release sftp-0.1.0-dev-0.1.0 (commit 9047b09)

---

## §1. Situational Analysis

### 1.1. Completed (Phase 1-3)
- Foundation: 25 submodules, env matrix, compose, go.mod, layout
- Go REST API: full CRUD, JWT auth, sync, vault, Firebase optional
- Web SPA: 4 screens, OpenDesign light/dark, i18n, 19 vitest
- Mobile KMP: Android scaffold, 7 tests, iOS/HarmonyOS/AuroraOS placeholders
- Test matrix: 15/15 test types covered, 6/6 Challenges PASS (100%), HelixQA 161/163
- Docs: user manual, admin guide, API reference, setup guide, architecture diagrams
- Multi-track: 4 tracks provisioned, heartbeats auto-renewing

### 1.2. Known Issues (from final review + manual QA + live testing)

| ID | Severity | Issue | File/Area |
|---|---|---|---|
| K1 | MEDIUM | 5 test scripts failing (ddos 1/7, benchmarking 2/14, full-auto bash error, challenges-driver FAIL, helixqa-driver bash error) | tests/ |
| K2 | LOW | API logging middleware reports 200 for 500 errors (cosmetic, logged) | api/internal/api/router.go |
| K3 | LOW | No CSP header on web SPA | web/index.html or reverse proxy |
| K4 | LOW | localStorage tokens (XSS-readable) — documented SPA tradeoff | web/src/api/client.ts |
| K5 | LOW | Vault master key rotation not implemented | api/internal/vault/vault.go |
| K6 | LOW | 4 doc summary files missing HTML+PDF exports | docs/Issues_Summary.md, Fixed_Summary.md, Status_Summary.md |
| K7 | LOW | API reference PDF missing | docs/api/api_reference.md |
| K8 | INFO | HelixQA Go binary can't build (5 deps unresolvable — honest gap) | helixqa/ |
| K9 | INFO | iOS KMP can't compile on Linux (host-limited, honest SKIP) | mobile/shared/src/iosMain/ |
| K10 | INFO | HarmonyOS/AuroraOS scaffolding only (no upstream KMP target) | mobile/shared/src/harmonyosMain/, auroraosMain/ |
| K11 | LOW | Web-screenshots HelixQA suite: 10/12 (1 selector timeout) | web/scripts/screenshots.mjs |

### 1.3. Untested Areas

| Area | Status | Risk |
|---|---|---|
| Container deployment (atmoz/sftp + podman) | NOT TESTED on this host | MEDIUM — compose exists but never `podman-compose up` verified |
| Real SFTP upload/download through container | NOT TESTED | MEDIUM — users.conf rendered but container not tested |
| Web SPA production build served from API | NOT TESTED | LOW |
| Mobile Android APK on real device | NOT TESTED | LOW |
| PostgreSQL driver (SQLite dev-only) | NOT TESTED | MEDIUM |
| Rate limiter under real concurrent load | PARTIAL (ddos test has 1 failure) | MEDIUM |

---

## §2. Phase 4 — Work Streams

### STREAM-12 (FTP-012): Test Hardening — Fix All Failing Tests [TOP]
**Priority:** TOP (blocks all validation)
**Scope:** `tests/`
**Track:** T2

1. Fix `tests/ddos/test_api_ddos.sh` — rate-limit threshold (6/7 → 7/7)
2. Fix `tests/benchmarking/test_api_benchmark.sh` — timing thresholds (12/14 → 14/14)
3. Fix `tests/full_automation/test_autonomous_qa.sh` — bash `local` error
4. Fix `tests/challenges/run_challenges.sh` — FAIL investigation
5. Fix `tests/helixqa/run_helixqa_suites.sh` — bash `local` error
6. Verify: all 14 test scripts PASS against live API
7. Capture evidence: per-script verdict + output

### STREAM-13 (FTP-013): Code-Level Bug Fixes [TOP]
**Priority:** TOP
**Scope:** `api/internal/api/router.go`, `web/index.html`, `docs/`
**Track:** T2

1. Fix logging middleware 200-for-500 (K2)
2. Add CSP header meta tag to web SPA (K3)
3. Export missing doc PDFs (K6, K7): Issues_Summary, Fixed_Summary, Status_Summary, API reference
4. Capture evidence for each fix

### STREAM-14 (FTP-014): Container Deployment Verification [MIDDLE]
**Priority:** MIDDLE
**Scope:** `deploy/`, container runtime
**Track:** T3

1. Verify `podman-compose -f deploy/docker-compose.yml config` validates
2. Start containers (atmoz/sftp): `podman-compose up -d`
3. Create test user via API, run sync, verify users.conf in container
4. Real SFTP upload/download test through container
5. Verify directory provisioning (home dirs created)
6. Permission enforcement test (RO can't write, RW can)
7. Graceful shutdown + restart persistence
8. Capture evidence: container logs + SFTP transcript

### STREAM-15 (FTP-015): Security Hardening [MIDDLE]
**Priority:** MIDDLE
**Scope:** `web/`, `api/`
**Track:** T3

1. Migrate web token storage from localStorage to HttpOnly cookies (K4)
   - Requires backend change: set cookie on /auth/login, clear on /auth/logout
   - Requires frontend change: remove localStorage, use credentials: 'include'
2. Add CSRF protection if moving to cookies
3. Security headers audit (X-Frame-Options, X-Content-Type-Options, etc.)
4. Capture evidence: browser devtools screenshot showing HttpOnly cookie

### STREAM-16 (FTP-016): Vault Key Rotation [LOW]
**Priority:** LOW
**Scope:** `api/internal/vault/`
**Track:** T2

1. Implement `Vault.RotateKey()` — re-encrypt all entries with new key
2. Add test: rotate → all entries still readable
3. Add test: old key can't decrypt after rotation
4. Add CLI command or API endpoint to trigger rotation
5. Capture evidence: test output

### STREAM-17 (FTP-017): Mobile Android Verification [LOW]
**Priority:** LOW
**Scope:** `mobile/`
**Track:** T4

1. Verify Gradle build: `./gradlew :shared:testDebugUnitTest` — 7/7 PASS
2. Build Android debug APK: `./gradlew :androidApp:assembleDebug`
3. Verify APK artifact exists and is valid
4. Document host requirements for iOS, HarmonyOS, AuroraOS
5. Capture evidence: build output + APK file info

### STREAM-18 (FTP-018): Production Config Hardening [LOW]
**Priority:** LOW
**Scope:** `.env.example`, `deploy/`, `config_schemas/`
**Track:** T4

1. Production-ready .env.example: all vars documented with safe defaults
2. PostgreSQL configuration documented and tested
3. TLS/HTTPS setup guide for the API
4. Backup automation script tested
5. Capture evidence: config validation output

---

## §3. Execution

### Track Assignment (multi-track, §11.4.187)

| Track | Alias | Phase 4 Streams |
|---|---|---|
| T1 (main) | default (conductor) | Orchestration, commit/push, reviews |
| T2 (backend) | deepseek | FTP-012 (test fixes), FTP-013 (bug fixes), FTP-016 (vault rotation) |
| T3 (clients) | claude4 | FTP-014 (container verification), FTP-015 (security hardening) |
| T4 (QA) | opencode | FTP-017 (mobile verify), FTP-018 (config hardening) |

### Priority Order (§11.4.42/§11.4.72)
1. FTP-012 (test fixes) — TOP, blocks all validation
2. FTP-013 (bug fixes) — TOP, correctness
3. FTP-014 (container) — MIDDLE, production readiness
4. FTP-015 (security) — MIDDLE
5. FTP-016 (vault rotation) — LOW
6. FTP-017 (mobile) — LOW
7. FTP-018 (config) — LOW

### Auto-Backfill (§11.4.103(B))
When any track completes its assigned stream, immediately claim the next unassigned stream from the queue. No track idles while actionable items exist (§11.4.192).
