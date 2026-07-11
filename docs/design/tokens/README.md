# SFTP Design Tokens

**Revision:** 1
**Last modified:** 2026-07-11T18:25:00Z
**Authority:** docs/design_manifest.md · docs/plans/master_implementation_plan.md
**Scope:** global + semantic token tiers, both themes

## Model (OpenDesign)

Tokens follow the canonical OpenDesign token model: JSON files carrying
**scales** (global tier: raw values) and **roles/semantic** maps (semantic
tier: role -> scale step references). The **component tier** (button, input,
table...) is reserved in `tokens.json` and authored by the web/mobile streams
as components land.

> **Assumption (honest gap, §11.4.6):** the `open_design` submodule
> (`nexu-io/open-design`) was NOT present in the checkout when this set was
> authored (it is added in parallel by STREAM-1). The JSON structure was
> therefore designed from the documented OpenDesign token model and MUST be
> reconciled against the submodule schema once it lands — track under
> ATM-008 follow-up. No token *value* is expected to change; only envelope
> shape may need adapting.

## Files

| File | Contents |
|---|---|
| `tokens.json` | Top-level index: themes, file map, derived pack locations |
| `color.json` | `light` + `dark` — palettes primary/secondary/neutral/success/warning/error/info at steps 50..900 + semantic `roles` |
| `typography.json` | Font families (sans/mono), weights, 15-step scale (display/headline/title/body/label) |
| `spacing.json` | 4pt grid scale + semantic spacing roles |
| `radius.json` | Corner radius scale (0..9999) + semantic roles |
| `elevation.json` | Level 0-5 CSS box-shadows per theme + semantic roles |

## Conventions

- **Palette polarity.** Light theme scales run 50 (lightest) → 900 (darkest).
  Dark theme chromatic scales are luminance-inverted (50 darkest → 900
  lightest) so that (a) step 500 stays the primary accent in both themes and
  (b) surfaces always draw from the 50–200 range. Neutral follows the same
  inversion (dark `neutral.50` = `#0B1120` background).
- **Role references.** `roles` values are strings of form `<family>.<step>`
  or a literal hex (e.g. `#FFFFFF`); consumers resolve references at
  build/init time. `surface_elevated` in light is literal white because the
  neutral scale has no pure-white step.
- **Units.** px on web; 1:1 sp/dp mapping on mobile. Elevation levels map to
  Compose `shadowElevation = level * 2.dp`.
- **Touch targets.** `spacing.semantic.touch_target_min` = 48px (48 = 12×4),
  WCAG 2.2 target-size minimum.

## Brand rationale

- **Primary — indigo** (`#4F46E5` family): trust, security, admin surface of
  a credential-managed file service.
- **Secondary — teal** (`#0D9488` family): transfer/data-flow accent.
- **Neutral — slate**: enterprise chrome, AA-contrast pairs in both themes
  (text_primary on background ≥ 15:1; text_secondary ≥ 7:1; accent on
  accent_on ≥ 4.5:1 — spot-checked at authoring; full matrix validated by the
  host-rendered UI proof gate per §11.4.170 when components land).

## Derived packs

- Web: `web/src/theme/opendesign/` (TypeScript; css-variable contract).
- Mobile (KMP): `mobile/shared/src/commonMain/kotlin/digital/vasic/sftp/theme/`
  (Kotlin/Compose objects).

Both packs are *derived*: they mirror these JSON values verbatim. When a token
changes here, the packs are regenerated in the same commit (Docs Chain sync,
§11.4.106).

## Validation

Every JSON file is machine-checked by the pre-build design gate contract
(see `docs/design_manifest.md` → "Pre-build gate contract"): valid JSON,
required top-level keys, both themes present where applicable.
