# SFTP Project — Integration Status

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

**Scope:** whole-system integration status — every component/client/surface of the enterprise SFTP management system.
**Status vocabulary (§11.4.45):** PASS / FAIL / SKIP / PENDING / PENDING_FORENSICS / OPERATOR-BLOCKED. Every non-PENDING row MUST cite captured evidence (test log, recording, transcript path). Operator-blocked items surface first.

## Operator-blocked items

_None._

## Component status

| Component | Status | Evidence |
|---|---|---|
| SFTP container (atmoz/sftp, rootless Podman, port 7721) | PENDING | — (compose definition lands with FTP-001; live login test with FTP-003 container round-trip) |
| REST API (Go/Gin, port 7722) | PENDING | — (not yet built — FTP-002) |
| Web admin (React/TypeScript SPA) | PENDING | — (not yet built — FTP-004) |
| Mobile clients (KMP: Android/iOS/HarmonyOS/AuroraOS) | PENDING | — (not yet built — FTP-005) |
| Ops scripts (service ctl, setup, backup, systemd --user) | PENDING | — (not yet built — FTP-006) |
| Test matrix + Challenges + HelixQA | PENDING | — (gate suite in progress — FTP-009) |
| Documentation + Docs Chain sync | PENDING | — (first docs batch this revision — FTP-010; `docs_chain verify` not yet run) |

## Notes

- All rows are honestly PENDING: no user-facing component is built or validated yet (anti-bluff §11.4 — no invented PASS rows). Rows flip to PASS only with captured positive evidence per §11.4.5/§11.4.69.
- Live-state anchors: `docs/CONTINUATION.md` §2. Work plan: `docs/plans/master_implementation_plan.md`. Workable items: `docs/Issues.md`.
- This doc regenerates its `Status_Summary.md` companion + HTML/PDF exports on every status change (§11.4.45/§11.4.56) via the Docs Chain `status_sync` context (`.docs_chain/contexts/status_sync.yaml`).
