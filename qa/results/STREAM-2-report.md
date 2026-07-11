# STREAM-2 Report — ATM-002: Go REST API (account management + super-admin auth)

**Track:** T1 / branch main — `(T1/main - sftp) STREAM-2`
**Date:** 2026-07-11
**Status:** DONE_WITH_CONCERNS

## Test summary (captured evidence)

```
go test ./... -count=1   (run 3×, deterministic per §11.4.50 — exit 0 each run)
ok  internal/api        5.138s   (13 integration tests, REAL Gin + REAL SQLite temp files)
ok  internal/authn      0.903s   (bcrypt, JWT issue/validate/expired/tampered/wrong-secret/alg-none)
ok  internal/crypt      0.062s   (sha512-crypt vs openssl golden vectors)
ok  internal/sftpsync   0.011s   (golden render, auto-IDs, atomic write 0600, fail-closed)
ok  internal/store      0.019s   (CRUD, duplicate rejection, SeedAdmin)
go vet ./...  → exit 0
gofmt -l .    → empty
go build ./...→ exit 0
```

**Live end-to-end smoke against the real binary** (not a test harness —
compiled `cmd/sftp-api`, real env vars, real HTTP via curl):

- Refuses to start without `JWT_SECRET` and without `SUPERADMIN_PASSWORD`
  (exit 1, clear message — no insecure default).
- Full journey: health → wrong-password login 401 → login ok → create
  read_write (201) → public without ack (422) → public with ack (201) →
  sync → `users.conf` contents asserted → SIGTERM graceful shutdown
  (`shutdown complete`, exit 0).
- The live-rendered sha512-crypt hash was cross-verified byte-identical to
  `openssl passwd -6 -salt <salt> <password>` (independent oracle) AND
  Python passlib `sha512_crypt.verify` → atmoz `usermod -p` will accept it.

## Deliverables (all in `api/`, nothing else touched)

- `cmd/sftp-api/main.go` — rewritten from placeholder: config.Load →
  Validate → store.Open → bcrypt-hash SUPERADMIN_PASSWORD → SeedAdmin →
  authn.NewService → api.NewServer → http.Server with ReadHeaderTimeout +
  graceful SIGINT/SIGTERM shutdown (15 s drain) → store.Close. Secrets
  consumed from env, never logged.
- `internal/config/config.go` — defaults < API_CONFIG file (JSON via
  digital.vasic.config, YAML via yaml.Unmarshal) < env. Validate refuses
  startup without JWT_SECRET (≥32 chars) / SUPERADMIN_PASSWORD outside
  test mode.
- `internal/store/store.go` + `store_test.go` — accounts CRUD (username
  regex `[a-z_][a-z0-9_-]{0,31}`, bcrypt password_hash, permission enum,
  optional uid/gid, home, enabled, timestamps), admins table + SeedAdmin
  (insert-if-absent) / GetAdmin. modernc.org/sqlite, MaxOpenConns=1, WAL.
- `internal/authn/authn.go` + `authn_test.go` — bcrypt cost 12; JWT
  HS256 access (15 m) + refresh (168 h) pairs; kind/issuer/expiry/alg
  enforcement; getters AccessTTL/RefreshTTL added for handlers.
- `internal/crypt/crypt.go` + `crypt_test.go` — sha512-crypt ($6$)
  implemented in-project, byte-identical to `openssl passwd -6` (5 golden
  vectors) and passlib. Root cause found and fixed during the session: the
  S-sequence digest must be TRUNCATED to salt length (verified against
  passlib `_raw_sha2_crypt` source), not repeated.
- `internal/api/router.go` — middleware stack: gin.Wrap for ADDITIVE-only
  middleware (request-id, recovery, request logging with health skipped);
  NATIVE Gin middleware for rejecting paths (JWT auth, per-IP fixed-window
  rate limit on auth endpoints) because the gin.Wrap adapter does not call
  `c.Abort()` on rejection (verified adapter behaviour, documented in
  source comments).
- `internal/api/handlers_auth.go` — login (400/401 same-body for wrong
  password and unknown user — no enumeration), refresh (rejects access
  tokens), me.
- `internal/api/handlers_accounts.go` — create (201/409/400/422),
  list, get, update (optional password re-hash), delete (204).
  `public` requires `public_acknowledged: true` else 422
  `public_access_not_acknowledged`. accountResponse has NO password fields.
- `internal/api/handlers_sync.go` — in-memory cryptVault + POST /sync
  (atomic write-temp-then-rename, 0600, returns line count + path).
- `internal/api/errors.go` — error body + code constants.
- `internal/api/handlers_test.go` — 13 integration tests: full account
  journey incl. 422/201/409/400, list ordering, update, sync with REAL
  file-content assertions (`$6$` hash, `pubacct:*:...:e`), delete→404,
  rate limiting, panic recovery 500, request-id header, malformed JSON,
  store-reopen persistence, no-password-in-any-response sweep, crypt-vault
  lifecycle.
- `internal/sftpsync/sftpsync.go` + `sftpsync_test.go` — atmoz render
  `user:password:uid:gid:home[:options]`, sorted/deterministic, auto
  uid/gid from 1001, permission mapping (rw→no suffix, ro→`:e`,
  public→`*`+`:e`), fail-closed `*` without provisioned hash, disabled
  accounts omitted.
- `api/README.md` — endpoints, env vars, crypt decision with evidence,
  all deviations/boundaries documented.

## Evidence-based decisions (§11.4.6, no guessing)

1. **sha512-crypt for users.conf** — chosen because atmoz passes the field
   to `usermod -p` (glibc crypt); `$6$` is universally supported on slim
   images. Proven byte-identical to `openssl passwd -6` (the operator's
   verification tool) AND passlib. Rejected: bcrypt (glibc ≥2.27 not
   guaranteed on atmoz base), plaintext (§11.4.10 forbidden).
2. **gin.Wrap only for additive middleware** — the adapter does not
   `c.Abort()` when the wrapped middleware rejects; unsafe for
   auth/rate-limit, safe for requestid/logging/recovery.
3. **config.LoadFile is JSON-only** — verified in
   `digital.vasic.config/pkg/config` source (calls `json.Unmarshal`);
   YAML files branch to `yaml.Unmarshal`.
4. **modernc.org/sqlite (pure Go)** — verified in
   `digital.vasic.database/pkg/sqlite`; not CGO mattn.
5. **atmoz `e` option = chroot** — per atmoz docs referenced in MVP.md;
   `user:password:uid:gid:home[:options]` format per MVP.md.

## Boundaries / concerns (honest, §11.4.6)

1. **cryptVault restart boundary (documented)**: the sha512-crypt hash
   lives in an in-memory vault populated while the plaintext is in scope
   at create/update. After an API restart, accounts created in a previous
   process render with `*` (password login disabled) until the password is
   set again via the API. Fail-closed is the safe direction; the
   alternative (persisting a second password hash in the DB) was rejected
   to keep the DB free of SFTP-side credential material. If the conductor
   wants persistence-across-restart, the vault can be re-seeded by forcing
   a password rotation flow — flagging for STREAM coordination.
2. **read_only enforcement is deploy-layer**: the API maps `read_only` to
   the atmoz `e` (chroot) option; actual write-protection inside the
   chroot (root-owned home, user-writable subdirs) belongs to
   `deploy/docker-compose.yml` (STREAM-3 territory), per atmoz's
   documented model. Not enforced by the API.
3. **Tamper-test blind spot found + fixed during the session**:
   `TestTamperedTokenRejected` originally flipped the LAST base64 char of
   the signature segment, which can hold only padding bits — the decoded
   bytes stay identical and the HMAC still matches (a blind test that can
   pass without exercising tamper detection, §11.4 PASS-bluff at the test
   layer). Fixed to flip the FIRST signature char (always significant
   bits) with a comment explaining the pitfall. Verified FAIL before the
   fix (real signal), PASS after (3× deterministic).
4. **Rate limiter is in-process per-IP fixed-window** — sufficient for a
   single-instance management API bound to 127.0.0.1; not distributed. A
   restart resets the counters. If multi-instance is ever required, swap
   for the `digital.vasic.ratelimiter` tokenbucket backend.
5. `internal/config` has no test file (it is thin env/file plumbing
   covered indirectly by every integration test's `newTestEnv` and the
   live startup smoke); a dedicated unit test is a cheap future addition.

## Anti-stall / git

- No git operations performed (conductor owns all git per the brief).
- No submodule files modified; the one missing helper (sha512-crypt) was
  written in-project under `api/internal/crypt`.
- No credentials logged anywhere; the no-password sweep test enforces this
  mechanically.
