# GAP-004 -- Screenshots in User Manual

**Revision:** 1
**Last modified:** 2026-07-12T00:00:00Z

## Summary

Replaced the placeholder "Screenshots (to be added)" section in `docs/guides/user_manual.md` with actual screenshot references backed by 11 Playwright-captured PNG images.

## What was done

1. Created `docs/guides/assets/` directory to house screenshot PNGs.
2. Copied 11 existing Playwright screenshots from `qa/results/stream4/screenshots/` into `docs/guides/assets/`.
3. Rewrote section 10 of the user manual with markdown image syntax, descriptive captions, and collapsible dark-theme variants.
4. Updated the table of contents entry for section 10.
5. Bumped the document revision from 1 to 2.

## Screenshots included

| File | Description | Size |
|---|---|---|
| `login-light.png` | Super-admin login screen (light theme) | 16 KB |
| `login-dark.png` | Super-admin login screen (dark theme) | 16 KB |
| `dashboard-light.png` | Account list dashboard (light theme) | 42 KB |
| `dashboard-dark.png` | Account list dashboard (dark theme) | 43 KB |
| `account-new-light.png` | New account creation form (light theme) | 33 KB |
| `account-new-dark.png` | New account creation form (dark theme) | 33 KB |
| `account-new-public-guard-light.png` | Public-access confirmation guard (light theme) | 43 KB |
| `account-edit-light.png` | Account editor with permissions (light theme) | 35 KB |
| `account-edit-dark.png` | Account editor with permissions (dark theme) | 35 KB |
| `settings-light.png` | Settings panel (light theme) | 34 KB |
| `settings-dark.png` | Settings panel (dark theme) | 34 KB |

## Light theme coverage

All six screens (login, dashboard, account-new, account-edit, settings, public-guard) have light-theme screenshots with accompanying captions.

## Dark theme coverage

Five screens (login, dashboard, account-new, account-edit, settings) include dark-theme variants in collapsible `<details>` blocks. The public-guard screen has only the light variant.

## Focus on SFTP user experience

- **Dashboard** -- shows accounts with permission levels (read_only / read_write), the core SFTP management view.
- **Account editor** -- shows the permission selector, the central control for least-privilege enforcement.
- **Public guard** -- shows the explicit confirmation dialog, the programmatic enforcement of public-never-default.

## SFTP client screenshots (deferred)

The SFTP server was not reachable at time of writing (`sftp -P 7721 alice@127.0.0.1` returned `Connection refused`). Subsection 10.2 is marked as pending and states the server was unreachable with the exact error. CLI/FileZilla/WinSCP screenshots will be added when the server is next running with test accounts.

## Verification

- All 11 PNG files are present in `docs/guides/assets/` (confirmed via `ls -la`).
- Section 10 heading matches the TOC entry (both read "Screenshots").
- All markdown image references use relative paths (`assets/<file>.png`), correct for the document's location at `docs/guides/user_manual.md`.
- Document revision bumped: 1 -> 2.

## Files modified

- `docs/guides/user_manual.md` -- Section 10 replaced, TOC updated, revision bumped.
- `docs/guides/assets/` -- New directory containing 11 PNG screenshots.
