## INHERITED FROM constitution/QWEN.md

All rules in `constitution/QWEN.md` (and the `constitution/Constitution.md` it references) apply unconditionally.
Project-specific rules below extend them — they do NOT weaken any universal clause. When this file disagrees with the constitution submodule, the constitution wins.

@constitution/QWEN.md

---

## SFTP Service — Project-Specific Rules (Qwen Code context)

This file is the Qwen Code carrier for the SFTP management system. Read `CLAUDE.md` and `AGENTS.md` in this directory for the full project-specific rules — every rule there binds Qwen Code exactly as it binds Claude Code.

This is an enterprise SFTP management system. Application code lives in:
- `api/` — Go REST API (Gin Gonic), account + permission management, super-admin auth.
- `web/` — React/TypeScript admin SPA (OpenDesign tokens, light/dark).
- `mobile/` — Kotlin Multiplatform clients (Android / iOS / HarmonyOS / AuroraOS).

Standing project rules (same as CLAUDE.md):
- Rootless Podman only, via the `containers` submodule — no docker, no sudo (§11.4.161).
- Service management: `systemctl --user` only.
- Commits via `scripts/commit_all.sh`; pushes via `scripts/push_all.sh` (all 4 upstreams, §2.1).
- NEVER force-push (§11.4.113).
- Anti-bluff (§11.4): every PASS / "done" claim requires captured positive evidence.
- Secrets never tracked; `.env` git-ignored (§11.4.10).

## Anti-Bluff — read first (cascaded from constitution §11.4)

Tests and Challenges exist for exactly one purpose: to confirm a feature genuinely works for a real end user, end-to-end. A test that passes while the feature is broken is a bluff test and is forbidden. CI green is necessary, never sufficient. See `CLAUDE.md`, `AGENTS.md`, and the constitution for the full anti-bluff mandate. Canonical authority: the Helix Constitution §11.4.
