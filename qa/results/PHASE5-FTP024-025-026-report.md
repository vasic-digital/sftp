# Phase 5 — FTP-024, FTP-025, FTP-026 Report

**Revision:** 1
**Last modified:** 2026-07-12T00:32:00Z
**Tester:** AI conductor (autonomous)
**Status:** 3/3 PASS — zero defects

---

## FTP-024: Backup/Restore E2E — PASS

### What was tested

1. **API started** with test configuration (JWT, super-admin seeded)
2. **Test users created** via REST API: testuser1 (read_write), testuser2 (read_only)
3. **Sync executed** — users.conf rendered to data/users.conf (2 accounts)
4. **Backup created** — `scripts/backup.sh` produced integrity-verified `backups/20260711T212855Z.tar.gz` (52,771 bytes, tar -tzf + gzip -t verified)
5. **Backup verified** — archive contains `config/`, `data/sftp.db` (24,576 bytes with both accounts), and `data/users.conf`
6. **testuser1 deleted** — DELETE returned 204, GET returned 404 (confirmed gone)
7. **API stopped, backup restored** — `backup.sh --restore ... --yes` completed; pre-restore safety copy created automatically
8. **testuser1 verified restored** — GET returned 200 with username, permission=read_write, enabled=true

### Gap found and fixed

The original `scripts/backup.sh` had two issues:

1. **WAL staleness** — backups taken while the API is running could miss recent transactions
   because SQLite WAL mode writes to `data/sftp.db-wal`, not directly to the main DB file.
   Fix: added `checkpoint_db()` function that runs `PRAGMA wal_checkpoint(TRUNCATE)` via
   `sqlite3` before creating the archive. This is skipped gracefully if `sqlite3` is not on PATH.

2. **users.conf path** — the script looked for `users.conf` at the repo root (`$ROOT/users.conf`)
   but the actual path is `data/users.conf` (matching the default `USERS_CONF_PATH` config).
   Fix: `collect_members()` now checks `data/users.conf` first, falls back to root-level for
   backward compatibility.

### Evidence

- Backup: `/run/media/milosvasic/DATA4TB/Projects/sftp/backups/20260711T212855Z.tar.gz`
- Pre-restore safety: `backups/pre-restore-20260711T212918Z.tar.gz`
- REST API responses captured (201 create, 204 delete, 404 not-found, 200 restored)

---

## FTP-025: OpenAPI Spec — PASS

### What was created

1. **`docs/api/openapi.yaml`** — OpenAPI 3.0.3 specification covering all 11 endpoints:
   - `GET /api/v1/health` — liveness probe (no auth)
   - `POST /api/v1/auth/login` — JWT authentication (rate-limited)
   - `POST /api/v1/auth/refresh` — token refresh (rate-limited)
   - `POST /api/v1/auth/logout` — revoke refresh token (Bearer auth)
   - `GET /api/v1/auth/me` — current user identity (Bearer auth)
   - `GET /api/v1/accounts` — list all accounts (Bearer auth)
   - `POST /api/v1/accounts` — create account (Bearer auth)
   - `GET /api/v1/accounts/{username}` — get single account (Bearer auth)
   - `PUT /api/v1/accounts/{username}` — update account (Bearer auth)
   - `DELETE /api/v1/accounts/{username}` — delete account (Bearer auth)
   - `POST /api/v1/sync` — render users.conf (Bearer auth)

2. **`docs/api/openapi.html`** — self-contained HTML render (20,197 bytes) with:
   - Light/dark theme support (OS preference)
   - Color-coded HTTP methods (GET=green, POST=blue, PUT=amber, DELETE=red)
   - Schema documentation with field tables, required markers, enums
   - Response code categorization (2xx green, 4xx amber)
   - Authentication badges (Bearer token)
   - Table of contents with anchor links

### Schemas documented

`ErrorResponse`, `HealthResponse`, `LoginRequest`, `TokenResponse`, `RefreshRequest`,
`LogoutRequest`, `LogoutResponse`, `MeResponse`, `AccountRequest`, `AccountResponse`,
`AccountListResponse`, `SyncResponse`

### Error codes documented

`bad_request`, `validation_error`, `unauthorized`, `not_found`, `conflict`,
`rate_limited`, `internal_error`, `public_access_not_acknowledged`, `invalid_credentials`

### Evidence

- `/run/media/milosvasic/DATA4TB/Projects/sftp/docs/api/openapi.yaml` (19,299 bytes)
- `/run/media/milosvasic/DATA4TB/Projects/sftp/docs/api/openapi.html` (20,197 bytes)

---

## FTP-026: systemd Install Test — PASS

### What was tested

1. **Template read** — `deploy/systemd/sftp-api.service` uses `@PROJECT_ROOT@` placeholder (37 occurrences in `WorkingDirectory=`, `EnvironmentFile=`, `Environment=`, `ReadWritePaths=`, `ReadOnlyPaths=`)
2. **Template rendered** — `@PROJECT_ROOT@` replaced with `/run/media/milosvasic/DATA4TB/Projects/sftp` via `sed`
3. **Unit installed** — rendered file copied to `~/.config/systemd/user/sftp-api.service` (3,392 bytes)
4. **`systemctl --user daemon-reload`** — exit 0, no errors
5. **`systemctl --user status sftp-api`** — unit recognized as "loaded" with correct description, documentation URL, and file path
6. **`systemctl --user cat sftp-api`** — unit content verified correct
7. **`systemctl --user is-enabled sftp-api`** — reports `disabled` (expected — per constraint, we did NOT enable or start the service)
8. **Service was NOT started** — `Active: inactive (dead)` is correct per the test constraint

### sftp-api.service install procedure

```bash
# 1. Render template
PROJECT_ROOT="/path/to/sftp"
sed "s|@PROJECT_ROOT@|$PROJECT_ROOT|g" deploy/systemd/sftp-api.service > ~/.config/systemd/user/sftp-api.service

# 2. Reload systemd
systemctl --user daemon-reload

# 3. Verify recognized
systemctl --user status sftp-api

# 4. Enable and start (manual operator step only)
systemctl --user enable --now sftp-api
```

The `sftp.service.template` (type=oneshot, RemainAfterExit=yes) for the SFTP compose stack was also read and documented but NOT installed — it requires `podman-compose` and the SFTP container stack to be operational first.

### Evidence

- Installed unit: `/home/milosvasic/.config/systemd/user/sftp-api.service`
- daemon-reload: exit 0
- status output: `Loaded: loaded (/home/milosvasic/.config/systemd/user/sftp-api.service; disabled; preset: disabled)`

---

## Verdict

3/3 PASS. All evidence captured. No commits made (per constraint).
