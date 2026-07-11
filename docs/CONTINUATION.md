# SFTP Project — CONTINUATION

**Revision:** 4
**Last modified:** 2026-07-11T23:00:00Z

## §1. Where we are

**PHASE:** Enterprise build-out — Phase 1 foundation + Phase 2 core COMMITTED + PUSHED (checkpoints c5e68b9, 6460e5e on all 4 upstreams); Phase 3 parallel client/QA streams: STREAM-4 (web) + STREAM-5 (mobile) + STREAM-7 (firebase) all DONE + independently verified; STREAM-9 (test-matrix) in progress (chaos fix running).

The project transforms from a basic `atmoz/sftp` compose stub (see `docs/research/mvp/MVP.md`)
into a full enterprise SFTP management system: Go/Gin REST API, account + permission management,
YAML/JSON config, super-admin auth, Web/Desktop/React + KMP mobile clients (Android/iOS/HarmonyOS/AuroraOS),
rootless-Podman ops via the `containers` submodule, full test matrix + Challenges + HelixQA,
Docs Chain synced documentation, OpenDesign UI (light/dark), Firebase integration, i18n (en first).

## §2. Live-state anchors

- **HEAD:** 6460e5e (FTP-002 Go API + FTP-003 config_schemas + FTP-006 bash ops + wrapper hardening) — pushed to github+gitlab+gitflic+gitverse; prior c5e68b9 (FTP-001/008/010 foundation) also pushed 4/4
- **Uncommitted (conductor owns the commit):** STREAM-4 web/ (DONE+verified, migrated to Fixed.md), STREAM-5 mobile/ (DONE+verified, migrated to Fixed.md), STREAM-7 api/internal/firebase/+api/router (DONE+verified+reviewed, migrated to Fixed.md), STREAM-9 tests/+qa/ (in progress)
- **Branch:** main (all work merges to main per §11.4.42 iteration discipline; no force-push §11.4.113)
- **Remotes:** origin fan-out → github + gitlab + gitflic + gitverse (§2.1 multi-upstream push)
- **Host:** Go 1.26.2 · Node v22.19.0 · Podman 5.7.1 rootless (no docker — §11.4.161) · 64 GB RAM · ulimit -u 65536
- **Plan:** `docs/plans/master_implementation_plan.md` (Revision 1) — 11 streams
- **Issues:** `docs/Issues.md` — 11 stream work items FTP-001..FTP-011

## §3. Active work

| Stream | Item | Status | Scope (disjoint file ownership) |
|---|---|---|---|
| STREAM-9 | FTP-009 Test matrix + QA banks | In progress (background) — chaos fix running; lifecycle evidence in qa/results/stream9/ | `tests/`, `qa/`, `docs/qa/` |

Done + verified (checkpoints c5e68b9 + 6460e5e): STREAM-1 FTP-001, STREAM-2 FTP-002 (core, 5/5 pkgs), STREAM-3 FTP-003, STREAM-6 FTP-006, STREAM-8 FTP-008, STREAM-10 FTP-010-partial.
Done + verified (2026-07-11, migrated to Fixed.md): STREAM-4 FTP-004 (19/19 vitest, 11 screenshots), STREAM-5 FTP-005 (7/7 tests ×2 deterministic), STREAM-7 FTP-007 (Admin SDK + review + fix, 7 tests + full suite GREEN).
Continuous: FTP-011 (gates/review/release plumbing — commit wrapper hardened + self-validated).
Conductor notes: compose `api.build` = `{context: .., dockerfile: api/Dockerfile}` (done); `backups/` + `service-account*.json` in .gitignore; commit_all.sh hardened (env.example exemption, code-scoped mutation scan, split secret audit) and self-validated. Coordination: cryptVault in-memory → after API restart accounts render `*` until password re-set (fail-closed, acceptable for MVP).

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
