# PHASE5-FTP023: Web SPA Production Build & Serve

**Revision:** 1
**Last modified:** 2026-07-12T00:42:00Z
**Status:** PASS

## Summary

Built the React/TypeScript web SPA for production and implemented static file
serving in the Go REST API with SPA client-side routing fallback. The SPA is
served from `web/dist/` and gated behind a `--serve-web` CLI flag or `SERVE_WEB`
environment variable.

## Files Modified

### api/internal/config/config.go

- Added `ServeWeb bool` field (gates SPA serving)
- Added `WebDistDir string` field (filesystem path to dist, default `"web/dist"`)
- Wired `SERVE_WEB` env var in `applyEnv()` (`"1"` or `"true"` enables)
- Wired `WEB_DIST_DIR` env var for custom dist directory
- Set default `WebDistDir: "web/dist"` in `Default()`

### api/cmd/sftp-api/main.go

- Added `--serve-web` CLI flag: `flag.Bool("serve-web", false, ...)`
- `run()` accepts `serveWeb bool` and sets `cfg.ServeWeb = true` when flag is active
- Flag takes precedence (OR logic with env var — either activates)

### api/internal/api/router.go

- Added `"os"` to imports
- Added `mountWebSPA(r *gin.Engine)` method called from `Engine()` when `s.cfg.ServeWeb` is true
- `r.Static("/assets", dist+"/assets")` — serves JS/CSS/images
- `r.GET("/", handler)` — serves the SPA entrypoint at root
- `r.NoRoute(handler)` — SPA fallback: non-API routes receive index.html
- API routes (`/api/*`) that don't match return proper JSON 404
- Index HTML content is preloaded at startup (`os.ReadFile`) and served via
  `c.Data()` to avoid `http.ServeFile` redirect behavior

## Smoke Test Results

All 10 checks passed on a live API instance started with `--serve-web`:

| # | Check | Result |
|---|-------|--------|
| 1 | `GET /api/v1/health` | 200 — `{"status":"ok","version":"0.1.0-dev",...}` |
| 2 | `GET /` | 200 — text/html, 798 bytes (SPA entrypoint) |
| 3 | `GET /index.html` | 200 — text/html, 798 bytes |
| 4 | `GET /accounts` | 200 — text/html, 798 bytes (SPA deep link) |
| 5 | `GET /settings` | 200 — text/html, 798 bytes (SPA deep link) |
| 6 | `GET /assets/index-Dr5hExJw.js` | 200 — text/javascript, 193,277 bytes |
| 7 | `GET /assets/index-DnXnEz8J.css` | 200 — text/css, 4,780 bytes |
| 8 | `GET /api/v1/nonexistent` | 404 — `{"code":"not_found","error":"endpoint not found"}` |
| 9 | `POST /api/v1/auth/login` | 400 — endpoint works, auth routing intact |
| 10 | `GET /api/v1/accounts` | 401 — auth middleware intact (no token) |

## Mode Gating Verification

| Condition | SPA served at `/` | API routes work |
|-----------|:-----------------:|:---------------:|
| `--serve-web` flag | 200 | Yes |
| `SERVE_WEB=1` env | 200 | Yes |
| Neither set | 404 | Yes |

## Build Verification

```
cd web && npm run build     → EXIT 0 (TypeScript tsc + Vite)
cd api && go vet ./...      → EXIT 0
cd api && go build ./cmd/sftp-api/ → EXIT 0
```

## Design Decisions

1. **Preloaded index.html**: The SPA entrypoint HTML is read once at startup
   and served from memory via `c.Data()`. This avoids `http.ServeFile`'s
   standard behavior of redirecting `/index.html` → `./`.

2. **API-aware NoRoute**: The SPA fallback explicitly checks for `/api` prefix
   before serving index.html. Unmatched API routes return a proper JSON 404
   (`{"code":"not_found","error":"endpoint not found"}`) instead of silently
   returning HTML.

3. **Mount-time WARN**: If the dist directory or index.html is missing at
   startup, the API logs a WARNING and skips SPA mounting (the API stays up,
   just without web serving).
