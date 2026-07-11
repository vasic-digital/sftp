# SFTP Project — Fixed (closed items)

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

Archive of closed workable items, tracked per §11.4.19 (fixed-document column alignment) and §11.4.33 (type-aware closure vocabulary).

**Migration rule (atomic, §11.4.19):** when an item in `docs/Issues.md` reaches a terminal status — `Fixed (→ Fixed.md)` for Type `Bug`, `Implemented (→ Fixed.md)` for Type `Feature`, `Completed (→ Fixed.md)` for Type `Task`, or `Obsolete (→ Fixed.md)` per §11.4.90 — it moves into this file **in the same commit**: the heading + full body leave `Issues.md`, disappear from `docs/Issues_Summary.md` (open-only), and appear in `docs/Fixed_Summary.md` (closed-only). No item may exist in both files.

**Entry format:** every heading carries a `**Status:**` line (terminal closure value) and a `**Type:**` line (`Bug | Feature | Task`) within 8 non-blank lines, plus the evidence citation (test log / captured proof) that justified closure. Items with `reopens_count > 0` additionally carry a `docs/issues/<ATM-NNN>/Reopens.md` history per §11.4.55.

---

_No closed items yet. The enterprise build-out opened on 2026-07-11; this archive will receive its first entry when the first workable item closes with captured evidence (§11.4.123 rock-solid proof)._
