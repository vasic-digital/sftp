# STREAM-4 — ATM-004 React/TypeScript Admin SPA — Report

**Status:** DONE
**Date:** 2026-07-11
**Scope:** `web/` only (no files touched outside; no git operations performed)

## Summary

Full Vite + React 18 + TypeScript SPA for the SFTP admin console, consuming the
existing OpenDesign token pack (`web/src/theme/opendesign/`) with a light/dark
theme toggle, English-first i18n (`t(key)` helper, zero hardcoded UI strings),
and the exact verified API contract (no invented endpoints). Build, tests, and
the Playwright host-rendered visual-proof harness all GREEN.

## Files created

- `web/package.json`, `web/vite.config.ts` (dev proxy `/api` → `:7722`, `__APP_VERSION__` define, vitest config), `web/tsconfig.json` + `tsconfig.app.json` + `tsconfig.node.json`, `web/index.html`, `web/vitest.setup.ts`, `web/src/vite-env.d.ts`
- `web/src/main.tsx`, `web/src/App.tsx` (router + guards)
- `web/src/api/types.ts`, `web/src/api/client.ts` (Bearer auth, serialized single-flight silent refresh on 401 → retry once → `onSessionExpired`, base URL via `VITE_API_BASE_URL` default `/api/v1` + per-browser override, client-side public-ack guard mirroring server 422)
- `web/src/i18n/en.ts`, `web/src/i18n/index.ts`
- `web/src/theme/ThemeProvider.tsx` (injects OpenDesign stylesheet, `data-theme` flip, system preference)
- `web/src/auth/AuthContext.tsx`, `web/src/components/Layout.tsx`, `web/src/components/RequireAuth.tsx`
- `web/src/screens/LoginScreen.tsx` (health banner + error states), `DashboardScreen.tsx` (accounts table, edit/delete, Sync button, count/status), `AccountEditorScreen.tsx` (new+edit; permission defaults to `read_write`, public requires acknowledgement checkbox before submit is enabled), `SettingsScreen.tsx` (theme, API base override, about/version)
- `web/src/styles/app.css` — consumes ONLY `--sftp-*` OpenDesign CSS variables
- Tests: `web/src/api/client.test.ts` (9), `web/src/i18n/i18n.test.ts` (5), `web/src/screens/AccountEditorScreen.test.tsx` (5)
- `web/scripts/screenshots.mjs` (Playwright harness + contract-faithful mock API)

## How to run

```bash
cd web
npm install
npm run dev          # dev server :5173, proxies /api → :7722
npm run build        # tsc -b + vite build  → exit 0
npm test             # vitest run            → 19/19 PASS
npm run screenshots  # build + host-rendered capture of every route × {light,dark}
```

`VITE_API_BASE_URL` overrides the default `/api/v1` at build time; the Settings
screen overrides per-browser at runtime.

## Test results

- `npm run build` → exit 0 (49 modules, tsc strict clean)
- `npm test` → **19/19 PASS** (client refresh logic, concurrent-401 single-flight, refresh-failure session expiry, public-ack guard client-side 422 with zero fetch, 204 delete, response parsing without password, i18n fallback/interpolation, editor guard UX + edit-mode load)
- `npm run screenshots` → **11 PNGs, zero console/page errors** (any runtime error fails the run)

## Host-rendered visual proof (§11.4.170)

`web/qa/results/stream4/screenshots/`: `login-{light,dark}.png`, `dashboard-{light,dark}.png`, `account-new-{light,dark}.png`, `account-edit-{light,dark}.png`, `settings-{light,dark}.png`, `account-new-public-guard-light.png`. Vision-verified: dashboard table renders accounts/badges; dark theme binds correctly; public-guard state shows warning + unchecked acknowledgement with disabled submit.

## Notes / NEEDS_CONTEXT

- None blocking. Playwright chromium downloaded successfully (no fallback needed).
- `node_modules/`, `dist/`, and `qa/` outputs should be covered by `.gitignore` (conductor owns git).
