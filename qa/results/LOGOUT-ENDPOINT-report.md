# LOGOUT-ENDPOINT Implementation Report

**Date:** 2026-07-11
**Scope:** POST /auth/logout endpoint — Review-B Finding 2

## Implementation Summary

### Files Modified

1. **`api/internal/authn/authn.go`** — Added token revocation infrastructure:
   - Added `crypto/rand` and `encoding/hex` imports for JTI generation
   - Added `sync` import for concurrent-safe revocation map
   - Added `JTI string` field to `Claims` struct
   - Added `revokedMu sync.RWMutex` and `revokedJTIs map[string]time.Time` to `Service`
   - Added `generateJTI()` helper — 16 random bytes hex-encoded (32-char unique ID)
   - Modified `sign()` to include `jti` claim in every issued token
   - Modified `validate()` to extract `jti` from claims into `Claims.JTI`
   - Added `ErrTokenRevoked` sentinel error
   - Added `RevokeRefreshToken(tokenString string) error` — validates token, marks JTI as revoked
   - Added `IsJTIRevoked(jti string) bool` — checks revocation map with read lock
   - Modified `ValidateRefresh()` to check revocation after standard validation

2. **`api/internal/api/router.go`** — Added route:
   - `secured.POST("/auth/logout", s.handleLogout)` — in the secured group (requires valid access token)

3. **`api/internal/api/handlers_auth.go`** — Added handler:
   - `logoutRequest` struct with `refresh_token` field
   - `handleLogout()` — validates JSON body, requires `refresh_token`, calls `RevokeRefreshToken`,
     returns 200 `{"message":"logged out"}` on success, 401 on invalid/expired token

### Test Coverage Added

4. **`api/internal/authn/authn_test.go`** — 5 new test functions:
   - `TestTokenPairHasJTI` — verifies both access and refresh tokens carry a non-empty JTI
   - `TestRevokeRefreshToken` — validates before revoke, revokes, confirms `ErrTokenRevoked`,
     confirms access token from same pair is NOT revoked
   - `TestRevokeAccessTokenRejected` — verifies `RevokeRefreshToken` rejects an access token
   - `TestIsJTIRevoked` — full lifecycle: JTI not revoked before, revoked after
   - `TestRevokeExpiredRefreshTokenFails` — verifies expired token rejection

5. **`api/internal/api/handlers_test.go`** — 4 new test functions + 1 existing test updated:
   - Updated `TestSecuredEndpointsRequireToken` to include `/api/v1/auth/logout`
   - `TestLogoutRequiresAuth` — verifies 401 without bearer token
   - `TestLogoutInvalidatesRefreshToken` — full flow: login, refresh works, logout with access token,
     refresh fails after logout, un-revoked new refresh token still works
   - `TestLogoutEmptyRefreshTokenRejected` — verifies 400 on empty refresh_token
   - `TestLogoutWithAccessTokenRejected` — verifies access token cannot be used as refresh_token for revocation

### Verification Results

```
go vet ./...    — PASS (exit 0)
go build        — PASS (exit 0)
go test ./...   — ALL 8 packages PASS
```

| Package | Status | Duration |
|---------|--------|----------|
| api/internal/api | PASS | ~7s |
| api/internal/authn | PASS | <1s |
| api/internal/crypt | PASS | <1s |
| api/internal/firebase | PASS | <1s |
| api/internal/sftpsync | PASS | <1s |
| api/internal/store | PASS | <1s |
| api/internal/vault | PASS | <1s |

### API Contract

**POST /api/v1/auth/logout**

- **Auth:** Requires valid access token (Bearer header)
- **Request body:** `{"refresh_token": "<string>"}`
- **Success (200):** `{"message": "logged out"}`
- **Error (400):** Invalid JSON or empty refresh_token
- **Error (401):** Missing bearer token, invalid/expired/revoked refresh token, or access token passed as refresh_token

### Design Notes

- Each issued JWT now carries a `jti` (JWT ID) claim — a random 16-byte hex-encoded string — enabling per-token identification
- Revocation is in-memory only (map JTI -> revocation timestamp), guarded by `sync.RWMutex`
- `ValidateRefresh` now performs a post-validation revocation check: if the JTI is in the revoked set, it returns `ErrTokenRevoked`
- The refresh handler in `handlers_auth.go` (unchanged) naturally inherits this protection since it calls `ValidateRefresh` — a revoked refresh token is rejected with 401
- Only refresh tokens are revocable; access tokens are not checked against the revocation set
