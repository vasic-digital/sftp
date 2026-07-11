# SFTP Project — CONTINUATION

**Revision:** 1
**Last modified:** 2026-07-11T18:35:00Z

## §1. Where we are

**PHASE:** Enterprise build-out — Phase 0 complete (ground truth + plan), Phase 1 (parallel streams) launching.

The project transforms from a basic `atmoz/sftp` compose stub (see `docs/research/mvp/MVP.md`)
into a full enterprise SFTP management system: Go/Gin REST API, account + permission management,
YAML/JSON config, super-admin auth, Web/Desktop/React + KMP mobile clients (Android/iOS/HarmonyOS/AuroraOS),
rootless-Podman ops via the `containers` submodule, full test matrix + Challenges + HelixQA,
Docs Chain synced documentation, OpenDesign UI (light/dark), Firebase integration, i18n (en first).

## §2. Live-state anchors

- **HEAD:** 8e01dff (pre-enterprise baseline; constitution init)
- **Branch:** main (all work merges to main per §11.4.42 iteration discipline; no force-push §11.4.113)
- **Remotes:** origin fan-out → github + gitlab + gitflic + gitverse (§2.1 multi-upstream push)
- **Host:** Go 1.26.2 · Node v22.19.0 · Podman 5.7.1 rootless (no docker — §11.4.161) · 64 GB RAM · ulimit -u 65536
- **Plan:** `docs/plans/master_implementation_plan.md` (Revision 1) — 11 streams
- **Issues:** `docs/Issues.md` — 11 stream work items ATM-001..ATM-011

## §3. Active work

| Stream | Item | Status | Scope (disjoint file ownership) |
|---|---|---|---|
| STREAM-1 | ATM-001 Infrastructure & Foundation | In progress | `.gitmodules`, `deploy/`, `.env.example`, `api/go.mod`, `.gitignore`, submodule dirs |
| STREAM-8 | ATM-008 Design system & assets | In progress | `docs/design/`, `web/src/theme/`, `mobile/shared/.../theme/` |
| STREAM-10 | ATM-010 Documentation | In progress | `docs/` (except plans owned here), `.docs_chain/` |

Queued (start after ATM-001 lands): ATM-002 (API), ATM-003 (config/permissions), ATM-006 (bash ops).
Queued (after API contract): ATM-004 (web), ATM-005 (mobile), ATM-007 (firebase).
Continuous: ATM-009 (tests/QA), ATM-011 (gates/review/release plumbing).

## §4. Terminal goal (this scope)

A fully validated enterprise SFTP management system: every stream closed with captured evidence,
full test matrix GREEN, docs synced, release tag `sftp-0.1.0-dev-*` (§11.4.151 prefixed naming)
pushed to all 4 upstreams. Manual QA final confirmation (§11.4.185) gates the tag.

## §5. Binding constraints (restated for resumption)

- Anti-bluff §11.4: captured positive evidence per PASS — no metadata-only/config-only PASS.
- Subagent-driven by default (§11.4.20/§11.4.70); ≥3 parallel streams with auto-backfill (§11.4.103).
- Rootless containers only (§11.4.161); systemctl --user; NO sudo/root.
- No secrets in git (§11.4.10); `.env` git-ignored.
- NEVER force-push (§11.4.113); merge-onto-latest-main for integration.
- No silent removal of existing components without operator confirmation (§11.4.122).

## §6. How to resume (any fresh session)

1. `git fetch --all --prune` (§11.4.37) — check `git log --oneline HEAD..@{u}`.
2. Read this file + `docs/plans/master_implementation_plan.md` + `docs/Issues.md`.
3. Check active subagent dispatches (`/tasks`) and background logs.
4. Continue the highest-priority open item per §11.4.42/§11.4.94 — never idle while actionable items exist.
