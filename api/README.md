# api/ — SFTP Enterprise Management API (Go)

Go REST API managing SFTP accounts, super-admin authentication, and
`users.conf` synchronisation for the `atmoz/sftp` container. Depends on the
owned `digital.vasic.*` submodules at the repo root (see `go.mod` replace
directives).

Owned by STREAM-2 (API core) per `docs/plans/master_implementation_plan.md`;
module skeleton + dependency graph bootstrapped by STREAM-1 (ATM-001).

## Running

Required environment variables (no insecure defaults — the API refuses to
start without them):

| Variable | Default | Notes |
|---|---|---|
| `JWT_SECRET` | — | **Required** (min 32 chars). Signs access/refresh tokens. |
| `SUPERADMIN_PASSWORD` | — | **Required**. Seeds the super-admin (bcrypt-hashed, never stored in plaintext, never logged). |
| `SUPERADMIN_USERNAME` | `admin` | Super-admin username. |
| `API_BIND` | `127.0.0.1` | Listen address. |
| `API_PORT` | `7722` | Listen port. |
| `DB_PATH` | `data/sftp.db` | SQLite database file. |
| `USERS_CONF_PATH` | `data/users.conf` | atmoz `users.conf` render target. |
| `ACCESS_TOKEN_TTL` | `15m` | Access token lifetime. |
| `REFRESH_TOKEN_TTL` | `168h` | Refresh token lifetime. |
| `API_CONFIG` | — | Optional JSON or YAML config file; env vars override file values. |

```bash
export JWT_SECRET="$(openssl rand -hex 32)"
export SUPERADMIN_PASSWORD='...'
go run ./cmd/sftp-api
```

Graceful shutdown on SIGINT/SIGTERM (drain timeout 15 s), then SQLite close.

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/v1/health` | — | Liveness probe (skipped from request logging). |
| POST | `/api/v1/auth/login` | rate-limited | `{username,password}` → `{access_token, refresh_token, token_type, expires_in, refresh_expires_in}`. Wrong password and unknown user return the same `401 invalid_credentials` (no enumeration). |
| POST | `/api/v1/auth/refresh` | rate-limited | `{refresh_token}` → new token pair. Access tokens are rejected here. |
| GET | `/api/v1/auth/me` | Bearer JWT | `{username, expires_at}` from the token claims. |
| POST | `/api/v1/accounts` | Bearer JWT | Create account (201). Duplicate → 409. |
| GET | `/api/v1/accounts` | Bearer JWT | List accounts `{accounts, count}`, sorted by username. |
| GET | `/api/v1/accounts/:username` | Bearer JWT | Fetch one account (404 if absent). |
| PUT | `/api/v1/accounts/:username` | Bearer JWT | Update account; optional `password` re-hashes both bcrypt (DB) and sha512-crypt (users.conf render). |
| DELETE | `/api/v1/accounts/:username` | Bearer JWT | Delete account (204). |
| POST | `/api/v1/sync` | Bearer JWT | Render `users.conf` atomically (0600, write-temp-then-rename) → `{rendered_accounts, path}`. |

Account fields: `username` (`[a-z_][a-z0-9_-]{0,31}`), `password`
(write-only, bcrypt cost 12 in the DB, never echoed in any response),
`permission` (`read_only` | `read_write` | `public`; default `read_only`),
optional `uid`/`gid` (auto-assigned from 1001 in username order when
omitted), `home_dir` (default `/<username>`), `enabled`, timestamps.

**`public` access is never a default**: creating or updating an account
with `"permission": "public"` requires `"public_acknowledged": true` in the
request body, otherwise the API returns `422 public_access_not_acknowledged`.

Responses never contain password material of any kind — no plaintext, no
bcrypt hash, no crypt hash (covered by `TestNoPasswordInAnyResponse`, which
sweeps every endpoint's response body).

## users.conf rendering + the crypt decision

atmoz/sftp consumes `users.conf` lines of the form
`user:password:uid:gid:home[:options]`. The `password` field is passed to
`usermod -p`, which accepts any glibc `crypt(3)` hash. **Decision (made
with evidence, §11.4.6): sha512-crypt (`$6$`)**, implemented in-project at
`internal/crypt` (Drepper SHA-crypt, 5000 default rounds) and proven
byte-identical to `openssl passwd -6` — the exact tool operators use to
verify hashes manually — plus cross-validated against Python passlib's
reference implementation. Alternatives rejected: bcrypt (`$2b$`, supported
by glibc ≥ 2.27 but not guaranteed on the slim atmoz image's crypt
backend) and plaintext (forbidden, §11.4.10).

Permission mapping:

| Permission | users.conf line |
|---|---|
| `read_write` | `user:<sha512-crypt>:uid:gid:home` |
| `read_only` | `user:<sha512-crypt>:uid:gid:home:e` (`e` = chroot) |
| `public` | `user:*:uid:gid:home:e` (no password login, ever) |

**Two-credential model**: the bcrypt hash in the DB authenticates API
callers only and is never rendered; the sha512-crypt hash in `users.conf`
authenticates SFTP logins only. The crypt hash is computed in an in-memory
vault at account create/update time while the plaintext is in scope.
**Restart boundary**: after an API restart the vault is empty, so accounts
created in a previous process render with `*` (password login disabled)
until their password is set again via the API. This is the safe failure
direction (fail closed). Enabling/disabling, renaming, and metadata updates
do not affect this.

**read_only enforcement boundary**: the API maps `read_only` to the atmoz
`e` (chroot) option. Write-protection inside the chroot (directory
ownership/modes) is enforced at the deploy/container layer
(`deploy/docker-compose.yml`), not by the API — atmoz's documented model is
"home owned by root, subdirectories writable by the user".

## Middleware notes (verified behaviour, §11.4.6)

- `gin.Wrap` adapters are used ONLY for additive middleware (request-id,
  recovery, request logging) because the adapter does not call `c.Abort()`
  when the wrapped `net/http` middleware rejects a request. Rejecting
  middleware (JWT auth, per-IP fixed-window rate limit on auth endpoints)
  is implemented natively on Gin so rejection reliably aborts the handler
  chain.
- Request logging never logs bodies or credentials (§11.4.10).
- SQLite runs on `modernc.org/sqlite` (pure Go, no CGO) via
  `digital.vasic.database/pkg/sqlite`, `MaxOpenConns=1`, WAL mode.
- `digital.vasic.config`'s `LoadFile` is JSON-only (verified in source);
  `internal/config` branches `.yaml`/`.yml` to `yaml.Unmarshal`, everything
  else to `LoadFile`.

## Testing

```bash
go test ./...   # unit + integration (REAL Gin server + REAL SQLite temp files)
go vet ./...
gofmt -l .
```

Integration tests in `internal/api/handlers_test.go` run the full journey:
health → login (wrong password 401, ok) → create read_only → public
without ack (422) → public with ack (201) → duplicate (409) → list/get/
update → sync (asserts the rendered file contents) → delete → 404 — plus
rate limiting, panic recovery, request-id presence, store-reopen
persistence, and the no-password-in-any-response sweep. No mocks anywhere
outside unit tests (§11.4.27).
