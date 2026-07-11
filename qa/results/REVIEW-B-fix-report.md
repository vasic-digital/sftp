# REVIEW-B Fix Report — LOW-severity findings

**Date:** 2026-07-11
**Scope:** `web/` directory only
**Review:** `qa/results/REVIEW-B-web.md` (3 LOW findings addressed)

---

## Finding 4 — Dashboard error-empty conflation (FIXED)

**File:** `web/src/screens/DashboardScreen.tsx`

**Changes:**

1. Removed `setAccounts([])` from the `catch` block (line 27). On fetch error, `accounts` retains its previous value (`null` on first load, or the last successful array on reload). The error alert above the content area already communicates the failure.

2. Restructured the render ternary to distinguish three states with error-awareness:
   - `accounts === null && !error` — shows "Loading..."
   - `accounts !== null && accounts.length === 0 && !error` — shows "No accounts yet" empty state
   - `accounts !== null && accounts.length > 0` — shows the account table (with or without error alert above)
   - When `error` is set and `accounts === null`: renders nothing below the error alert (no misleading "Loading..." or "No accounts yet")

This ensures the user never sees "No accounts yet. Create one to get started." when the API request failed.

---

## Finding 5 — i18n `$` replacement escaping (FIXED)

**File:** `web/src/i18n/index.ts`

**Changes:**

In `t()` (line 24), replacement values are now escaped before being passed to `String.prototype.replace()`. The call:

```ts
String(replacement).replace(/\$/g, '$$$$')
```

converts each literal `$` in the replacement value to `$$`, which `String.prototype.replace()` interprets as a literal `$` rather than a special replacement pattern (`$&`, `$'`, `$\``, `$1`-`$9`). This prevents corrupted output when parameter values contain dollar signs (e.g., `t('dashboard.deleteConfirm', { username: 'user$1' })`).

---

## Finding 6 — Hardcoded `maxWidth: 560` outside OpenDesign (FIXED)

**Files changed:**

| File | Change |
|------|--------|
| `web/src/theme/opendesign/tokens.ts` | Added `layout: { formMaxWidth: 560 }` to `SpacingTokens` interface and `spacing` constant |
| `web/src/theme/opendesign/theme.ts` | Added layout token export to `toCssVariables()` — emits `--sftp-layout-form-max-width: 560px` |
| `web/src/styles/app.css` | Added `.card-form { max-width: var(--sftp-layout-form-max-width); }` |
| `web/src/screens/AccountEditorScreen.tsx` | Replaced `style={{ maxWidth: 560 }}` with `className="card card-form"` |
| `web/src/screens/SettingsScreen.tsx` | Replaced three occurrences of `style={{ maxWidth: 560 }}` with `className="card card-form"` (preserving per-card `marginBottom` where present) |

The `560px` value is now defined once in the OpenDesign token layer and consumed via a CSS custom property, consistent with all other styling in the project.

---

## Verification results

| Step | Command | Result |
|------|---------|--------|
| TypeScript type-check | `cd web && npx tsc --noEmit` | exit 0, no errors |
| Vitest test suite | `cd web && npx vitest run` | 19/19 PASS (3 test files) |
| Production build | `cd web && npm run build` | exit 0, built in 722ms |

- tsc: clean
- vitest: 19 passed, 0 failed
- build: `dist/` produced successfully (index.html, CSS, JS)
