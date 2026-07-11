# SFTP Project — Status Summary

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

Two-audience digest of `docs/Status.md` (§11.4.56). Regenerated on every Status.md change.

---

## Page 1 — For the project team

**What we are building.** An enterprise-grade SFTP management system: a secure SFTP server (atmoz/sftp in rootless Podman) wrapped by a Go REST API, a web admin console, and mobile apps — with account/permission management, audit logging, backups, and full automated testing.

**What works today.** Nothing user-facing yet — and we say so on purpose. The project is in its first build phase: foundations (submodules, environment, compose), the design system, and this documentation set are in progress. No component has passed validation, so no "done" claims exist anywhere in our docs.

**What is next.** The API and account/permission system come first, then the web console and mobile apps, then Firebase and release hardening. Every step ships only with real captured proof (test transcripts, container round-trips, screenshots) — never a bare claim.

**Team actions.** None required from the team right now; work is proceeding through parallel build streams tracked in the project plan.

---

## Page 2 — For software engineers

- **Phase:** Phase 1 — parallel streams (see `docs/CONTINUATION.md` §1/§3).
- **Plan:** `docs/plans/master_implementation_plan.md` (11 streams).
- **Active streams:** STREAM-1 (ATM-001 infra), STREAM-8 (ATM-008 design), STREAM-10 (ATM-010 docs, this doc set).
- **Status table:** `docs/Status.md` — all 7 component rows PENDING, zero operator-blocked.
- **Sync engine:** Docs Chain contexts under `.docs_chain/contexts/` (issues_sync, fixed_sync, status_sync, continuation_sync, readme_links); `docs_chain verify --all` is the deterministic gate (§11.4.50).
- **Binding anchors:** §11.4.44 (revision headers), §11.4.45/§11.4.56 (this doc pair), §11.4.65 (md→html/pdf exports), §11.4.106 (Docs Chain), §11.4.123 (rock-solid proof or deep research), §11.4.185 (manual QA final confirmation before any tag).
- **Release gate:** tag `sftp-0.1.0-dev-*` (§11.4.151) only after full-suite retest (§11.4.40) + manual QA (§11.4.185).

---

_Source of truth: `docs/Status.md` (Revision 1)._
