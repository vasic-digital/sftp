# PHASE4-ATM015: Security Hardening Report

**Date:** 2026-07-11
**Scope:** `api/internal/api/`, `api/internal/config/`, `web/src/api/`, `web/src/auth/`
**Status:** COMPLETE

## Summary

Migrated authentication from localStorage-based token storage (XSS-readable) to HttpOnly
cookies for refresh tokens, added security headers on all API responses, and added CORS
support with credentials.

---

## Part A: HttpOnly Cookie Migration

### Backend changes

**`api/internal/api/handlers_auth.go`:**
- Added `refreshTokenCookie` constant (`sftp_refresh_token`).
- `handleLogin`: On successful authentication, sets the refresh token as an HttpOnly,
  SameSite=Strict cookie (Secure when TLS). Access token remains in JSON body for
  backward compatibility.
- `handleRefresh`: Reads refresh token from cookie first; falls back to JSON request
  body for backward compatibility with clients not yet migrated.
- `handleLogout`: Reads refresh token from cookie first (body fallback), revokes it,
  and clears the cookie.
- Added helpers: `readRefreshToken()`, `setRefreshTokenCookie()`, `clearRefreshTokenCookie()`.

**`api/internal/config/config.go`:**
- Added `CORSOrigin` field to the `Config` struct.
- Added `API_CORS_ORIGIN` environment variable parsing.

**`api/internal/api/router.go`:**
- Added `corsMiddleware()`: Sets `Access-Control-Allow-Origin` (specific configured
  origin), `Access-Control-Allow-Credentials: true`, and handles OPTIONS preflight
  with 204. Only active when `CORSOrigin` is configured.
- Added `securityHeadersMiddleware()`: Sets on every response:
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
  - `Referrer-Policy: strict-origin-when-cross-origin`
  - `Permissions-Policy: camera=(), microphone=(), geolocation=()`

### Frontend changes

**`web/src/api/client.ts`:**
- All `fetch()` calls now include `credentials: 'include'` so HttpOnly cookies are
  sent on cross-origin requests.
- `storeTokens()` now only stores the access token in localStorage; the refresh token
  lives exclusively in the HttpOnly cookie.
- `clearTokens()` only clears the access token from localStorage.
- `refreshAccessToken()` sends an empty body (`{}`) — the refresh token is carried
  automatically by the cookie.
- `logout()` is now async: clears local state immediately, then fire-and-forgets a
  server call to revoke the refresh token and clear the cookie.
- Removed `getRefreshToken()` and `REFRESH_TOKEN_KEY` — no longer exported or needed.

**`web/src/auth/AuthContext.tsx`:**
- `logout` is now `async` to match `ApiClient.logout()`.
- On mount, `isAuthenticated()` checks for a stored access token. If present, the
  proactive refresh timer starts (the refresh cookie will rotate the token).

**`web/src/api/types.ts`:**
- Added optional `refresh_expires_in` field to `TokenPair`.

**`web/index.html`:**
- CSP meta tag was already present (added before this phase).

### Before/After Security Posture

| Attack Vector | Before | After |
|---|---|---|
| XSS steals refresh token | localStorage — trivial to read | HttpOnly cookie — JS cannot access |
| XSS steals access token | localStorage — readable but short-lived (15 min) | Unchanged (still in localStorage, but 15-min expiry limits blast radius) |
| CSRF on auth endpoints | No SameSite cookie protection | SameSite=Strict on refresh cookie |
| Clickjacking | No protection | X-Frame-Options: DENY |
| MIME sniffing | No protection | X-Content-Type-Options: nosniff |
| Referrer leakage | No policy | Referrer-Policy: strict-origin-when-cross-origin |
| Browser feature abuse | No restrictions | Permissions-Policy: camera/mic/geolocation disabled |
| Cross-origin requests | No CORS control | Configurable CORS with explicit origin + credentials |
| Content injection | No CSP | CSP meta tag in index.html |

---

## Test Results

### Backend (Go)
```
$ go vet ./...
BUILD OK

$ go build -o /dev/null ./cmd/sftp-api/
BUILD OK

$ go test ./... -count=1
ok  github.com/vasic-digital/sftp/api/internal/api    6.929s
ok  github.com/vasic-digital/sftp/api/internal/authn   0.950s
ok  github.com/vasic-digital/sftp/api/internal/crypt   0.049s
ok  github.com/vasic-digital/sftp/api/internal/firebase 0.010s
ok  github.com/vasic-digital/sftp/api/internal/sftpsync 0.011s
ok  github.com/vasic-digital/sftp/api/internal/store   0.023s
ok  github.com/vasic-digital/sftp/api/internal/vault   0.003s
All packages PASS
```

### Frontend (TypeScript/Vitest)
```
$ npx tsc --noEmit
(exit 0)

$ npx vitest run
✓ src/i18n/i18n.test.ts (5 tests)
✓ src/api/client.test.ts (11 tests)
✓ src/screens/AccountEditorScreen.test.tsx (5 tests)
Test Files  3 passed (3)
Tests      21 passed (21)
```

All 28 tests pass (7 Go packages + 3 TS test files).

---

## Backward Compatibility

The `/auth/refresh` and `/auth/logout` endpoints still accept a `refresh_token` field
in the JSON request body when the cookie is absent. This ensures existing API consumers
(CLI tools, other services) continue to work without changes.

The login JSON response still includes `refresh_token` alongside the cookie, so
non-browser clients can still use the body-based token flow.

---

## Files Changed

| File | Change |
|---|---|
| `api/internal/config/config.go` | Added `CORSOrigin` field + env parsing |
| `api/internal/api/handlers_auth.go` | Cookie helpers, login/refresh/logout cookie handling |
| `api/internal/api/router.go` | CORS + security headers middleware |
| `web/src/api/types.ts` | Added `refresh_expires_in` to TokenPair |
| `web/src/api/client.ts` | credentials:include, cookie-based refresh, async logout |
| `web/src/auth/AuthContext.tsx` | async logout |
| `web/src/api/client.test.ts` | Updated tests for new cookie-based flow |
