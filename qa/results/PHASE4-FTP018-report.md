# PHASE4-FTP018: Production Config Hardening

**Revision:** 1
**Last modified:** 2026-07-11T23:30:00Z
**Status:** PASS
**Scope:** `.env.example`, `config_schemas/`, `deploy/systemd/`, `deploy/docker-compose.yml`

---

## 1. .env.example — Full audit and rewrite

### 1.1 Name mismatches FIXED

Two legacy variable names in `.env.example` did NOT match what `api/internal/config/config.go` `applyEnv()` actually reads. These are corrected:

| Old (broken) | New (canonical) | config.go `getenv()` call |
|---|---|---|
| `JWT_TTL=24h` | `ACCESS_TOKEN_TTL=15m` | `getenv("ACCESS_TOKEN_TTL")` |
| `SUPERADMIN_USER=admin` | `SUPERADMIN_USERNAME=admin` | `getenv("SUPERADMIN_USERNAME")` |

The old names were never consumed by the Go code — the `JWT_TTL` env var was simply ignored, and the API used the hardcoded default `15m` for access tokens. Challenge scripts (`qa/challenges/scripts/ch_sftp_*.sh`) already used the correct names (`ACCESS_TOKEN_TTL`, `SUPERADMIN_USERNAME`), confirming the fix is consistent with the test infrastructure.

### 1.2 Missing env vars ADDED

The following variables consumed by `config.go` `applyEnv()` had NO entry in the old `.env.example`:

| Variable | Default | config.go line |
|---|---|---|
| `ACCESS_TOKEN_TTL` | `15m` | L140 |
| `REFRESH_TOKEN_TTL` | `168h` | L145 |
| `SUPERADMIN_USERNAME` | `admin` | L150 |
| `SUPERADMIN_PASSWORD` | — (required) | L153 |
| `API_VERSION` | `0.1.0-dev` | L156 |
| `API_TEST_MODE` | `false` | L159 |
| `LOGIN_RATE_LIMIT` | `10` | L162 |
| `LOGIN_RATE_WINDOW` | `1m` | L168 |
| `VAULT_DATA_DIR` | `data/vault` | L182 |
| `API_CORS_ORIGIN` | — (empty = no CORS) | L185 |
| `USERS_CONF_PATH` | `data/users.conf` | L134 |

All 18 `applyEnv()`-consumed variables are now present and documented.

### 1.3 Env vars present but NOT consumed by config.go — documented

The following variables were kept because they are consumed by `docker-compose`, setup scripts, or challenge infrastructure. Each is now marked with its actual consumer:

| Variable | Consumer |
|---|---|
| `SFTP_*` (PORT, IMAGE, CONTAINER_NAME, DATA_DIR, USERS_CONF) | `deploy/docker-compose.yml` only |
| `API_CONTAINER_NAME` | `deploy/docker-compose.yml` only (added — was missing) |
| `POSTGRES_*` (CONTAINER_NAME, DB, USER, PASSWORD) | `deploy/docker-compose.yml` only |
| `API_CONFIG` | `config.go` `Load()` (L93), NOT `applyEnv()` |
| `DB_DRIVER`, `DB_DSN` | RESERVED — future Postgres support; exported by challenge scripts |
| `JWT_ISSUER` | RESERVED — current Go `authn` hardcodes `"sftp-api"` (L111); exported by challenge scripts |
| `API_LOG_LEVEL` | RESERVED — exported by challenge scripts; not yet wired into Go config |
| `I18N_DEFAULT_LANG` | RESERVED — exported by challenge scripts; not yet wired into Go config |
| `FIREBASE_WEB_APP_ID` | `scripts/firebase_config.sh` only |
| `HELIX_RELEASE_PREFIX` | Release tag naming (§11.4.151) |

### 1.4 Production checklist ADDED

A 16-item production checklist (§11.4.108 runtime-signature) was added to the top of `.env.example`. Every item requires captured evidence (log output, `ss -tlnp`, `curl` health check, `find` permissions audit). A bare "defaults should be fine" claim is explicitly called out as a §11.4 PASS-bluff.

Evidence: `.env.example` lines 20-53.

---

## 2. deploy/systemd/sftp-api.service — CREATED

A new `systemd --user` unit was created at:
`/run/media/milosvasic/DATA4TB/Projects/sftp/deploy/systemd/sftp-api.service`

Key properties:

| Property | Value | Rationale |
|---|---|---|
| `Type` | `simple` | API is a long-running foreground process |
| `WorkingDirectory` | `@PROJECT_ROOT@` | Template variable, rendered by `sftp_ctl.sh` |
| `EnvironmentFile` | `@PROJECT_ROOT@/.env` | Loads secrets (§11.4.10) |
| `ExecStart` | `/usr/local/bin/sftp-api` | Go binary, pure-Go static build |
| `Restart` | `always` | Crash resilience; `RestartSec=2` backoff |
| `NoNewPrivileges` | `yes` | Security hardening |
| `ProtectSystem` | `strict` | Read-only filesystem except data dirs |
| `MemoryMax` | `512M` | Conservative ceiling; tune per host |
| `CPUQuota` | `200%` | Two full cores max |
| `SyslogIdentifier` | `sftp-api` | journald structured logging |

The unit follows the same `@PROJECT_ROOT@` template convention as the existing `deploy/systemd/sftp.service.template`. It runs the API binary DIRECTLY (not containerized) for minimal overhead, while the SFTP/Postgres containers are managed by the compose-stack unit.

---

## 3. deploy/docker-compose.yml — Production hardening

### 3.1 Added: dedicated network

```yaml
networks:
  sftp_net:
    driver: bridge
    internal: false
```

All three services (`sftp`, `postgres`, `api`) are now attached to `sftp_net`. Service-to-service traffic stays on the internal bridge; the host can still reach services (ports are published). To lock down to pure-internal, set `internal: true`.

### 3.2 Added: resource limits

| Service | `mem_limit` | `cpus` |
|---|---|---|
| `sftp` | 256m | 1.0 |
| `postgres` | 512m | 1.0 |
| `api` | 256m | 0.5 |

These are conservative defaults — tune per host workload. Without limits, a runaway process in one container can exhaust the host's memory and trigger the OOM killer unpredictably.

### 3.3 Added: logging configuration

```yaml
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

Applied to all three services. Prevents unbounded disk growth from container logs (default json-file driver has no rotation).

### 3.4 Added: API_CONTAINER_NAME and POSTGRES_CONTAINER_NAME to .env.example

These compose interpolation variables (`${API_CONTAINER_NAME:-sftp_api}`, `${POSTGRES_CONTAINER_NAME:-sftp_postgres}`) were previously only in `docker-compose.yml` with hardcoded defaults. They are now exposed in `.env.example` so operators can customize container names.

---

## 4. Port consistency audit

Every non-`docs/research/`, non-`qa/results/` reference in the project uses:
- **7721** for SFTP (maps to container sshd `:22`)
- **7722** for REST API

Files verified: `CLAUDE.md`, `.env.example`, `config_schemas/server.yaml`, `deploy/docker-compose.yml`, `deploy/systemd/sftp-api.service`, `api/Dockerfile`, `api/internal/config/config.go`, `api/README.md`, `docs/Status.md`, `docs/architecture/overview.md`, `docs/faq/faq.md`, `docs/guides/admin_guide.md`, `docs/guides/deployment_guide.md`, `docs/guides/quick_setup_guide.md`, `docs/guides/security_guide.md`, `docs/guides/troubleshooting_guide.md`, `docs/guides/user_management_guide.md`, `docs/guides/user_manual.md`, `docs/plans/master_implementation_plan.md`, `docs/scripts/sftp_ctl.md`, `docs/tutorials/api_quickstart.md`, `docs/tutorials/quickstart.md`, `scripts/sftp_ctl.sh`, `qa/challenges/sftp_challenges.yaml`, `qa/challenges/scripts/ch_sftp_*.sh`, `web/vite.config.ts`.

Zero inconsistencies found. All references use 7721 for SFTP and 7722 for API.

---

## 5. Build verification

```
=== VET: PASS ===
=== BUILD: PASS ===
```

Command: `cd api && go vet ./... && go build -o /dev/null ./cmd/sftp-api/`

Go 1.26, pure-Go static build (modernc.org/sqlite, CGO_ENABLED=0). No vet warnings, no build errors.

---

## 6. Summary of changes

| File | Action | Key changes |
|---|---|---|
| `.env.example` | REWRITTEN | Fixed 2 name mismatches (JWT_TTL→ACCESS_TOKEN_TTL, SUPERADMIN_USER→SUPERADMIN_USERNAME); added 11 missing config.go vars; added 2 missing compose vars; documented consumer for every var; added 16-item production checklist |
| `deploy/systemd/sftp-api.service` | CREATED | Standalone `systemd --user` unit for the Go API binary with security hardening, resource limits, and journald logging |
| `deploy/docker-compose.yml` | UPDATED | Added dedicated network (`sftp_net`), resource limits (mem_limit+cpus) on all 3 services, JSON-file log rotation (10m/3), documented podman-compose health-check compatibility requirement |
| `qa/results/PHASE4-FTP018-report.md` | CREATED | This evidence report |

**No commits were made** (per constraint: "NEVER commit").

---

## 7. Anti-bluff posture (§11.4)

- Every variable name was cross-referenced against the actual `getenv()` call in `config.go` — no guessing, no "probably the same."
- Port consistency was verified with a project-wide `grep` excluding only `docs/research/` (foreign MVP reference material).
- Build verification produces a clean `go vet` + `go build` — zero warnings, zero errors.
- The production checklist explicitly requires captured evidence for every item (§11.4.5, §11.4.69, §11.4.108) — a checklist claim without proof is a §11.4 PASS-bluff.
- `SUPERADMIN_PASSWORD` and `JWT_SECRET` are marked as REQUIRED with no insecure defaults — the API refuses to start without them in non-test mode (`config.go` `Validate()` L219-226).
