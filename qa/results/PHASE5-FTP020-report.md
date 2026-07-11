# PHASE5-FTP020: PostgreSQL Driver Verification Report

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-11T23:00:00Z |
| **Status** | PASS — gap analysis complete |
| **Author** | Claude (subagent) |
| **Scope** | `api/internal/store/`, `database/pkg/postgres/`, `database/pkg/sqlite/`, `database/pkg/database/` |

---

## 1. Summary

PostgreSQL is NOT currently wired into the SFTP API store layer. The store
(`api/internal/store/store.go`) is hardcoded to the concrete `sqlite.Client`
type from `digital.vasic.database/pkg/sqlite`. The `digital.vasic.database`
submodule DOES have a full, working PostgreSQL implementation at
`database/pkg/postgres/` using `pgx/v5` and `pgxpool`, and BOTH drivers
implement the SAME `database.Database` interface in `database/pkg/database/`.

The integration gap is the store layer itself — it was never designed for
driver switching. Five specific changes are needed (documented below).

All 26 PostgreSQL integration tests in `database/pkg/postgres/` PASS against
a real `postgres:16-alpine` container. The database module's PG support is
real and works.

---

## 2. What Works (Good News)

### 2.1. Postgres implementation exists and is battle-tested

The `digital.vasic.database/pkg/postgres` package provides:

- `Client` struct implementing `database.Database` interface
- `pgx/v5` + `pgxpool` for connection pooling
- Full CRUD, transactions, health checks, migrations
- 119 tests (26 integration against real PG + 93 unit) — ALL GREEN

```
ok  digital.vasic.database/pkg/postgres  0.444s
```

### 2.2. Both drivers implement the same interface

```go
// database.Database - shared by both sqlite.Client and postgres.Client
type Database interface {
    Connect(ctx context.Context) error
    Close() error
    Exec(ctx context.Context, query string, args ...any) (Result, error)
    Query(ctx context.Context, query string, args ...any) (Rows, error)
    QueryRow(ctx context.Context, query string, args ...any) Row
    Begin(ctx context.Context) (Tx, error)
    HealthCheck(ctx context.Context) error
}
```

This means a refactored `Store` can hold a `database.Database` interface
and accept either backend via constructor injection.

### 2.3. `sql.ErrNoRows` matching works with pgx

Despite pgx having its own `pgx.ErrNoRows`, the actual runtime error wraps
`sql.ErrNoRows`, so `errors.Is(err, sql.ErrNoRows)` returns TRUE:

```
Scan error for missing row: no rows in result set (type: *pgx.proxyError)
Is sql.ErrNoRows? true
Is pgx.ErrNoRows? true
```

The store's `GetAccount()` and `GetAdmin()` `errors.Is(err, sql.ErrNoRows)`
checks WILL work correctly against PostgreSQL without any code changes.

---

## 3. What Does NOT Work (Gaps)

### 3.1. Gap A: Store hardcoded to `sqlite.Client` concrete type

**File:** `api/internal/store/store.go`, line 118

```go
type Store struct {
    client *sqlite.Client    // <-- concrete type, not interface
}
```

**File:** `api/internal/store/store.go`, lines 145-169

```go
func Open(ctx context.Context, path string) (*Store, error) {
    cfg := sqlite.DefaultConfig(path)  // <-- sqlite-specific
    client := sqlite.New(cfg)          // <-- sqlite-specific
    ...
}
```

**Fix:** Change `Store.client` to `database.Database` interface. Add a
`NewStore(client database.Database)` constructor OR modify `Open()` to
accept driver selection.

### 3.2. Gap B: `?` placeholders (SQLite syntax) incompatible with pgx

**Tested:** pgx with `PreferSimpleProtocol: true` REJECTS `?` placeholders:

```
QUESTION: ? placeholder FAILS with PreferSimpleProtocol: exec: unused argument: 0
```

pgx requires `$1`, `$2`, `$3`, ... placeholders. The SFTP store uses `?`
in ALL SQL queries (INSERT, SELECT, UPDATE, DELETE, migration checks).

**Affected queries (store.go):**

| Line | Query | Placeholder count |
|---|---|---|
| 184-185 | `SELECT COUNT(*) FROM schema_migrations WHERE version = ?` | 1 |
| 201-202 | `INSERT INTO schema_migrations ... VALUES (?, ?)` | 2 |
| 235-239 | `INSERT INTO accounts ... VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)` | 9 |
| 255-256 | `SELECT ... FROM accounts WHERE username = ?` | 1 |
| 269-270 | `SELECT ... FROM accounts ORDER BY username ASC` | 0 |
| 299-304 | `UPDATE accounts SET ... = ?, ... WHERE username = ?` | 7 |
| 321 | `DELETE FROM accounts WHERE username = ?` | 1 |
| 344-345 | `SELECT COUNT(*) FROM admins WHERE username = ?` | 1 |
| 353-354 | `INSERT INTO admins ... VALUES (?, ?, ?, ?)` | 4 |
| 367-369 | `SELECT ... FROM admins WHERE username = ?` | 1 |

**Fix options:**

1. (Recommended) Use the database module's `connection` package which
   provides dialect-aware query rewriting (`?` → `$N` for PostgreSQL).
2. Use two sets of SQL with build tags or driver-detection switch.
3. Use `database/sql`'s pgx stdlib adapter which supports `?` through
   `database/sql`'s internal placeholder rewriter.

### 3.3. Gap C: `isUniqueViolation()` only detects SQLite errors

**File:** `api/internal/store/store.go`, lines 435-439

```go
func isUniqueViolation(err error) bool {
    msg := err.Error()
    return strings.Contains(msg, "UNIQUE constraint failed") ||
        strings.Contains(msg, "constraint failed") && strings.Contains(msg, "accounts.username")
}
```

PostgreSQL returns a `pgconn.PgError` with SQLSTATE code `23505`
(`unique_violation`), not the SQLite text pattern:

```
Duplicate error: ERROR: duplicate key value violates unique constraint "accounts_pkey" (SQLSTATE 23505)
Is PG unique violation (code 23505)? true
Contains 'duplicate key'? true
Contains 'UNIQUE constraint' (SQLite-style)? false
```

**Fix:** Use `errors.As()` to check for `*pgconn.PgError` with code `"23505"`:

```go
func isUniqueViolation(err error) bool {
    var pgErr *pgconn.PgError
    if errors.As(err, &pgErr) && pgErr.Code == "23505" {
        return true
    }
    msg := err.Error()
    return strings.Contains(msg, "UNIQUE constraint failed") ||
        (strings.Contains(msg, "constraint failed") && strings.Contains(msg, "accounts.username"))
}
```

### 3.4. Gap D: Config struct has no driver selection fields

**File:** `api/internal/config/config.go`

The `Config` struct only has `DBPath string` — a file path. There are no
`DB_DRIVER` or `DB_DSN` fields, and no env vars for them.

**Fix:** Add fields and env vars:

```go
type Config struct {
    ...
    DBDriver string `json:"db_driver" yaml:"db_driver"`   // "sqlite" | "postgres"
    DBDSN    string `json:"db_dsn"    yaml:"db_dsn"`       // postgres://... or file path
    ...
}
```

Add corresponding env vars `DB_DRIVER` and `DB_DSN` in `applyEnv()`.

### 3.5. Gap E: DDL schema differences between SQLite and PG

The store's migrations (store.go lines 123-141) use SQLite-specific types:

| Column | SQLite DDL | PostgreSQL DDL needed |
|---|---|---|
| `uid` / `gid` | `INTEGER` | `BIGINT` (or `INTEGER` — PG's INTEGER is 4 bytes) |
| `enabled` | `INTEGER NOT NULL DEFAULT 1` | `INTEGER NOT NULL DEFAULT 1` (works, same) |
| `created_at` | `TEXT NOT NULL` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |
| `updated_at` | `TEXT NOT NULL` | `TIMESTAMPTZ NOT NULL DEFAULT NOW()` |

Additionally, the store stores timestamps as RFC3339Nano TEXT strings and
parses them back with `time.Parse(time.RFC3339Nano, s)`. With PostgreSQL,
timestamps come back as `time.Time` directly from the driver — the TEXT
format is never used. The `parseTime()` helper would need to be a no-op or
removed for PG.

**Fix:** Provide per-driver migration sets, or use a migration helper that
emits dialect-correct DDL.

---

## 4. What the Config API would look like

### 4.1. Configuration

```bash
# SQLite (current default)
DB_DRIVER=sqlite
DB_PATH=data/sftp.db

# PostgreSQL (new)
DB_DRIVER=postgres
DB_DSN="postgres://postgres:password@localhost:5432/sftp?sslmode=disable"
```

### 4.2. Store.Open() entry point sketch

```go
func Open(ctx context.Context, driver, dsn string) (*Store, error) {
    var client database.Database
    switch driver {
    case "sqlite", "":
        cfg := sqlite.DefaultConfig(dsn)
        client = sqlite.New(cfg)
    case "postgres":
        cfg := postgres.DefaultConfig()
        // parse dsn into cfg fields...
        client = postgres.New(cfg)
    default:
        return nil, fmt.Errorf("store: unsupported driver %q", driver)
    }
    if err := client.Connect(ctx); err != nil {
        return nil, err
    }
    s := &Store{client: client}
    if err := s.migrate(ctx); err != nil {
        _ = client.Close()
        return nil, err
    }
    return s, nil
}
```

---

## 5. Verification Evidence

### 5.1. SQLite baseline (all tests PASS)

```
$ go test ./internal/store/ -v -count=1
=== RUN   TestCreateAndGetAccount        --- PASS
=== RUN   TestCreateDuplicateUsernameRejected --- PASS
=== RUN   TestGetMissingAccount          --- PASS
=== RUN   TestListAccountsOrdered        --- PASS
=== RUN   TestUpdateAccount              --- PASS
=== RUN   TestUpdateMissingAccount       --- PASS
=== RUN   TestDeleteAccount              --- PASS
=== RUN   TestDeleteMissingAccount       --- PASS
=== RUN   TestAccountValidation          --- PASS
=== RUN   TestNilUIDGIDRoundTrip         --- PASS
=== RUN   TestSeedAndGetAdmin            --- PASS
=== RUN   TestGetMissingAdmin            --- PASS
=== RUN   TestSeedAdminValidation        --- PASS
=== RUN   TestHealthCheck                --- PASS
=== RUN   TestMigrationsIdempotent       --- PASS
PASS
ok      github.com/vasic-digital/sftp/api/internal/store      0.016s
```

### 5.2. Database module PG integration tests (all PASS)

```
$ go test -tags=integration -count=1 ./pkg/postgres/
ok      digital.vasic.database/pkg/postgres      0.444s
```

(26 integration tests + 93 unit tests = 119 total, all green)

### 5.3. SFTP store SQL compatibility against real PostgreSQL

DDL (with PG-adapted types): **PASS**
CRUD cycle (INSERT/SELECT/UPDATE/DELETE with $N placeholders): **PASS**
Unique violation detection via `pgconn.PgError{Code: "23505"}`: **PASS**
`?` placeholder with pgx PreferSimpleProtocol: **FAIL** (as expected)
`sql.ErrNoRows` matching from pgx: **PASS** (works via error wrapping)

---

## 6. Effort Estimate

| Task | Approx. complexity | Lines changed |
|---|---|---|
| A: Switch `Store.client` to `database.Database` interface | Low | ~10 |
| B: Placeholder syntax migration (`?` → `$N` or dialect adapter) | Medium | ~50 (all queries) |
| C: PG-aware `isUniqueViolation()` | Low | ~10 |
| D: Config fields + env vars | Low | ~20 |
| E: Per-driver DDL migrations | Medium | ~30 |
| Wire `main.go` to select driver based on config | Low | ~15 |
| Add `store_test.go` with PG test helper + run against both drivers | Medium | ~30 |
| **Total** | | **~165** |

---

## 7. Honest Boundary

- The database module's PostgreSQL support is **real and working** against
  a live `postgres:16-alpine` container with all 119 tests passing.
- The SFTP API store was **never tested against PostgreSQL** — it was
  designed for SQLite only, and the concrete type coupling confirms this.
- All 15 store tests currently run against SQLite only and pass.
- The store CAN be made driver-agnostic with ~165 lines of changes across
  4 files (store.go, config.go, main.go, store_test.go).
- This report captures real captured evidence from a live PG container.
  No claim is made without a corresponding test run.
