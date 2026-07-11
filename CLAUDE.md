## INHERITED FROM constitution/CLAUDE.md

All rules in `constitution/CLAUDE.md` (and the `constitution/Constitution.md` it references) apply unconditionally.
Project-specific rules below extend them — they do NOT weaken any universal clause. When this file disagrees with the constitution submodule, the constitution wins.

@constitution/CLAUDE.md

---

## SFTP Service — Project-Specific Rules

**Amendment (2026-07-11, classification: project-specific per §11.4.17):** the former rule
"no Go/Rust/Python application code lives here" is SUPERSEDED. This project is now an
enterprise SFTP management system and application code DOES live here:

- `api/` — Go REST API (Gin Gonic), account + permission management, super-admin auth.
- `web/` — React/TypeScript admin SPA (OpenDesign tokens, light/dark).
- `mobile/` — Kotlin Multiplatform clients (Android / iOS / HarmonyOS / AuroraOS).
- `config/` — YAML/JSON server + account configuration schemas and examples.
- `deploy/` — container compose (rootless Podman) + systemd `--user` units.
- `scripts/` — bash management (service ctl, setup, backup, firebase config, commit/push wrappers).
- `tests/`, `qa/` — full test matrix, Challenges banks, HelixQA suites.

Standing project rules:

- The SFTP server runs as `atmoz/sftp` via rootless Podman compose (`deploy/docker-compose.yml`).
  Rootful Docker / sudo is FORBIDDEN (§11.4.161). All container orchestration goes through the
  `containers` submodule (§11.4.76) — no ad-hoc docker/podman invocations outside its
  `pkg/boot`/`pkg/compose`/`pkg/health` layer.
- User configuration sources of truth: `config/accounts.yaml` (+ JSON), rendered to
  `users.conf` for the container by the API sync layer. `.env` (git-ignored, §11.4.10)
  holds host/runtime config; `.env.example` is the tracked template.
- SSH daemon port maps from `.env` `SFTP_PORT` (default 7721); API port `API_PORT` (default 7722).
- Permission model: per-account `read_only` | `read_write`; `public` access exists but is
  NEVER default and requires explicit acknowledgement (API + UI guard).
- Service management is user-scoped: `systemctl --user`, no root, no sudo.
- All commits go through `scripts/commit_all.sh` (never raw `git commit`); pushes fan out to
  github + gitlab + gitflic + gitverse via `scripts/push_all.sh` (§2.1); force-push strictly
  forbidden (§11.4.113).
- Development is subagent-driven (§11.4.20/§11.4.70) with parallel streams per
  `docs/plans/master_implementation_plan.md`; the task registry lives in `docs/Issues.md`.
