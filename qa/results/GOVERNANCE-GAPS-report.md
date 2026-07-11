# GOVERNANCE-GAPS — Gap Fill Report

| Field | Value |
|---|---|
| **Run** | 2026-07-11 |
| **Scope** | Fill QWEN.md + GEMINI.md governance gaps across main project + submodules |
| **Files created** | 9 |
| **Files modified** | 0 |
| **Commits** | 0 (NEVER commit per operator instruction) |
| **Verification** | head -3 on every created file confirmed |

## Files created

| # | Path | Type | Pattern used |
|---|---|---|---|
| 1 | `QWEN.md` | project-root Qwen carrier | `constitution/QWEN.md` inheritance + SFTP project rules |
| 2 | `GEMINI.md` | project-root Gemini carrier | `constitution/GEMINI.md` inheritance + SFTP project rules |
| 3 | `filesystem/QWEN.md` | submodule Qwen pointer | `challenges/QWEN.md` — brief pointer, inherit constitution, read CLAUDE.md |
| 4 | `formatters/QWEN.md` | submodule Qwen pointer | Same pattern as challenges/QWEN.md |
| 5 | `i18n/QWEN.md` | submodule Qwen pointer | Same pattern as challenges/QWEN.md |
| 6 | `open_design/QWEN.md` | submodule Qwen pointer | Same pattern, but points to AGENTS.md (open_design has AGENTS.md as canonical, not CLAUDE.md) |
| 7 | `storage/QWEN.md` | submodule Qwen pointer | Same pattern as challenges/QWEN.md |
| 8 | `streaming/QWEN.md` | submodule Qwen pointer | Same pattern as challenges/QWEN.md |
| 9 | `watcher/QWEN.md` | submodule Qwen pointer | Same pattern as challenges/QWEN.md |

## Patterns followed

### Project-root QWEN.md
- Opens with `## INHERITED FROM constitution/QWEN.md` (matching CLAUDE.md pattern)
- Includes `@constitution/QWEN.md` import
- Restates SFTP project-specific rules from CLAUDE.md
- Includes anti-bluff covenant reference

### Project-root GEMINI.md
- Opens with `## INHERITED FROM constitution/GEMINI.md`
- Thin carrier: restates project identity, points to CLAUDE.md for full rules
- Follows the constitution/GEMINI.md "thin carrier" pattern

### Submodule QWEN.md (standard pattern)
- Opens with `# QWEN.md — Qwen Code context for this module`
- Has `## INHERITED FROM the Helix Constitution` section
- Has `## Read CLAUDE.md — it is mandatory` section
- Plain-text pointer, no auto-import directives (Qwen Code compatibility)
- Matches `challenges/QWEN.md` pattern exactly

### open_design/QWEN.md (special case)
- Points to `AGENTS.md` instead of `CLAUDE.md` because open_design/CLAUDE.md is just `@AGENTS.md` — AGENTS.md is the canonical agent instruction file for that submodule

## Remaining gaps

| Status | Detail |
|---|---|
| FILLED | All 9 missing files created |
| NONE | No remaining known governance file gaps |

## Integrity

- All inheritance pointers follow the Helix Constitution §11.4.35 pattern
- All submodule QWEN.md files stay fully decoupled (§11.4.28) — no project-specific context
- All files reference anti-bluff covenant (§11.4)
- Lockstep per §11.4.157: QWEN.md and GEMINI.md now exist alongside CLAUDE.md and AGENTS.md
