# Design Boards

**Revision:** 1
**Last modified:** 2026-07-11T18:25:00Z
**Authority:** docs/design_manifest.md · docs/plans/master_implementation_plan.md

## Board set

The design-board set for the SFTP management system (each board: light + dark
variant, desktop 1440×900 / mobile 390×844 where applicable):

| # | Board | Frames | Consumed by |
|---|---|---|---|
| 1 | Login | desktop, mobile | web + KMP sign-in screens |
| 2 | Dashboard | desktop, mobile | service status, instance list, quick actions |
| 3 | Account editor | desktop, mobile | users.conf account CRUD (RO/RW/admin badges) |
| 4 | Mobile list | mobile | account list item anatomy + permission chips |

## Source-of-truth policy

- **Authoritative:** `docs/design/tokens/*.json` (tokens) +
  `docs/design/assets/*.svg` (iconography). Boards are *compositions* of
  those two — any board element's color/spacing/typography MUST trace to a
  token (OpenDesign provenance, §11.4.162/§11.4.190).
- **Export policy (Figma / PenPot / PSD):** produced by **operator tooling**
  (GUI design apps) and attached here when produced. Per the master plan:
  "Figma/PenPot/PSD as source-of-truth exports where tooling allows."
- **Never block on unavailable GUI tools.** This build host has no design
  GUI and no SVG rasteriser (see `docs/design/assets/RENDER.md` tool-detection
  table). Boards are therefore currently represented by: (a) the token set,
  (b) the SVG icon set, and (c) the layout specs below. That is an honest,
  recorded gap (§11.4.6) — not a bluff: no board PNG is claimed to exist.

## Board layout specs (token-bound, implementation-ready)

Until GUI exports land, each board is specified textually so the web/mobile
streams can implement directly; every measure is a token reference.

### 1. Login

- Centered card: `surface_elevated`, `radius.card` (lg), `elevation.1` →
  hover `elevation.2`, padding `inset.modal` (6 = 24px).
- Logo (logo.svg) 48px top, `stack.loose` (24px) gap to title
  `headline.small` ("SFTP Admin"), subtitle `body.medium` `text.secondary`.
- Inputs: height `touch_target_min` (48px), `radius.input`, border
  `border`, focus ring `focus_ring` 2px outline-offset 2px.
- Primary button: `accent` bg / `accent_on` text, `radius.button`,
  height 48px, label `label.large`.

### 2. Dashboard

- Page gutter `gutter.page` (24px); section gap `gutter.section` (32px).
- Header bar: logo 24px + wordmark `title.large`; theme toggle right.
- Stat cards row (instances / accounts / transfers): `inset.card` (20px),
  `radius.card`, `elevation.1`; numbers `display.small`, labels `label.medium`
  `text.secondary`.
- Instance list rows: icon_server.svg 24px tinted `accent`, name `title.medium`
  (mono family for host:port), status chip `radius.chip` + success/warning/error
  roles.

### 3. Account editor

- Two-column form on desktop (label column 160px), single column mobile.
- Permission segmented control: three options — read-only (icon_user_ro),
  read-write (icon_user_rw), admin (icon_admin) — icons 20px in `accent`.
- `public` toggle: default OFF, warning copy `warning.main` +
  `warning.surface` banner when enabled (matches plan rule: public is never
  default and requires explicit acknowledgement).
- Footer actions: secondary button (cancel) + primary (save), `stack.default`
  gap (16px), `elevation` none (flat bar with top `border`).

### 4. Mobile list (account list)

- List item height 72px, `inset.control` (12px) vertical padding.
- Leading: avatar circle `radius.avatar` with user initial on
  `primary.100`/`primary.200` (light/dark).
- Title `body.large` mono for username; subtitle `body.small` `text.secondary`
  (home path).
- Trailing: permission chip — ro = `info` roles, rw = `success` roles,
  admin = `primary` roles.
- Divider `border` 1px, inset from avatar edge.

## Validation

Boards, once exported, enter the §11.4.170 host-rendered pixel-proof flow
(per screen × state × {light,dark}) and the §11.4.190 website-quality gates.
Today, only the specs above exist — they are token-consistent by construction
(every measure cites a token), which the web/mobile streams can verify at
implementation time.
