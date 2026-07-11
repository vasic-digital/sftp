# POSTGRES-FIX: SFTP Store Layer PostgreSQL Support

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-12T00:00:00Z |
| **Status** | PASS -- all 5 gaps fixed |
| **Author** | Claude (subagent) |
| **Scope** | `api/internal/store/`, `api/internal/config/`, `api/cmd/sftp-api/` |

---

## 1. Summary

All 5 PostgreSQL gaps identified by Phase 5 FTP-020 are fixed. The SFTP store
layer now supports both SQLite and PostgreSQL via the `database.Database`
interface from `digital.vasic.database`. 15 SQLite tests + 1 PG integration
test all PASS. `go vet ./...` and `go build` are clean.

## 2. Changes Made

### Gap A: Store uses `database.Database` interface

**File:** `api/internal/store/store.go`

- `Store.client` changed from `*sqlite.Client` to `database.Database`
- `Store` struct gains `dialect *dialect.Dialect` and `driver string` fields
- `Open()` signature: `(ctx, driver, dsn string)` -- driver-aware constructor
- `openSQLite()` and `openPostgres()` helper functions handle driver-specific
  client creation
- `applyDSN()` parses PostgreSQL connection URLs via `net/url`

### Gap B: Placeholder syntax (`?` -> `$N`)

**File:** `api/internal/store/store.go`

- `rewriteQuery(query)` method calls `dialect.RewritePlaceholders()` which
  converts `?` to `$1,$2,...` for PostgreSQL (SQLite queries pass through unchanged)
- All 10 query strings in the store pass through `rewriteQuery()`
- Uses the existing `digital.vasic.database/pkg/dialect` package (no ad-hoc rewriting)

### Gap C: PG-aware `isUniqueViolation()`

**File:** `api/internal/store/store.go`

- Checks for `*pgconn.PgError{Code: "23505"}` (unique_violation) via `errors.As()`
- Retains existing SQLite text-pattern detection
- Imports `github.com/jackc/pgx/v5/pgconn` for the error type

### Gap D: Config fields

**File:** `api/internal/config/config.go`

- Added `DBDriver string` (env: `DB_DRIVER`, values: `sqlite`/`postgres`)
- Added `DBDSN string` (env: `DB_DSN`, PostgreSQL connection URL)
- `Validate()` updated: requires either DBPath (SQLite) or DBDSN (PG)
- `Validate()` rejects unknown driver values
- `main.go` resolves DSN: uses `DB_DSN` when driver is `postgres`, `DBPath` otherwise

### Gap E: Per-driver DDL migrations

**File:** `api/internal/store/store.go`

- `sqliteMigrations` -- original SQLite DDL (INTEGER uid/gid, TEXT timestamps)
- `postgresMigrations` -- PostgreSQL DDL (BIGINT uid/gid, TIMESTAMPTZ with DEFAULT NOW())
- `driverMigrations()` returns the correct set based on active dialect
- Timestamp handling: `formatTimestamp()` returns `time.Time` for PG, RFC3339Nano string for SQLite
- Scanning: `parseTimestamp()` handles both `time.Time` (pgx) and `string` (SQLite) via type-switch
- `scanAccount` scans timestamps into `any` instead of `string`

## 3. Verification

### 3.1 SQLite baseline (all tests PASS)

```
$ go test -count=1 -v ./internal/store/
=== RUN   TestCreateAndGetAccount          --- PASS
=== RUN   TestCreateDuplicateUsernameRejected --- PASS
=== RUN   TestGetMissingAccount            --- PASS
=== RUN   TestListAccountsOrdered          --- PASS
=== RUN   TestUpdateAccount               --- PASS
=== RUN   TestUpdateMissingAccount        --- PASS
=== RUN   TestDeleteAccount               --- PASS
=== RUN   TestDeleteMissingAccount        --- PASS
=== RUN   TestAccountValidation           --- PASS
=== RUN   TestNilUIDGIDRoundTrip           --- PASS
=== RUN   TestSeedAndGetAdmin              --- PASS
=== RUN   TestGetMissingAdmin              --- PASS
=== RUN   TestSeedAdminValidation          --- PASS
=== RUN   TestHealthCheck                  --- PASS
=== RUN   TestMigrationsIdempotent         --- PASS
PASS  (0.018s)
```

### 3.2 PostgreSQL integration (all operations PASS)

Tested against real `postgres:16-alpine` container:

```
$ DB_DSN="postgres://postgres:testpass@localhost:54399/sftp?sslmode=disable" \
  go test -tags=integration -count=1 -run TestPostgreSQL_CRUD -v ./internal/store/
=== RUN   TestPostgreSQL_CRUD
    pg_integration_test.go:66: duplicate: store: username already exists: "testuser"
--- PASS: TestPostgreSQL_CRUD (0.09s)
PASS
```

Operations verified:
- Connect + health check
- Schema migrations (PG-specific DDL with BIGINT, TIMESTAMPTZ)
- Admin seed + get
- Account create + get + list + update + delete
- Duplicate username detection (pgconn.PgError 23505)

### 3.3 Full suite

```
$ go vet ./...          # exit 0
$ go build ./cmd/...    # exit 0
$ go test ./... -count=1  # ALL 8 packages PASS
ok  .../internal/api       7.994s
ok  .../internal/authn     1.109s
ok  .../internal/crypt     0.072s
ok  .../internal/firebase  0.011s
ok  .../internal/sftpsync  0.012s
ok  .../internal/store     0.023s
ok  .../internal/vault     0.008s
```

## 4. Usage

```bash
# SQLite (default)
DB_PATH=data/sftp.db

# PostgreSQL
DB_DRIVER=postgres
DB_DSN="postgres://user:pass@host:5432/sftp?sslmode=disable"
```

The `main.go` entry point resolves:
- When `DB_DRIVER` is empty or `"sqlite"`: uses `DB_PATH` as the SQLite file path
- When `DB_DRIVER` is `"postgres"` and `DB_DSN` is set: uses `DB_DSN` as the PG connection URL

## 5. Files Modified

| File | Change |
|---|---|
| `api/internal/store/store.go` | Interface type, dialect-aware queries, per-driver DDL, timestamp handling, PG unique-violation detection |
| `api/internal/config/config.go` | `DBDriver`/`DBDSN` fields + env vars + validation |
| `api/cmd/sftp-api/main.go` | DSN resolution: picks `DB_DSN` for PG, `DB_PATH` for SQLite |
| `api/internal/store/store_test.go` | Updated `Open()` calls to 3-arg signature |
| `api/internal/api/handlers_test.go` | Updated `store.Open()` calls |

## 6. Honest Boundary

- PostgreSQL support is verified against a real `postgres:16-alpine` container
  with all CRUD operations + duplicate detection.
- The store's SQLite tests run against the same code path, confirming no
  regression.
- Timestamp round-tripping works for both drivers: SQLite stores RFC3339Nano
  TEXT strings; PostgreSQL uses native TIMESTAMPTZ via pgx.
- The `pgx/v5/pgconn` dependency is transitively available through the
  `digital.vasic.database` module's PostgreSQL package.
