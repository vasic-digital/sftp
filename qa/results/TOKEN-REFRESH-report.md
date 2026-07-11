# TOKEN-REFRESH Implementation Report

**Task:** Add proactive token refresh to the SFTP web SPA (REVIEW-B Finding 3)
**Date:** 2026-07-11
**Status:** PASS

## Summary

Added proactive token refresh logic that automatically refreshes the access token
~60 seconds before expiry, eliminating the need to wait for a 401 response before
refreshing. The timer is managed across login, logout, page-reload, and session-expiry
scenarios.

## Files Modified

### 1. `web/src/api/client.ts`

**Constants added:**
- `EXPIRES_AT_KEY` (`sftp.expires_at`) -- localStorage key for the computed
  expiration timestamp (epoch milliseconds)
- `REFRESH_LEAD_SECONDS` (60) -- how many seconds before expiry to trigger refresh

**Helper functions added (module-level):**
- `getExpiresAt()` -- reads and parses the stored expiration timestamp
- `storeExpiresAt(expiresIn)` -- computes `Date.now() + expiresIn * 1000` and stores it
- `clearExpiresAt()` -- removes the stored expiration timestamp

**`clearTokens()` updated** to also remove `EXPIRES_AT_KEY`, keeping all
auth-related localStorage keys cleared together.

**`ApiClient` class additions:**
- `private refreshTimerId` -- holds the `setTimeout` handle or `null`
- `startProactiveRefresh()` -- public entry point; calls `scheduleProactiveRefresh()`
- `stopProactiveRefresh()` -- public; clears the timer, idempotent
- `private scheduleProactiveRefresh()` -- stops any existing timer, reads
  `expires_at`, computes `max(0, expiresAt - Date.now() - 60_000)`, and sets a
  `setTimeout` that fires `performProactiveRefresh()`
- `private performProactiveRefresh()` -- calls `refreshAccessToken()`; on
  success the timer is automatically rescheduled (inside `refreshAccessToken`);
  on failure calls `onSessionExpired?.()`

**`refreshAccessToken()` updated:**
- On success: calls `storeExpiresAt(tokens.expires_in)` and
  `this.scheduleProactiveRefresh()` to reschedule with the new token's lifetime
- On failure (both HTTP error and catch): calls `clearExpiresAt()` and
  `this.stopProactiveRefresh()` in addition to existing `clearTokens()`

**`login()` updated:**
- After `storeTokens(tokens)`, also calls `storeExpiresAt(tokens.expires_in)`
  and `this.scheduleProactiveRefresh()`

**`logout()` updated:**
- Now calls `clearExpiresAt()` and `this.stopProactiveRefresh()` in addition to
  `clearTokens()`

### 2. `web/src/auth/AuthContext.tsx`

**`useEffect` on mount updated:**
- After wiring `apiClient.onSessionExpired`, checks `isAuthenticated()` and
  calls `apiClient.startProactiveRefresh()` if a stored session exists (handles
  page reload / revisit scenarios)
- Cleanup function now calls `apiClient.stopProactiveRefresh()` to prevent the
  timer from firing after the provider unmounts

## Behavior by Scenario

| Scenario | Timer Behavior |
|---|---|
| Fresh login | Timer starts after `storeTokens`, fires ~60s before expiry |
| 401 reactive refresh (success) | `refreshAccessToken` reschedules timer with new expiry |
| 401 reactive refresh (failure) | Timer cleared, tokens cleared, `onSessionExpired` fires |
| Proactive timer fires (success) | `scheduleProactiveRefresh` called, new timer set |
| Proactive timer fires (failure) | Timer cleared, tokens cleared, `onSessionExpired` fires |
| Explicit logout | Timer cleared, tokens + expiry cleared |
| Page reload with stored session | `AuthProvider` mount calls `startProactiveRefresh()` |
| AuthProvider unmount | Cleanup calls `stopProactiveRefresh()` |

## Verification Results

- **TypeScript type-check:** `npx tsc --noEmit` -- exit 0, zero errors
- **Test suite:** `npx vitest run` -- 19/19 PASS (3 test files)
  - `src/i18n/i18n.test.ts` -- 5 tests
  - `src/api/client.test.ts` -- 9 tests
  - `src/screens/AccountEditorScreen.test.tsx` -- 5 tests
- **Production build:** `npm run build` -- exit 0, 49 modules transformed

All existing tests continue to pass; no regressions introduced. The proactive
timer logic does not interfere with the existing reactive 401 refresh path --
the two mechanisms are complementary and share the same `refreshAccessToken()`
implementation which now handles timer rescheduling automatically.
