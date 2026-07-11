# sftp_ctl.sh — user guide

**Revision:** 1
**Last modified:** 2026-07-11T19:05:00Z

## Overview

`scripts/sftp_ctl.sh` is the control plane for the SFTP Enterprise compose
stack (`deploy/docker-compose.yml`: atmoz/sftp + postgres + management API).
It drives **rootless Podman only** (§11.4.161) — it prefers `podman-compose`
and falls back to `podman compose`; it never invokes rootful docker or sudo.
It also installs / uninstalls the **systemd --user** unit rendered from
`deploy/systemd/sftp.service.template` (the template's `@PROJECT_ROOT@`
placeholder is substituted with the real project path at install time, so no
absolute path is ever hardcoded — §11.4.177).

## Prerequisites

- bash ≥ 4, rootless `podman` + `podman-compose` (or `podman compose` plugin)
- `systemctl --user` available (for `install` / `uninstall` / the unit panel of `status`)
- `.env` present is optional — ports fall back to SFTP `7721` / API `7722`
  (`.env` is parsed as plain `KEY=VALUE` lines, never `source`d)

## Usage examples

```bash
scripts/sftp_ctl.sh start            # podman-compose up -d
scripts/sftp_ctl.sh status           # containers + SFTP_PORT/API_PORT listeners + unit state (always exit 0)
scripts/sftp_ctl.sh logs sftp        # follow only the atmoz/sftp service logs
scripts/sftp_ctl.sh ps               # compose ps table
scripts/sftp_ctl.sh restart          # down + up -d
scripts/sftp_ctl.sh stop             # podman-compose down

scripts/sftp_ctl.sh install          # render template → ~/.config/systemd/user/sftp.service, enable --now
scripts/sftp_ctl.sh uninstall        # disable --now + remove the unit (containers untouched)
```

## Edge cases

- **Stack never started** → `status` still exits 0 and says the compose project
  has no containers; port probes report `not-listening`. Status is
  informational by contract (used by the smoke test with nothing running).
- **No `ss`/`netstat`** → port state prints `unknown (no ss/netstat)` instead of failing.
- **Neither `podman-compose` nor `podman compose` installed** → any stack
  command exits `127` with the install hint (`pip install podman-compose`).
- **`.env` absent** → defaults `7721` / `7722` apply; no error.
- **`install` when the template is missing** → exit 1 naming the template path.
- **`uninstall` when the unit is absent** → idempotent no-op, exit 0.
- **Unknown command** → exit 2 + usage on stderr.

## Internal behaviour

1. Resolves the project root from the script's own location (`ROOT=../..` of the script).
2. `env_get` extracts `SFTP_PORT` / `API_PORT` from `.env` via grep+cut with
   inline-comment and quote stripping (the file is never executed).
3. `compose()` dispatches to `podman-compose -f deploy/docker-compose.yml` or
   `podman compose -f …` with the same argument vector.
4. `status` prints: compose `ps` output, per-port LISTENING/not-listening from
   `ss -ltn` (netstat fallback), and the user-unit enabled/active state.
5. `install` sed-renders `@PROJECT_ROOT@` (with `&`/`|` escaping) into
   `${XDG_CONFIG_HOME:-~/.config}/systemd/user/sftp.service` via a temp file +
   rename, then `daemon-reload` + `enable --now`. Boot-without-login
   (`loginctl enable-linger`) is printed as an operator decision — the script
   never touches it (§11.4.122).

## Related scripts

- `scripts/setup.sh` — create `.env` + data dirs before the first `start`.
- `scripts/backup.sh` — back up config/DB/users.conf (independent of stack state).
- `scripts/firebase_config.sh` — web Firebase config acquisition.
- Constitution: §11.4.161 (rootless containers), §11.4.177 (no hardcoded paths), §12 (host safety).

## Last verified

2026-07-11 — `bash -n` clean, shellcheck clean, `status` exit-0-with-no-stack
proven by `tests/test_scripts_smoke.sh`.
