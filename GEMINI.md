## INHERITED FROM constitution/GEMINI.md

All rules in `constitution/GEMINI.md` (and the `constitution/Constitution.md` it references) apply unconditionally.
Project-specific rules below extend them — they do NOT weaken any universal clause. When this file disagrees with the constitution submodule, the constitution wins.

---

## SFTP Service — Gemini CLI context

This file is the Gemini CLI carrier for the SFTP management system. It is one of the five canonical agent context carriers (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`, `GEMINI.md`) this project maintains per §11.4.157. Read `CLAUDE.md` in this directory for the full project-specific rules — every rule there binds Gemini CLI exactly as it binds Claude Code.

This is an enterprise SFTP management system. Application code lives in `api/` (Go/Gin REST API), `web/` (React/TypeScript admin SPA), `mobile/` (KMP clients), and supporting infrastructure (`config/`, `deploy/`, `scripts/`, `tests/`, `qa/`).

Standing project rules: rootless Podman only via `containers` submodule (§11.4.161); `systemctl --user` only; commits via `scripts/commit_all.sh`, pushes via `scripts/push_all.sh` (all 4 upstreams, §2.1); NEVER force-push (§11.4.113); anti-bluff (§11.4) — every PASS requires captured positive evidence; secrets never tracked (§11.4.10).

This file is a thin carrier — the full rule set is in `constitution/Constitution.md` (canonical) and the sibling carriers. Project-specific extensions live in `CLAUDE.md` and `AGENTS.md`.
