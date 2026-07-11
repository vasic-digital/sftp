# REVIEW-B: Web Admin React/TS SPA — Code Review Report

**Date:** 2026-07-11  
**Reviewer:** Claude (subagent)  
**Scope:** `web/src/` (all TS/TSX), `web/package.json`, `web/tsconfig*.json`, `web/vite.config.ts`, `web/vitest.setup.ts`, `web/index.html`, `web/scripts/screenshots.mjs`  
**Test status:** 19/19 vitest tests GREEN (3 test files, 0 failures)  
**Verdict:** GO with 3 LOW-severity findings. No critical or medium issues. No secrets in client code. No XSS vectors.

---

## Area 1: API Client — 401 Silent Refresh, Token Storage

### Finding 1 (LOW — token-storage-security)
- **File:line:** `web/src/api/client.ts:21-22`, `web/src/api/client.ts:46-48`, `web/src/api/client.ts:54-57`
- **Description:** Access and refresh tokens are stored in `localStorage`, which is readable by any JavaScript running on the same origin. In the event of a successful XSS injection (e.g., via a compromised dependency), both tokens are exfiltratable. HttpOnly cookies would prevent script access to the token value.
- **Fix suggestion:** Consider moving to HttpOnly cookie-based auth (requires backend cooperation) or, at minimum, document this as a known tradeoff for the SPA architecture. The current approach is standard for SPAs and the rest of the codebase correctly scopes localStorage keys (`sftp.*`).

### Finding 2 (LOW — no-server-logout)
- **File:line:** `web/src/api/client.ts:177-179`, `web/src/auth/AuthContext.tsx:39-42`
- **Description:** `logout()` clears tokens from `localStorage` client-side but never informs the server. The refresh token remains valid server-side until it expires naturally. If an attacker obtains a refresh token before logout, they can still use it.
- **Fix suggestion:** Add a `POST /auth/logout` endpoint that invalidates the refresh token server-side, and call it from `logout()` (fire-and-forget, with `clearTokens()` called regardless of the server response).

### No issues found in:
- 401 silent refresh logic (`request<T>` method, lines 133-155): correct single-retry with serialized refresh (`tryRefresh` at lines 123-130 deduplicates concurrent 401s). Test `serializes concurrent 401s into a single refresh round-trip` confirms the contract.
- Token refresh stores both new access and refresh tokens, and the retry picks up the new access token via `getAccessToken()`.
- `Content-Type` auto-detection (lines 137-139): correctly only adds `application/json` when body is present and no Content-Type already set.
- `encodeURIComponent()` on all username-bearing URL segments (lines 190, 203, 211).

---

## Area 2: Auth Context Provider — Token Lifecycle

### Finding 3 (LOW — no-proactive-refresh)
- **File:line:** `web/src/auth/AuthContext.tsx:15` (and `web/src/api/types.ts:33` — `expires_in` field defined but unused)
- **Description:** The `TokenPair.expires_in` field (seconds until expiry) is defined in the type contract and returned by the server, but never consumed by the client. The client only reacts to 401 responses (reactive refresh). Every API call near token expiry incurs a 401 → refresh → retry round-trip latency.
- **Fix suggestion:** Set a `setTimeout` in `AuthProvider` (or `ApiClient`) to proactively refresh ~60 seconds before `expires_in` elapses. Store `expiresAt = Date.now() + expires_in * 1000` alongside the tokens.

### No issues found in:
- `AuthProvider` correctly wires `onSessionExpired` callback (lines 18-27) and cleans up on unmount (line 24-26).
- `RequireAuth` correctly redirects unauthenticated users to `/login` with return-path in `location.state` (lines 7-9).
- `LoginScreen` redirects already-authenticated users away from `/login` (lines 26-31) and honors the return path.
- Initial auth state reads from `localStorage` which is correct for session persistence across page reloads.

---

## Area 3: Screens — State Coverage

### Finding 4 (LOW — error-conflated-with-empty)
- **File:line:** `web/src/screens/DashboardScreen.tsx:26-28`
- **Description:** On fetch error, `setAccounts([])` is called (line 27), which triggers the empty-state message "No accounts yet. Create one to get started." (line 83). The user cannot distinguish between "server has zero accounts" and "the request failed." The error state IS set (`setError` at line 26), but the empty-state card overrides the visual hierarchy.
- **Fix suggestion:** Do NOT set `accounts` to `[]` on error. Keep `accounts` as `null` (loading) or the previous successful value. The error alert above the table already comunicates the failure; showing stale/empty data below it is misleading.

### No issues found in:
- **LoginScreen**: covers checking/ok/down health states, sessionExpired warning, error, busy (submitting), already-authenticated redirect.
- **AccountEditorScreen**: covers loading (edit mode), loadError, error (with 422 special-casing), busy (submitting), public-ack guard (warning + checkbox conditional, submit disabled when unacknowledged), username-required validation, password hint context (new vs edit).
- **SettingsScreen**: covers saved feedback (auto-clearing after 2.5s), theme preference buttons (light/dark/system), API base override.

---

## Area 4: Public-Account Guard — Client-Side Mirror of Server 422

**GO — zero findings in this area.**

- `assertPublicAcknowledged()` (`web/src/api/client.ts:72-76`) throws `ApiError(422)` synchronously.
- `createAccount()` and `updateAccount()` both call the guard before the fetch (lines 194, 202).
- `AccountEditorScreen` enforces the guard at three levels: (a) submit handler check (lines 58-61), (b) submit button disabled attribute (line 204), (c) clearing the ack checkbox when switching away from public permission (line 132).
- Test `createAccount blocks unacknowledged public permission before any fetch` confirms zero network calls for blocked requests.
- Server-side mock in `screenshots.mjs` (lines 80-82) independently enforces the same 422 contract.
- Permission defaults to `read_write`, never `public` (line 19 in AccountEditorScreen, confirmed by test).

---

## Area 5: i18n — Key Completeness, English-First

### Finding 5 (LOW — dollar-sign-replacement-bug)
- **File:line:** `web/src/i18n/index.ts:24`
- **Description:** The `t()` function uses `String.prototype.replace()` for parameter interpolation. The second argument to `replace()` interprets `$`-prefixed patterns as special replacement tokens: `$&` (whole match), `$'` (post-match), `$`` (pre-match), `$1`-`$9` (capture groups). If a param value passed to `t()` contains a literal `$` followed by one of these characters, the replacement text will be corrupted. For example: `t('dashboard.deleteConfirm', { username: 'user$1' })` would produce an incorrect string.
- **Fix suggestion:** Escape `$` characters in the replacement value before passing to `.replace()`: `String(replacement).replace(/\$/g, '$$$$')`.

### No issues found in:
- 67 keys in the English dictionary covering all UI surfaces (app, nav, common, login, dashboard, table, permission, editor, settings, auth).
- `as const` assertion on the dictionary provides full type-safety for `I18nKey` (line 98).
- `t()` falls back to the English dictionary when the active locale is missing a key (line 22). Falls back to the raw key string when no dictionary has it (line 22).
- Test `every dictionary value is non-empty` verifies data integrity.
- Test `keeps English active for unknown locales` verifies locale fallback.

---

## Area 6: OpenDesign — Light/Dark Token Correctness

**GO — zero hardcoded values in CSS. One minor inline-style finding below.**

### Finding 6 (LOW — hardcoded-layout-values)
- **File:line:** `web/src/screens/AccountEditorScreen.tsx:97`, `web/src/screens/SettingsScreen.tsx:25,40,58`
- **Description:** Inline `style={{ maxWidth: 560 }}` uses a hardcoded pixel value outside the OpenDesign token system. The spacing tokens define values up to `--sftp-space-32` (128px), and this `560px` is outside that scale. It is a layout constraint, not a spacing or color value, but it is still ad-hoc.
- **Fix suggestion:** Define a CSS class (e.g., `.card-narrow`) in `app.css` with `max-width` referencing a design token, or add a `maxWidthForm` semantic token to the spacing scale. If 560px is intentionally a one-off value, document why.

### No issues found in:
- `app.css` uses exclusively `var(--sftp-*)` CSS variables for colors, typography, spacing, radius, elevation, and fonts. No raw hex codes, no raw pixel font-sizes, no raw spacing values.
- `tokens.ts` defines complete light and dark palettes with proper luminance inversion. Role tokens map consistently between themes (same semantic meaning, theme-appropriate luminance).
- `ThemeProvider.tsx` correctly injects the combined light+dark stylesheet once (line 23-27), listens for OS-level color-scheme changes (lines 47-50), and flips `data-theme` on `<html>` (line 56).
- `buildThemeStylesheet()` binds `:root, [data-theme="light"]` and `[data-theme="dark"]` selectors (theme.ts:74-76).
- **Correction to earlier draft:** LoginScreen h1 is inside a `.login-card` and renders as a standard `<h1>`. The `.page-head h1` rule (app.css:243-247) only applies inside `.page-head`. The login card h1 gets browser-default sizing. This is acceptable for a login page where the h1 is "SFTP Admin" and a `.hint` tagline — it is not a data-table heading. The visual distinction is intentional.

---

## Area 7: Test Quality — 19 Vitest Tests

**GO — zero bluff-capable tests in the suite. Coverage gaps noted below.**

### Strengths
- `client.test.ts` (9 tests): covers login, auth header, 401→refresh→retry, refresh-failure cleanup, concurrent-401 dedup, public-ack guard, guard-before-fetch, password-never-in-response, 204→undefined.
- `AccountEditorScreen.test.tsx` (5 tests): covers default permission, conditional ack checkbox, blocked submit, full public-ack flow (end-to-end with mock fetch), edit-mode data loading.
- `i18n.test.ts` (5 tests): covers key resolution, param interpolation, unknown-key fallback, unknown-locale fallback, non-empty values.
- All tests use behaviorally meaningful assertions (token values, fetch call counts, header contents, DOM element presence/state, mock body inspection). No test PASSes on metadata-only or absence-of-error.

### Coverage Gaps (not findings — informational)
- No component tests for `LoginScreen`, `DashboardScreen`, or `SettingsScreen`.
- No tests for `AuthContext` provider or `ThemeProvider`.
- No test for network-failure path in `request<T>` (the `catch` in `refreshAccessToken` at line 116 is untested — the mock always resolves).
- No test for non-JSON error response body in `parseError`.
- No test for `RequireAuth` redirect behavior.

---

## Area 8: XSS Vectors, Input Sanitization, Secrets

**GO — zero findings.**

- **XSS:** React's JSX auto-escaping protects all user-provided values rendered via `{expression}` syntax. No `dangerouslySetInnerHTML` usage anywhere in the codebase. Usernames, account names, and all API response data flow through JSX escaping.
- **URL encoding:** `encodeURIComponent()` used on all username-bearing URL segments in `ApiClient` (lines 190, 203, 211) and `DashboardScreen` (line 117). React Router's `useParams` provides URL-decoded values, but these are only used for display (escaped by JSX) and API calls (re-encoded by `ApiClient`).
- **Input sanitization:** No client-side validation beyond `trim()` on username and required-field checks. The server is the authoritative validator. This is architecturally correct for an admin SPA — client-side validation is a UX enhancement, not a security boundary.
- **Password handling:** Password is held in React component state only, sent over HTTPS to the API, never stored in `localStorage`, never logged, never returned by the API (`Account` type excludes `password` field). The test `parses account responses (never expects a password field)` confirms the API contract.
- **Secrets audit:** No hardcoded API keys, tokens, credentials, or secrets found in any source file. The `screenshots.mjs` mock tokens (`screenshot-access-token`, `screenshot-refresh-token`) are clearly labeled as non-production test fixtures. `VITE_API_BASE_URL` is the only env var consumed — it is a non-secret build-time config value.
- **CSRF:** Not applicable. Bearer tokens in the `Authorization` header are not automatically attached by browsers, so CSRF attacks cannot exploit them.
- **Content Security Policy:** `index.html` does not define a CSP meta tag or header. This is not a finding for an admin SPA behind a reverse proxy (the proxy should set CSP headers), but worth noting for production deployment.

---

## Summary

| Severity | Count | Area |
|----------|-------|------|
| CRITICAL | 0 | — |
| HIGH | 0 | — |
| MEDIUM | 0 | — |
| LOW | 6 | Token storage (L1), no-server-logout (L2), no-proactive-refresh (L3), error-conflated-with-empty (L4), dollar-sign-replacement-bug (L5), hardcoded-layout-values (L6) |

**Overall assessment:** The web SPA is well-architected. The API client handles 401→refresh→retry correctly with concurrent-401 deduplication. The public-account guard is enforced at three layers (client assertion, form validation, submit disable). All styles flow through OpenDesign CSS variables. No XSS vectors, no secrets in client code, and all 19 vitest tests are behaviorally meaningful. The six LOW findings are polish items — none block release.

**Recommendation:** Address the six LOW findings in a follow-up stream. No pre-release blockers.
