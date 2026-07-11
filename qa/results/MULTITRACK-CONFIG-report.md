# Multi-Track Configuration Report — SFTP Project (host: nezha)

**Revision:** 1
**Last modified:** 2026-07-11T17:00:00Z
**Status:** active
**Classification:** project-specific (§11.4.17)

## Summary

Multi-track development configuration created for the SFTP project on host
`nezha` per Helix Constitution §11.4.187. The config file
`config/multitrack/nezha.yaml` is valid and parseable by the engine's own
`multitrack_config.sh` loader (MT_TRACK_COUNT=2, all fields resolved).

## Config structure

### Schema

| Field | Value |
|---|---|
| schema_version | 1 |
| host.hostname | nezha |
| host.machine_id | 2b81a82f970a4429 |

### Tracks

| # | ID | Role | Branch | Mount | Worktree Path | Focus |
|---|---|---|---|---|---|---|
| 1 | track-1 | main | main | /mnt/track1 | /mnt/track1/sftp/ | Primary — conductor + commit/push + reviews |
| 2 | track-2 | feature | main | /mnt/track2 | /mnt/track2/sftp/ | Secondary — features + fixes + tests |

### Aliases

| # | Alias | Kind | Config Directory |
|---|---|---|---|
| 1 | default | native | ~/.claude |
| 2 | claude4 | native | ~/.claude-claude4 |
| 3 | deepseek | provider | ~/.claude-prov-deepseek |
| 4 | kimi-for-coding | provider | ~/.claude-prov-kimi-for-coding |
| 5 | xiaomi | provider | ~/.claude-prov-xiaomi |
| 6 | opencode | provider | ~/.claude-prov-opencode |
| 7 | openrouter | provider | ~/.claude-prov-openrouter |

### Conductor

`conductor: ""` (empty string) — no single alias is designated as the
conductor. Any session not bound to a track worktree acts as the conductor.
The operator currently drives sessions from the `deepseek` provider alias.

### Fallback signatures

Two canonical rate-limit transcript signatures configured:
- `"apiErrorStatus":429`
- `"isApiErrorMessage":true`

### Worktree subdir

`worktree_subdir: sftp` — all tracks resolve to `/mnt/track<N>/sftp/`.

### Protected drives

- `S4EWNS0X108183F` (nvme0n1) — system drive (/) — never touched

## Validation

```
Engine loader parse:     PASS  (MT_TRACK_COUNT=2)
Track fields resolved:   PASS  (all 2 tracks have id/mount/role/branch/serial)
Conductor resolved:      PASS  (empty string — valid)
Fallback sigs resolved:  PASS  (2 signatures)
Worktree subdir:         PASS  ("sftp")
YAML syntax:             PASS  (parsed by engine AWK loader without error)
```

## Honest gaps (§11.4.6)

### GAP-1: No physical track drives

The multitrack engine is designed for projects with dedicated physical NVMe
drives per track (as in the Atmosphere reference project). The SFTP project
is a code-only project (Go API + React SPA + Kotlin Multiplatform + bash
scripts) that does NOT have dedicated physical drives for parallel tracks.

**Impact:** The `drive_serial` values in the config (`sftp-track1-logical`,
`sftp-track2-logical`) are logical identifiers, not physical drive serials.
The engine's `mt_plan` function will report both tracks as STATUS=ABSENT
because no physical drive with those serials exists. The drive-prep step
in `multitrack_bootstrap.sh` (step 5) will produce informational notes but
will NOT block bootstrap (exit code remains 0).

**Mitigation:** The operator must manually create the track directories:
```bash
mkdir -p /mnt/track1/sftp /mnt/track2/sftp
```
Or mount physical drives at `/mnt/track1` and `/mnt/track2` if desired.

### GAP-2: Track directories do not exist

`/mnt/track1/` and `/mnt/track2/` do not currently exist on host `nezha`.
The config declares the intended layout but physical provisioning is an
operator step (§11.4.21 — the agent cannot autonomously create mount points
outside the project tree).

### GAP-3: No device_pool or lease_policy

The SFTP project has no Android test devices. The `device_pool` and
`lease_policy` config sections (used by `multitrack_device_lock.sh` for
§11.4.176(B) capability-aware deadlock-proof device arbitration) are
omitted. This is correct for this project — not a missing configuration.

### GAP-4: Engine is for headless Claude Code workers

The engine's `multitrack_sessions.sh` spawns headless `claude -p
--output-format stream-json` workers. This requires:
- The `claude` CLI installed and on PATH
- Each alias authenticated (OAuth or API key)
- Per-alias `CLAUDE_CONFIG_DIR` and `CLAUDE_CODE_OAUTH_TOKEN` set

These are host-level prerequisites, not config-level. Verification that
each declared alias can spawn a headless session is an operator-gated
acceptance test (§11.4.187 honest boundary — per-subscription quota-isolation
proof requires live tokens).

### GAP-5: Only 2 tracks (minimum viable)

Per §11.4.103(B), the engine targets >=3 parallel background streams with
auto-backfill. The current config defines only 2 tracks due to the SFTP
project's smaller scope. Additional tracks can be added as the project
grows by extending the `tracks:` block.

## Files created

| File | Path | Purpose |
|---|---|---|
| Config | `config/multitrack/nezha.yaml` | Per-host track/alias/conductor config |
| README | `config/multitrack/README.md` | Operator guide for configuring and starting |
| Report | `qa/results/MULTITRACK-CONFIG-report.md` | This evidence report |

## Bootstrap readiness

The config satisfies the engine's minimum requirements:
- `MT_TRACK_COUNT >= 1` (2 tracks)
- `schema_version: 1`
- `host.hostname` resolves to current host
- `aliases` block present with at least one alias
- `conductor` key present (empty string = valid)

The bootstrap command:
```bash
cd /run/media/milosvasic/DATA4TB/Projects/sftp
MT_REPO_ROOT="$PWD" \
  bash constitution/scripts/multitrack/multitrack_bootstrap.sh
```
Will pass steps 1-4 (cwd-hook install, config validation, orchestrator
reconcile, status check). Step 5 (drive-prep informational) will note
that both tracks have no matching physical drives — informational, not a
bootstrap failure.

## References

- §11.4.187 — Automatic multi-track ruler orchestration
- §11.4.178 — Track-qualified identity
- §11.4.176 — Exactly-once claim + device-lock arbitration
- §11.4.179 — Corruption-isolated git streams
- §11.4.182 — Track+branch work-stream identity labels
- §11.4.192 — Continuous multi-track auto-backfill
- §11.4.103 — Continuous parallel-stream working routine
- Engine: `constitution/scripts/multitrack/`
- Reference config: `constitution/scripts/multitrack/README.md`
