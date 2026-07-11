# REVIEW-A: Firebase Integration Code Review

**Review scope:** `api/internal/firebase/`, `api/internal/config/config.go` (Firebase lines),
`api/cmd/sftp-api/main.go` (Firebase wiring), `config_schemas/firebase.yaml`,
`docs/firebase/README.md`, `.env.example` (FIREBASE_* lines).

**Reviewed:** 2026-07-11 | **Verdict:** PASS WITH FINDINGS

**Summary:** 7 findings (0 critical, 1 high, 2 medium, 4 low). Zero credential leaks.
Config chain from env vars through Config struct to `firebase.New()` is complete.
The fail-fast and graceful-degrade contracts are correctly implemented and tested.

---

## Findings

### FINDING 1 -- HIGH -- Orphaned Firebase client (no runtime reachability)

**Severity:** HIGH
**File:** `api/cmd/sftp-api/main.go`, line 104--110
**Description:** `firebase.New()` returns a `*firebase.Client`, but the result is
discarded with `_`. The client is created, validated (fail-fast), and immediately
becomes unreachable:

```go
if _, err := firebase.New(ctx, firebase.Options{  // <-- result discarded
    Enabled:            cfg.FirebaseEnabled,
    ProjectID:          cfg.FirebaseProjectID,
    ServiceAccountPath: cfg.FirebaseServiceAccountPath,
}); err != nil {
    return err
}
```

**Evidence that the client is inaccessible downstream:**

- `api.NewServer` (`api/internal/api/router.go:36`) accepts
  `cfg *config.Config, st *store.Store, auth *authn.Service` -- no
  `*firebase.Client` parameter.
- A repo-wide grep for `firebase.Client` outside `internal/firebase/` returns
  zero usages.
- No health endpoint calls `firebase.Client.Verify()`.
- No middleware or handler calls `RecordCrash()`, `RecordEvent()`, or `RecordTrace()`.

**Impact:** An operator sets `FIREBASE_ENABLED=true`, the API starts and logs
`firebase: enabled (project <id>)`, but the subsystem has zero runtime effect.
`Verify()` is documented as available for health endpoints (`firebase.go:123`)
but no such endpoint exists. The fail-fast wiring works correctly, but the
"positive" path is unplugged -- a PASS-bluff at the subsystem-integration layer
per SS11.4/SS11.4.108 (SOURCE layer is green, RUNTIME layer is absent).

**Fix suggestion:** Either (a) thread `*firebase.Client` into `api.NewServer` and
wire `Verify()` into the `/api/v1/health` endpoint, making it available to
operators; or (b) document explicitly that the subsystem is infrastructure-only
at this phase and will be wired in a follow-up work item. Option (b) is acceptable
for an incremental delivery but MUST cite a tracked work item per SS11.4.6.

---

### FINDING 2 -- MEDIUM -- Config-schema key-name divergence from Go struct tags

**Severity:** MEDIUM
**File:** `config_schemas/firebase.yaml` lines 16-18 vs `api/internal/config/config.go` lines 53-59
**Description:** The YAML schema uses a nested structure:

```yaml
# config_schemas/firebase.yaml
firebase:
  enabled: false
  project_id: sftp-enterprise-dev
  service_account_path: ./secrets/...
```

But the Go `Config` struct uses flat top-level tags:

```go
// api/internal/config/config.go
FirebaseEnabled            bool   `yaml:"firebase_enabled"`
FirebaseProjectID          string `yaml:"firebase_project_id"`
FirebaseServiceAccountPath string `yaml:"firebase_service_account_path"`
```

If an operator writes an `API_CONFIG` YAML file copying the schema's nested
structure, `yaml.Unmarshal` (called from `config.Load` at config.go:105) will
silently NOT populate the firebase fields -- the nested keys don't match the
flat struct tags.

**Impact:** Silent misconfiguration. The API starts with firebase effectively
disabled (zero values: `Enabled=false`, `ProjectID=""`, `ServiceAccountPath=""`)
despite the operator thinking they configured it. The operator sees
`firebase: disabled` in the log with no explanation why their YAML was ignored.

**Fix suggestion:** Either (a) change the schema to use flat keys matching the
Go tags (`firebase_enabled`, `firebase_project_id`, `firebase_service_account_path`)
with a comment explaining that these are the top-level API config keys; or (b)
if nested grouping is desired, add a `Firebase` sub-struct to `Config` that
matches the nested YAML shape. Option (a) is simpler and keeps the existing
flat Go struct.

---

### FINDING 3 -- MEDIUM -- `detail` parameter silently discarded in telemetry stubs

**Severity:** MEDIUM
**File:** `api/internal/firebase/firebase.go`, line 168
**Description:**

```go
func (c *Client) RecordCrash(component, message string) {
    c.telemetryStub("crashlytics", component, message)  // message -> detail
}

func (c *Client) telemetryStub(surface, component, detail string) {
    ...
    c.log.Printf("firebase: %s hook received component=%s (...)", surface, component, surface)
    _ = detail   // line 168 -- the semantic payload is thrown away
}
```

`RecordCrash`'s `message` ("what crashed"), `RecordEvent`'s `name` ("what event"),
and `RecordTrace`'s `name` ("what trace") are all accepted by the public API but
discarded without logging. The function signature implies these identify what
happened, but an operator searching logs for a specific crash or event will find
only `component=test` with no further distinguishing information.

**Impact:** Loss of operator-useful information. Even in stub form, logging the
detail line ("note: Go Admin SDK has no ingestion API; %s=%s event logged only")
gives the operator a breadcrumb trail. Currently the breadcrumb names the surface
and component but not the specific event/crash/trace.

**Fix suggestion:** Include `detail` in the log format:

```go
c.log.Printf("firebase: %s hook received component=%s detail=%s (note: ...)",
    surface, component, detail)
```

Or, if the intent is to keep the log line short, at minimum log the first N chars.
The `_ = detail` line serves only to suppress the Go unused-variable error and is
a code-smell equivalent to a buried `// TODO` per SS11.4.27.

---

### FINDING 4 -- LOW -- Weak test assertion on disabled-client hook count

**Severity:** LOW
**File:** `api/internal/firebase/firebase_test.go`, line 45
**Description:**

```go
if !strings.Contains(out, "firebase: disabled") || strings.Count(out, "firebase: disabled") < 2 {
    t.Fatalf("hook calls on disabled client must log the disabled state, got %q", out)
}
```

The disabled-client path produces exactly 4 log lines containing the substring
`"firebase: disabled"`:
1. `New()` -> `"firebase: disabled"`
2. `RecordCrash(...)` -> `"... hook ignored (firebase: disabled) ..."`
3. `RecordEvent(...)` -> `"... hook ignored (firebase: disabled) ..."`
4. `RecordTrace(...)` -> `"... hook ignored (firebase: disabled) ..."`

The assertion requires >=2 occurrences. This PASSes if exactly 2 hooks fire
(out of the 3 hooks called), missing a regression where one hook silently becomes
a zero-op.

**Impact:** A future edit that breaks one of the three hook methods into a zero-op
(returns without calling `telemetryStub`) would not be caught by this test.

**Fix suggestion:** Tighten the assertion to exactly 4:

```go
if got := strings.Count(out, "firebase: disabled"); got != 4 {
    t.Fatalf("expected 4 'firebase: disabled' lines (1 init + 3 hooks), got %d:\n%s", got, out)
}
```

---

### FINDING 5 -- LOW -- No test coverage for nil-Logger fallback

**Severity:** LOW
**File:** `api/internal/firebase/firebase.go`, line 67-69
**Description:**

```go
logger := opts.Logger
if logger == nil {
    logger = log.Default()
}
```

This nil-safety path has zero test coverage. Every test in `firebase_test.go`
passes an explicit `Logger` (via `testLogger()`). A regression that removes
the nil-check would pass all tests but panic on `nil pointer` when an operator
initializes `firebase.New(ctx, Options{Enabled: false})` without a Logger.

**Fix suggestion:** Add a one-line test:

```go
func TestNewWithNilLoggerDoesNotPanic(t *testing.T) {
    _, err := New(context.Background(), Options{Enabled: false})
    if err != nil {
        t.Fatal(err)
    }
}
```

This takes sub-millisecond and covers the default-logger path.

---

### FINDING 6 -- LOW -- No test coverage for active-client telemetry logging

**Severity:** LOW
**File:** `api/internal/firebase/firebase.go`, line 166
**Description:** The active-client telemetry log format (`"firebase: %s hook received component=%s (note: Go Admin SDK has no %s ingestion API; event logged only)"`) is untested. All 7 tests exercise only the disabled path or the fail-fast init path.

The test package (`package firebase`) can construct a synthetic active client
without a real credential:

```go
logger, buf := testLogger()
c := &Client{active: true, log: logger}
c.RecordEvent("analytics", "user_signup", "test_event")
// assert buf contains "analytics hook received component=user_signup"
```

**Impact:** A formatting regression in the active-path log message would go
undetected until an operator deploys with `FIREBASE_ENABLED=true` and examines
log output.

**Fix suggestion:** Add a test that constructs a synthetic `&Client{active: true,
log: ...}` and calls each hook, asserting the log output format. This does not
require credentials -- the test makes `active=true` while leaving `app` and
`auth` nil, and the telemetry hooks don't touch those fields.

---

### FINDING 7 -- LOW -- Error wrapping exposes SDK error chain

**Severity:** LOW
**File:** `api/internal/firebase/firebase.go`, line 96
**Description:**

```go
return nil, fmt.Errorf("firebase: admin SDK init failed (check the service account JSON at %q): %w",
    opts.ServiceAccountPath, err)
```

The `%w` verb wraps the Firebase Admin SDK's internal error, making it
inspectable via `errors.Unwrap`. While the SDK's current error messages for
credential-parse failures are designed not to include key material (e.g.
`"failed to parse private key"` without the key bytes), the error chain is
fully exposed. If a future SDK version changes its error format to include
partial key data, this path would surface it.

**Impact:** Theoretical future risk. Current SDK versions are safe.

**Fix suggestion:** Replace `%w` with `%v` to break the error chain while still
logging the SDK's message. The operator-facing message already guides them to
check the file at the named path:

```go
return nil, fmt.Errorf("firebase: admin SDK init failed (check the service account JSON at %q): %v",
    opts.ServiceAccountPath, err)
```

The cost is that a caller cannot programmatically distinguish SDK-init errors
via `errors.Is`/`errors.As`, but no caller does this currently (the error is
only consumed in `main.go:54` as a fatal log line).

---

## Positive Findings

| # | Area | Detail |
|---|---|---|
| P1 | Security -- git-ignore | `.gitignore` covers `secrets/` (line 12), `service-account*.json` (line 18), and `firebase-service-account*.json` (line 19) -- triple coverage. `git ls-files` confirms zero tracked service-account files. |
| P2 | Security -- no stale refs | Zero references to a legacy `FIREBASE_CREDENTIALS_FILE` env var anywhere in the codebase. Naming is consistent throughout. |
| P3 | Security -- credential discipline | Only the file PATH is logged (never the content). `SUPERADMIN_PASSWORD` and `JWT_SECRET` are consumed from env and never printed (per main.go:24-25). |
| P4 | Correctness -- graceful degrade | `FIREBASE_ENABLED=false` (default) -> logs `"firebase: disabled"`, all hooks are safe no-ops, API starts normally. Verified by `TestDisabledIsInertAndLogs`. |
| P5 | Correctness -- fail-fast | Every misconfiguration path returns a clear, actionable error naming the exact env var or path: empty project-id (line 78), empty SA path (line 81), missing file (line 85), directory-not-file (line 88), SDK init failure (line 96). |
| P6 | Correctness -- compile/vet | `go build ./internal/firebase/` and `go vet ./internal/firebase/` both exit 0. |
| P7 | Test quality -- 7 contracts covered | Tests cover: disabled-is-inert, no-project-id, no-SA-path, missing-file, directory-instead-of-file, invalid-JSON (real SDK init), undecryptable-key (real JWT parse). All exercise real Admin-SDK code paths -- no tautologies. |
| P8 | Correctness -- Verify probe | `Verify()` uses `firebase-connectivity-probe@invalid.invalid` -- the `.invalid` TLD is reserved by RFC 6761, guaranteeing "user not found" and never a collision. |
| P9 | Configuration -- env->config chain | Complete: `FIREBASE_ENABLED` -> `applyEnv()` (config.go:165) -> `Config.FirebaseEnabled` -> `firebase.Options.Enabled` -> `firebase.New()`. All three env vars (`FIREBASE_ENABLED`, `FIREBASE_PROJECT_ID`, `FIREBASE_SERVICE_ACCOUNT_PATH`) are wired. |
| P10 | Documentation | `docs/firebase/README.md` carries revision header (SS11.4.44), cites verified sources (SS11.4.99), and includes complete setup instructions with `chmod 600` guidance. |
| P11 | Schema | `config_schemas/firebase.yaml` includes a JSON Schema (draft 2020-12) with conditional `required` when `enabled=true`. |

---

## Configuration Chain Trace

| Step | Mechanism | Verified? |
|---|---|---|
| 1. Operator sets env | `FIREBASE_ENABLED=true`, `FIREBASE_PROJECT_ID=<id>`, `FIREBASE_SERVICE_ACCOUNT_PATH=<path>` | YES -- all three env vars read via `getenv()` in `config.go:165-173` |
| 2. Config struct populated | `applyEnv()` sets `Config.Firebase*` fields | YES |
| 3. Options constructed | `main.go:104-107` maps `Config` fields to `firebase.Options` | YES -- all three fields mapped |
| 4. Client created | `firebase.New(ctx, opts)` validates & initializes | YES -- returns error on misconfiguration, nil+inert on disabled, active client on success |
| 5. Client reachable at runtime | NOT REACHABLE -- result is `_` (discarded) | **NO -- FINDING 1** |

---

## Test Coverage Matrix

| Test | What it proves | REAL SDK? | Covered |
|---|---|---|---|
| `TestDisabledIsInertAndLogs` | Disabled path: no error, Active()=false, Verify errors, hooks log | No (disabled bypasses SDK) | PARTIAL (weak count assertion -- Finding 4) |
| `TestEnabledWithoutProjectIDFailsFast` | Missing project ID -> clear error | No (validated before SDK) | YES |
| `TestEnabledWithoutServiceAccountPathFailsFast` | Missing SA path -> clear error | No (validated before SDK) | YES |
| `TestEnabledWithMissingServiceAccountFileFailsFast` | Missing file -> error names the path | No (os.Stat before SDK) | YES |
| `TestEnabledWithDirectoryInsteadOfFileFailsFast` | Directory -> error says "directory" | No (os.Stat before SDK) | YES |
| `TestEnabledWithInvalidServiceAccountJSONFailsFast` | Invalid JSON -> SDK init fails | YES (`firebase.NewApp`) | YES |
| `TestEnabledWithWellFormedButUndecryptableServiceAccountFailsFast` | Valid JSON, broken key -> SDK init fails | YES (JWT parse in SDK) | YES |
| nil-Logger path | Logger nil -> log.Default() | N/A | **NOT COVERED (Finding 5)** |
| Active-client telemetry logging | Hooks on active client log correct format | N/A | **NOT COVERED (Finding 6)** |

---

## Verdict

**PASS WITH FINDINGS.** The core contracts -- graceful degrade when disabled and
fail-fast when misconfigured -- are correctly implemented and well-tested. The
security posture is solid: no tracked secrets, comprehensive git-ignore coverage,
no credential leaking via log or error messages.

The one HIGH finding (orphaned client) means the subsystem has zero runtime effect
when enabled -- the operator sees `firebase: enabled` in logs but no health
endpoint, no telemetry recording, no handler integration. This is a
PASS-bluff at the subsystem-integration layer (SS11.4/SS11.4.108) and requires
either wiring into the API runtime or documenting as a phased delivery with a
tracked follow-up work item.

Zero credential leaks. Zero findings requiring an emergency fix.
