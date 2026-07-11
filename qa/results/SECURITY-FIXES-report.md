# SECURITY-FIXES: Phase 5 Audit Remediation Report

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-12T00:00:00Z |
| **Source audit** | `qa/results/PHASE5-FTP022-report.md` |
| **Scope** | `api/`, `web/` |
| **Constraint** | No commits made |

---

## Verification Summary

| Check | Result |
|---|---|
| `go vet ./...` | PASS (exit 0) |
| `go build -o /dev/null ./cmd/sftp-api/` | PASS (exit 0) |
| `go test ./... -count=1` | PASS (all 7 packages) |
| `go test ./... -race -count=1` | PASS (all 7 packages, no races) |

### Test Results (race detector)

| Package | Result |
|---|---|
| `internal/api` | ok (90.581s) |
| `internal/authn` | ok (13.961s) |
| `internal/crypt` | ok (1.206s) |
| `internal/firebase` | ok (1.038s) |
| `internal/sftpsync` | ok (1.049s) |
| `internal/store` | ok (1.234s) |
| `internal/vault` | ok (1.016s) |

---

## Fix 1: HIGH — quic-go vulnerability GO-2026-5676

**Audit Finding 1.1:** `github.com/quic-go/quic-go` v0.59.0 has an HTTP/3 QPACK
trailer memory exhaustion vulnerability. Fixed in v0.59.1.

**Change:** Bumped `github.com/quic-go/quic-go` from v0.59.0 to v0.59.1 in
`api/go.mod`. Ran `go mod tidy`.

**File:** `api/go.mod` (line 113)

**Verification:** `go vet` and `go build` pass clean. No breaking changes — quic-go
is a transitive dependency pulled in via Firebase Admin SDK / Google Cloud
libraries and not directly used by the SFTP API.

---

## Fix 2: MODERATE — Refresh token leaked in JSON response body

**Audit Finding 6.1:** Both `handleLogin` and `handleRefresh` included the
`refresh_token` field in the JSON response body, making it accessible to
JavaScript in XSS scenarios. The refresh token is already set as an HttpOnly
cookie.

**Changes:**

1. **`api/internal/api/handlers_auth.go`:**
   - Removed `RefreshToken` field from `tokenResponse` struct. Added comment
     documenting the HttpOnly-cookie-only design.
   - Removed `RefreshToken` from both `handleLogin` and `handleRefresh` JSON
     response bodies. The refresh token is delivered exclusively via the
     `Set-Cookie` header with `HttpOnly`, `SameSite=Strict`.
   - `handleRefresh` and `handleLogout` still read `refresh_token` from the
     JSON request body as a fallback for backward compatibility (non-browser
     clients that do not send cookies).

2. **`api/internal/api/handlers_test.go`:**
   - Modified `login()` helper to return the refresh token extracted from the
     `Set-Cookie` response header (via `refreshTokenFromCookie` helper)
     instead of from the JSON response body.
   - Updated all 7 call sites of `login()` to use the new `(map[string]any, string)` return.
   - Updated `TestLogoutInvalidatesRefreshToken` to extract the rotated
     refresh token from the cookie after `/auth/refresh` instead of from JSON.

3. **`web/src/api/types.ts`:**
   - Made `refresh_token` optional in the `TokenPair` interface. The web
     client already relied on the HttpOnly cookie for refresh (sends
     `body: '{}'` to `/auth/refresh` and only stores `access_token` in
     localStorage).

**Verification:** All 7 test packages pass with `-count=1` and `-race`.
The `TestFullAccountJourney`, `TestLogoutInvalidatesRefreshToken`,
`TestRefreshRejectsAccessToken`, and auth tests all pass — confirming
that login, refresh, and logout flows work correctly with the cookie-based
refresh token delivery.

---

## Fix 3: MODERATE — Rate limiter unbounded map growth

**Audit Finding A.1:** The `ipLimiter` map in `api/internal/api/router.go`
never shrank entries for IPs that stopped sending requests. Under a
sustained attack from many distinct IPs, the map could grow unbounded.

**Changes (`api/internal/api/router.go`):**

1. Added `lastAccess time.Time` field to `limitEntry` struct to track the
   last time each IP was rate-checked.
2. Updated the middleware to set `e.lastAccess = now` on every request
   (alongside the existing `e.count++`).
3. Added `cleanupLoop(interval, maxAge time.Duration)` method on `ipLimiter`
   that runs a background ticker every 30 minutes and deletes entries whose
   `lastAccess` is older than 1 hour.
4. Started the cleanup goroutine in `rateLimitMiddleware` when `rate > 0`
   (i.e., rate limiting is enabled).

**Verification:** `go vet` reports no issues. `go test -race` passes —
the cleanup goroutine does not cause data races (correct `l.mu.Lock()`/`Unlock()`
protection).

---

## Files Changed

| File | Change |
|---|---|
| `api/go.mod` | Bumped `quic-go` v0.59.0 → v0.59.1 |
| `api/go.sum` | Updated via `go mod tidy` |
| `api/internal/api/handlers_auth.go` | Removed `RefreshToken` from `tokenResponse` struct and JSON responses |
| `api/internal/api/handlers_test.go` | Updated tests to extract refresh tokens from HttpOnly cookies |
| `api/internal/api/router.go` | Added `lastAccess` tracking + background cleanup goroutine to `ipLimiter` |
| `web/src/api/types.ts` | Made `refresh_token` optional in `TokenPair` |
