# Asset Rendering — SVG → PNG / PDF

**Revision:** 1
**Last modified:** 2026-07-11T18:25:00Z
**Authority:** docs/design_manifest.md

The SVG files in this directory are the **authoritative sources**. Raster
(PNG) and PDF artifacts are **derivatives** — regenerated on demand, never
hand-edited, committed only at release prep (§11.4.128 curated-evidence
policy + §11.4.30 no-versioned-build-artifacts).

## Host tool detection (captured 2026-07-11)

Command executed on this host:

```bash
which rsvg-convert inkscape convert magick
```

Result:

| Tool | Present | Path |
|---|---|---|
| `rsvg-convert` (librsvg) | NO | — |
| `inkscape` | NO | — |
| `convert` (ImageMagick 6) | NO | — |
| `magick` (ImageMagick 7) | NO | — |

`which xmllint python3` → both present (`/usr/bin/xmllint`, `/usr/bin/python3`,
Python 3.13.12).

**Honest gap (§11.4.6):** no SVG rasteriser exists on this host today, so PNG
renders were NOT produced by this stream — rendering is deferred to any host
with one of the toolchains below installed (all free, rootless-user
installable). Until then, the SVGs render natively in browsers, Android
(Compose `painterResource` via vector conversion), and design tools, so no
consumer is blocked. PNG export is tracked as pending-export rows in
`docs/design_manifest.md`.

## Install (pick one toolchain)

```bash
# Debian/Ubuntu/ALT (rootless-user: none of these need root beyond apt itself)
sudo apt-get install librsvg2-bin      # rsvg-convert (preferred, sharpest)
sudo apt-get install inkscape          # full editor + CLI export
sudo apt-get install imagemagick       # convert / magick (uses rsvg delegate when available)
```

## PNG renders (sizes: 24, 48, 96, 192, 512)

Output convention: `<name>_<size>.png` next to the source, e.g. `logo_192.png`.
Run from this directory.

```bash
SIZES="24 48 96 192 512"
SVGS="logo icon_server icon_user_ro icon_user_rw icon_admin"

# --- Option A: rsvg-convert (preferred) ---
for s in $SIZES; do for f in $SVGS; do
  rsvg-convert -w "$s" -h "$s" "$f.svg" -o "${f}_${s}.png"
done; done

# --- Option B: inkscape ---
for s in $SIZES; do for f in $SVGS; do
  inkscape "$f.svg" --export-type=png --export-filename="${f}_${s}.png" \
    --export-width="$s" --export-height="$s"
done; done

# --- Option C: ImageMagick 7 (magick) / 6 (convert) ---
for s in $SIZES; do for f in $SVGS; do
  magick -background none -density 384 "$f.svg" -resize "${s}x${s}" "${f}_${s}.png"
done; done
# IM6: replace 'magick' with 'convert'
```

Theme variants: the icons use `currentColor`, so themed PNGs need a tiny
wrapper SVG per theme, e.g. dark-on-transparent for the dark theme:

```bash
# example: render logo in dark-theme accent (#818CF8) at 512px
cat > /tmp/logo_dark.svg <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <g color="#818CF8"><use href="logo.svg"/></g>
</svg>
EOF
rsvg-convert -w 512 -h 512 /tmp/logo_dark.svg -o logo_dark_512.png
```

## PDF design board

Single-page vector board of all assets (for the docs/design/boards set):

```bash
# --- Option A: rsvg-convert per asset, then merge ---
for f in $SVGS; do rsvg-convert -f pdf "$f.svg" -o "$f.pdf"; done
# merge with pdfunite (poppler-utils) or python3 pypdf:
python3 - <<'EOF'
from pypdf import PdfWriter
w = PdfWriter()
for f in ["logo","icon_server","icon_user_ro","icon_user_rw","icon_admin"]:
    w.append(f"{f}.pdf")
w.write("icon_board.pdf")
EOF

# --- Option B: inkscape direct ---
inkscape logo.svg --export-type=pdf --export-filename=logo.pdf
```

## Figma / PenPot / PSD

Per the master plan: Figma/PenPot/PSD exports are produced by operator
tooling (GUI apps unavailable in this environment — see
`docs/design/boards/README.md`). Import path: open the SVG directly in
Figma/PenPot (both parse `currentColor` stroke icons); PSD via
Photoshop "Place" of the PDFs above. Source of truth remains SVG + tokens —
exports are attached artifacts, never edited.
