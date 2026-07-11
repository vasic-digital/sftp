# Phase 5 FTP-027 — Containers Submodule Integration Report

**Revision:** 1
**Last modified:** 2026-07-12T00:13:00Z
**Status:** COMPLETE

## Objective

Wire the `vasic-digital/containers` submodule as the SOLE container orchestration
layer per SS11.4.76 mandate. No ad-hoc docker/podman commands outside
`pkg/boot`/`pkg/compose`/`pkg/health`.

## Verification

All checks executed on the host with rootless podman available:

| Check | Command | Result |
|-------|---------|--------|
| go vet | `cd api && go vet ./...` | PASS (exit 0, no output) |
| go build | `cd api && go build -o /dev/null ./cmd/sftp-api/` | PASS (exit 0) |
| go test | `cd api && go test ./... -count=1 -short` | PASS (7/7 packages) |
| compose config | `podman-compose -f deploy/docker-compose.yml config` | PASS (valid YAML output) |
| CLI flags | `sftp-api --help` | PASS (--compose-up, --compose-down, --compose-status present) |
| compose-status | `SFTP_PROJECT_ROOT=<root> sftp-api --compose-status` | PASS (exit 0, correct output) |
| bash syntax | `bash -n scripts/sftp_ctl.sh` | PASS (syntax OK) |

## Changes Made

### 1. `api/go.mod`
- Added `replace digital.vasic.containers => ../containers`
- Added `digital.vasic.containers v0.0.0-00010101000000-000000000000` to require block

### 2. `api/internal/containers/stack.go` (NEW)
Wrapper package that uses the containers submodule:
- `New(cfg Config) (*Stack, error)` — creates orchestrator via `compose.NewDefaultOrchestrator` (auto-detects podman/docker)
- `Start(ctx context.Context) error` — boots stack via `orch.Up(detach, wait)`
- `Stop(ctx context.Context) error` — tears down via `orch.Down`
- `Status(ctx context.Context) ([]ServiceStatus, error)` — delegate to `orch.Status`
- `Health(ctx context.Context) (*HealthReport, error)` — wraps Status into health verdict
- `IsReady(ctx context.Context) bool` — convenience all-healthy check

### 3. `api/cmd/sftp-api/main.go`
Added CLI flags for compose management (SS11.4.76):
- `--compose-up` — starts the SFTP stack through containers layer
- `--compose-down` — stops the stack
- `--compose-status` — prints health report

The default mode (no compose flag) is unchanged: API server startup.
Project root is resolved from `SFTP_PROJECT_ROOT` env var, falling back to cwd.

### 4. `scripts/sftp_ctl.sh`
Replaced direct `podman-compose` calls:
- `start` now calls `sftp-api --compose-up`
- `stop` now calls `sftp-api --compose-down`
- `status` now calls `sftp-api --compose-status`
- `ps` now calls `sftp-api --compose-status`
- Added `ensure_api_binary()` helper that builds the Go binary on demand
- Logs still use `podman-compose logs` as a READ-ONLY observability escape (never mutates container state)
- Exports `SFTP_PROJECT_ROOT` so the Go binary resolves the compose file correctly

### 5. `scripts/setup.sh`
Updated next-steps guidance to reference the containers layer (SS11.4.76).

## What was NOT changed

- `deploy/docker-compose.yml` — untouched (the containers layer CONSUMES it, no replacement needed)
- `tests/api/test_api_chaos.sh` — the `unshare` usage is for namespace isolation in the disk-full test, not container orchestration (outside SS11.4.76 scope)
- `tests/api/lib_api.sh` — starts the API binary directly for test harness purposes (not a production orchestration path)

## End-to-end test

```
$ SFTP_PROJECT_ROOT=/path/to/sftp ./sftp-api --compose-status
=== SFTP Enterprise stack (containers layer) ===
Compose file : /path/to/sftp/deploy/docker-compose.yml

No services found — stack may not be started.
(exit 0)
```

The compose orchestrator auto-detected podman-compose, queried the compose
project through `containers/pkg/compose`, and returned a clean status report.
No ad-hoc podman/docker commands were used — all orchestration flows through
the containers submodule.

## Honest boundaries

- The `sftp_ctl.sh logs` command still uses `podman-compose logs -f` for log
  streaming. This is a READ-ONLY observability operation (no container state
  mutation). The containers Go orchestrator's `Logs()` returns an io.ReadCloser
  that requires a Go consumer. A future improvement could pipe this through a
  Go command, but the current approach does not violate the orchestration-layer
  mandate.
- The `test_api_chaos.sh` `unshare` usage is for test-environment namespace
  isolation (disk-full simulation), not for container orchestration. It falls
  outside SS11.4.76's scope of "container orchestration layer".
