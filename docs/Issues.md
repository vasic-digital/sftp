# SFTP Project — Issues (workable items)

**Revision:** 7
**Last modified:** 2026-07-12T00:10:00Z

Tracked per §11.4.15/§11.4.16/§11.4.54. Status vocabulary: Queued | In progress | Ready for testing | In testing | Reopened | Operator-blocked | Fixed (→ Fixed.md) / Implemented (→ Fixed.md) / Completed (→ Fixed.md). Type: Bug | Feature | Task.

All 26 workable items FTP-001 through FTP-026 migrated to `docs/Fixed.md` per §11.4.19. Release: `sftp-0.1.0-dev-0.1.0`.

---

## Honest Gaps (§11.4.6 — structural/host limitations, not defects)

### §1. [GAP-001] HelixQA Go binary cannot build — upstream submodule maturity

**Status:** Operator-blocked
**Type:** Task
**Priority:** LOW

5 dependency submodules (DocProcessor, I-LLM, LLMProvider, LLMsVerifier, VisionEngine) added to project but are early-stage — HelixQA imports packages (`pkg/agent`, `pkg/parser`) not yet implemented upstream. Bash execution path proven: 161/163 GREEN.
**Scope:** `helixqa/`, `doc_processor/`, `llm_orchestrator/`, `llm_provider/`, `llms_verifier/`, `vision_engine/`.

### §2. [GAP-002] iOS KMP target — macOS-required

**Status:** Operator-blocked
**Type:** Task
**Priority:** LOW

iOS KMP compilation requires macOS with Xcode. Sources (3 .kt files in `iosMain/`) are correct and reviewable. This Linux host cannot compile Kotlin/Native iOS targets.
**Scope:** `mobile/shared/src/iosMain/`.

### §3. [GAP-003] HarmonyOS / AuroraOS KMP targets — no upstream support

**Status:** Operator-blocked
**Type:** Task
**Priority:** LOW

No upstream KMP target exists for HarmonyOS or AuroraOS. Scaffolding and README documentation present with port plans.
**Scope:** `mobile/shared/src/harmonyosMain/`, `mobile/shared/src/auroraosMain/`.

### §4. [GAP-004] User manual screenshots — placeholder

**Status:** Queued
**Type:** Task
**Priority:** LOW

User manual references screenshots not yet captured. Needs real SFTP client (FileZilla, WinSCP, sftp CLI) screenshots added to `docs/guides/user_manual.md`.
**Scope:** `docs/guides/user_manual.md`, `docs/guides/assets/`.
