> **Base agent rules:** `constitution/AGENTS.md` — READ IT FIRST.
> The base file is authoritative for any topic not covered here.
> Project-specific rules below extend them; they never weaken them.

---

## SFTP Service — Agent Instructions

Enterprise SFTP management system (amended 2026-07-11; classification: project-specific).
Application code lives here: `api/` (Go/Gin), `web/` (React/TS), `mobile/` (KMP),
`config/` (YAML/JSON), `deploy/` (rootless Podman compose + systemd --user),
`scripts/` (bash), `tests/` + `qa/` (full matrix, Challenges, HelixQA).

Operating model for any agent (conductor or subagent):

1. **Fetch before edit** (§11.4.37): `git fetch --all --prune` is the first git action.
2. **Subagent-driven by default** (§11.4.20/§11.4.70): multi-step work is dispatched to
   dedicated subagents with tight disjoint file scopes per
   `docs/plans/master_implementation_plan.md` (streams STREAM-1..STREAM-11, items ATM-001..ATM-011).
3. **Labels** (§11.4.182): every dispatch description starts with `(T<n>/main - sftp)`.
4. **No raw commits**: only `scripts/commit_all.sh` commits; only `scripts/push_all.sh` pushes
   (all 4 upstreams, §2.1). NEVER force-push (§11.4.113).
5. **Anti-bluff** (§11.4): a PASS / "done" claim without captured positive evidence
   (real command output, real test run, real container round-trip) is rejected. Metadata-only
   and config-only PASSes are defects.
6. **Secrets** (§11.4.10): never tracked; `.env` git-ignored; test scripts never print secrets.
7. **Containers**: rootless Podman only, via the `containers` submodule — no docker, no sudo (§11.4.161).
8. **Service control**: `systemctl --user` only.
9. **Task tracking**: `docs/Issues.md` (status/type per §11.4.15/§11.4.16); closures migrate
   atomically to `docs/Fixed.md` (§11.4.19) with type-aware vocabulary (§11.4.33).
10. All work happens in the project root — never inside the `constitution` submodule
    (which is read-only inherited governance; changes there follow §11.4.26 separately).
