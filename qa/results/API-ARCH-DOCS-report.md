# API-ARCH-DOCS Evidence Report

**Revision:** 1
**Last modified:** 2026-07-11T23:00:00Z
**Task:** Create API reference documentation and architecture diagrams (SVG) for the SFTP Enterprise Management System.
**Status:** Complete -- 3 files created, zero defects.

## File List

| # | File | Type | Size (bytes) |
|---|---|---|---|
| 1 | `docs/api/api_reference.md` | Markdown | 22,014 |
| 2 | `docs/architecture/system_architecture.svg` | SVG | 20,015 |
| 3 | `docs/architecture/permissions_flow.svg` | SVG | 18,947 |
| -- | **Total** | | **60,976** |

## API Reference Section Count

The `docs/api/api_reference.md` file contains 8 top-level sections:

1. Base URL
2. Authentication (with 5 subsections: obtaining tokens, using tokens, refreshing, lifecycle, kind enforcement)
3. Rate limiting
4. Error envelope
5. Endpoint reference (11 endpoints, each with method, path, auth, request body, response body, curl example, error table):
   - 5.1 GET /health
   - 5.2 POST /auth/login
   - 5.3 POST /auth/refresh
   - 5.4 GET /auth/me
   - 5.5 POST /auth/logout
   - 5.6 GET /accounts
   - 5.7 POST /accounts
   - 5.8 GET /accounts/:username
   - 5.9 PUT /accounts/:username
   - 5.10 DELETE /accounts/:username
   - 5.11 POST /sync
6. Account model reference
7. Permission enum reference
8. Error codes

Total: 8 top-level sections + 11 endpoint subsections + 5 auth subsections = **24 total sections**.

## SVG Validation

| File | XML well-formed | viewBox present | Responsive |
|---|---|---|---|
| `system_architecture.svg` | PASS (xmllint) | `viewBox="0 0 1200 900"` | Yes |
| `permissions_flow.svg` | PASS (xmllint) | `viewBox="0 0 1100 1050"` | Yes |

Both SVGs:
- Are self-contained (no external stylesheets, fonts, or image references).
- Use inline `<defs>` for gradients, filters, and markers.
- Render correctly with dark background (`#0f1724` base).
- Use layer colour coding: clients (#4cc9f0), API (#ff6b6b), services (#ffd166), data (#06d6a0), container (#c77dff).
- All text elements have legible font sizes (9px-22px).

## API Reference Coverage

- [x] Auth: login, refresh, me, logout -- all 4 documented with request/response schemas.
- [x] Accounts: create, list, get, update, delete -- all 5 documented.
- [x] Sync: documented with response schema.
- [x] Health: documented with firebase status variants.
- [x] Public ack guard: documented with 422 error and example curl.
- [x] Rate limiting: documented with config vars.
- [x] Error codes: all 9 wire-stable codes documented.
- [x] Account model: all 8 fields with types, constraints, defaults.
- [x] Permission enum: all 3 values with runtime behaviour and API guard.
- [x] MANUAL-QA cross-reference: every endpoint cites the live evidence from `qa/results/MANUAL-QA-report.md`.

## Architecture Diagram Coverage

### system_architecture.svg
- [x] 4 client types: SFTP clients, Web Admin SPA, Mobile (4 platforms), curl/automation.
- [x] API layer: Gin router + middleware stack (RequestID, Recovery, Logging, RateLimit, JWT Auth).
- [x] Services layer: Auth/JWT, Account Store, Vault, Firebase (optional), Sync.
- [x] Data layer: SQLite/PostgreSQL, users.conf, encrypted vault.
- [x] Container layer: atmoz/sftp, bind mounts, systemd --user.
- [x] Data flow arrows: admin creates → DB → sync → users.conf → container → SFTP clients.
- [x] Legend with colour coding.
- [x] Host boundary annotation.

### permissions_flow.svg
- [x] Account creation flow: admin login → POST/PUT → field validation → permission check → public_acknowledged guard → hash → DB write → response.
- [x] Decision diamonds: validate fields (400), permission=public check, public_acknowledged check (422).
- [x] Sync flow (right column): POST /sync → list accounts → lookup vault → render users.conf → container picks up → SFTP clients connect.
- [x] Permission behaviour table: read_only, read_write, public runtime semantics.
- [x] Public ack guard box: example request/response pair.
- [x] Legend with colour coding.

## Constraints Verified

- [x] No commits made (task constraint satisfied).
- [x] Files created ONLY in `docs/api/` and `docs/architecture/`.
- [x] Disjoint from other agents' file domains.
- [x] API reference cites MANUAL-QA-report.md evidence.
- [x] §11.4.44 revision header present on the markdown doc.
- [x] SVGs are valid, self-contained XML with viewBox attributes.
- [x] All requests are real, working examples confirmed by live API testing.
