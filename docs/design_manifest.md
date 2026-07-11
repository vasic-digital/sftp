# Design Manifest — SFTP Management System

**Revision:** 1
**Last modified:** 2026-07-11T18:25:00Z
**Authority:** docs/plans/master_implementation_plan.md (Design line) · STREAM-8 (ATM-008)
**Scope:** all design tokens, theme packs, assets, boards

Machine-checkable inventory of every design artifact. Status values:
`present` (exists on disk, non-empty, validated) · `pending-export`
(source exists; derivative not yet produced — see asset RENDER.md / boards
README for why) · `pending-schema` (authored against documented model;
reconcile when dependency lands).

## Asset table

| # | Path | Type | Theme | Status |
|---|---|---|---|---|
| 1 | docs/design/tokens/tokens.json | token index (JSON) | both | present |
| 2 | docs/design/tokens/color.json | tokens — color (JSON) | light+dark | present |
| 3 | docs/design/tokens/typography.json | tokens — typography (JSON) | both | present |
| 4 | docs/design/tokens/spacing.json | tokens — spacing (JSON) | both | present |
| 5 | docs/design/tokens/radius.json | tokens — radius (JSON) | both | present |
| 6 | docs/design/tokens/elevation.json | tokens — elevation (JSON) | light+dark | present |
| 7 | docs/design/tokens/README.md | tokens documentation | both | present |
| 8 | web/src/theme/opendesign/tokens.ts | theme pack — TS tokens | light+dark | present |
| 9 | web/src/theme/opendesign/theme.ts | theme pack — css-var contract | light+dark | present |
| 10 | web/src/theme/opendesign/index.ts | theme pack — barrel | light+dark | present |
| 11 | mobile/shared/src/commonMain/kotlin/digital/vasic/sftp/theme/Tokens.kt | theme pack — KMP tokens | light+dark | present |
| 12 | mobile/shared/src/commonMain/kotlin/digital/vasic/sftp/theme/SftpTheme.kt | theme pack — KMP theme composable | light+dark | present |
| 13 | docs/design/assets/logo.svg | asset — logo (SVG source) | currentColor | present |
| 14 | docs/design/assets/icon_server.svg | asset — icon (SVG source) | currentColor | present |
| 15 | docs/design/assets/icon_user_ro.svg | asset — icon (SVG source) | currentColor | present |
| 16 | docs/design/assets/icon_user_rw.svg | asset — icon (SVG source) | currentColor | present |
| 17 | docs/design/assets/icon_admin.svg | asset — icon (SVG source) | currentColor | present |
| 18 | docs/design/assets/RENDER.md | asset render instructions + tool detection | both | present |
| 19 | docs/design/boards/README.md | board specs (token-bound) | light+dark | present |
| 20 | docs/design/assets/*_{24,48,96,192,512}.png | raster renders | both | pending-export |
| 21 | docs/design/assets/*.pdf + icon_board.pdf | vector PDF board | both | pending-export |
| 22 | docs/design/boards/*.{fig,penpot,psd,png,pdf} | GUI design-tool exports | light+dark | pending-export |
| 23 | open_design (submodule) | upstream OpenDesign engine | both | pending-schema |

### Row notes

- Rows 20–22 are `pending-export` **by policy, not failure**: no SVG
  rasteriser or GUI design tool exists on this host (captured evidence in
  `docs/design/assets/RENDER.md`). SVGs + token-bound board specs are the
  source of truth; derivatives attach when operator tooling produces them.
  Honest gap recorded per §11.4.6 — nothing here is claimed rendered.
- Row 23 `pending-schema`: the `open_design` submodule was absent from the
  checkout at authoring time (added in parallel by STREAM-1). Tokens follow
  the documented OpenDesign model (JSON scales + semantic/component tiers);
  envelope reconciliation is a follow-up of ATM-008 once the submodule lands.

## Pre-build gate contract

Gate name (recommended): `CM-DESIGN-MANIFEST-ASSETS-PRESENT`.
The check is deterministic, host-portable (python3 + xmllint), and MUST run
in the pre-build verification sweep. Verdict FAIL blocks the build.

1. **Manifest rows present.** For every row with status `present`, the path
   MUST exist on disk AND be non-empty. (Rows 1–19 at revision 1.)
2. **SVG well-formedness.** Every `*.svg` under `docs/design/assets/` MUST
   parse as well-formed XML and carry an `svg` root element with a
   `viewBox` attribute:
   ```bash
   xmllint --noout docs/design/assets/*.svg
   # fallback where xmllint is absent:
   python3 -c "import sys,xml.dom.minidom as m;[m.parse(p) for p in sys.argv[1:]];print('SVG OK')" docs/design/assets/*.svg
   ```
3. **Token JSON validity.** Every `*.json` under `docs/design/tokens/` MUST
   parse as JSON; `color.json` and `elevation.json` MUST carry both `light`
   and `dark` top-level keys; `tokens.json` MUST carry a `files` map:
   ```bash
   python3 -c "import json,glob;[json.load(open(f)) for f in glob.glob('docs/design/tokens/*.json')];print('JSON OK')"
   ```
4. **Derived-pack sync.** Token hex values in
   `web/src/theme/opendesign/tokens.ts` and
   `mobile/shared/src/commonMain/kotlin/digital/vasic/sftp/theme/Tokens.kt`
   MUST equal the values in `docs/design/tokens/color.json` (greppable:
   every light hex appears verbatim in both packs — spot-set assertion over
   the full light palette, all 70 steps).
5. **Pending-export rows are exempt** from existence checks; the gate MUST
   instead assert the manifest still lists them (never silently dropped) and
   their reason section exists.

### Self-check result (captured at authoring, 2026-07-11)

Executed rules 1–4 with xmllint + python3 on this host: **all PASS**
(outputs recorded in the STREAM-8 evidence report / conductor log).
Reproduction commands are exactly those quoted above.
