# SFTP Enterprise System — Phase 5 Plan

**Revision:** 1
**Last modified:** 2026-07-12T00:00:00Z
**Status:** active
**Prerequisite:** Phase 4 complete (commit 15b8aff), release sftp-0.1.0-dev-0.1.0

---

## §1. Post-Phase 4 Honest Gap Analysis

### 1.1. Verified (not re-testing)
- 88 Go tests, 21 vitest, 7 KMP tests — all GREEN
- 6/6 Challenges PASS (100%)
- HelixQA 161/163 GREEN (bash execution)
- DDoS 7/7, Benchmark 14/14, Security 16/16, E2E 23/23, Performance 8/8
- sftpsync format fixed, volume mapping fixed, HttpOnly cookies shipped, vault rotation implemented

### 1.2. Honest Gaps (§11.4.6)

| ID | Gap | Severity | Risk |
|---|---|---|---|
| G1 | Container E2E never re-verified after CRITICAL sftpsync fix | HIGH | Passwords may still break in real container |
| G2 | PostgreSQL driver never tested — SQLite only | HIGH | Production DB swap would be uncharted |
| G3 | Permission enforcement not implemented (read_only==read_write at FS) | MEDIUM | Security boundary gap |
| G4 | Multi-track headless workers never launched | MEDIUM | 4 tracks exist but only as synced clones |
| G5 | Backup/restore script never tested with real data | MEDIUM | Data loss risk |
| G6 | Security audit (OWASP/dependency/go-vuln) never run | MEDIUM | Unknown vulnerability surface |
| G7 | Web production build never served from API | LOW | SPA routing may break |
| G8 | systemd units never installed/tested with systemctl --user | LOW | Boot persistence unverified |
| G9 | OpenAPI spec never generated from code | LOW | API docs manual |
| G10 | User manual screenshots are placeholder | LOW | Docs incomplete |
| G11 | HelixQA binary can't build (5 deps absent) | INFO | Honest gap, bash fallback works |
| G12 | iOS/HarmonyOS/AuroraOS host-limited | INFO | Honest SKIP |

---

## §2. Phase 5 — Work Streams

### FTP-019: Container E2E Re-Verification [TOP]
Re-run the full container deployment test after the sftpsync `:e` position fix and volume mapping fix. Verify password auth actually works through the container.
**Scope:** `deploy/`, container runtime
**Track:** T3

### FTP-020: PostgreSQL Driver Verification [TOP]
Start a PostgreSQL instance (podman or system), configure the API for pgx driver, verify all CRUD operations work identically to SQLite.
**Scope:** `api/internal/store/`, `deploy/`
**Track:** T2

### FTP-021: Permission Enforcement [MIDDLE]
Implement filesystem-level read_only enforcement: RO users get read-only bind mounts or ACLs preventing writes. At minimum, document the enforcement mechanism and add a test that proves RO user's write is denied.
**Scope:** `deploy/`, `api/internal/sftpsync/`
**Track:** T2

### FTP-022: Security Audit [MIDDLE]
Run `govulncheck ./...` on the API, `npm audit` on web, check for known CVEs in dependencies. Scan for hardcoded secrets, weak crypto, missing security headers.
**Scope:** `api/`, `web/`
**Track:** T4

### FTP-023: Web Production Build Served from API [LOW]
Build the web SPA (`npm run build`), copy to an embeddable location, serve from the API as static files with SPA fallback routing.
**Scope:** `web/`, `api/`
**Track:** T3

### FTP-024: Backup/Restore E2E Test [LOW]
Run `scripts/backup.sh` against live data, verify backup integrity, run restore, verify data matches.
**Scope:** `scripts/`, `data/`
**Track:** T4

### FTP-025: OpenAPI Spec Generation [LOW]
Generate OpenAPI 3.0 spec from Gin route annotations or hand-author from the existing API reference doc.
**Scope:** `docs/api/`, `api/`
**Track:** T4

### FTP-026: systemd Unit Install + Test [LOW]
Install `sftp-api.service` and `sftp.service` as user units, enable lingering, verify they survive reboot simulation (stop+start cycle).
**Scope:** `deploy/systemd/`
**Track:** T4

---

## §3. Execution

| Track | Alias | Streams | Priority |
|---|---|---|---|
| T1 | default (conductor) | Orchestration, commit/push, reviews | — |
| T2 | deepseek | FTP-020 (PostgreSQL), FTP-021 (permissions) | TOP→MIDDLE |
| T3 | claude4 | FTP-019 (container E2E), FTP-023 (web production) | TOP→LOW |
| T4 | opencode | FTP-022 (security audit), FTP-024 (backup), FTP-025 (OpenAPI), FTP-026 (systemd) | MIDDLE→LOW |

Auto-backfill: §11.4.103(B)/§11.4.192 — no track idles.
