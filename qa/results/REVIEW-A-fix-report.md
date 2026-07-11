# REVIEW-A Fix Report

**Source review:** `qa/results/REVIEW-A-firebase.md`
**Date:** 2026-07-11
**Fix scope:** HIGH + MEDIUM + LOW findings (FINDING 1-5 only)

---

## FINDING 1 (HIGH) -- Wire Firebase client into the API runtime

**File:** `api/cmd/sftp-api/main.go`, `api/internal/api/router.go`

**Problem:** `firebase.New()` result was discarded with `_`, making the
Firebase subsystem unreachable at runtime -- a PASS-bluff at the
subsystem-integration layer (SS11.4/SS11.4.108).

**Fix:**

1. `router.go` -- Added `firebase *firebase.Client` field to `Server` struct.
   Added `fb *firebase.Client` parameter to `NewServer()`. Updated the
   `handleHealth` handler to call `fbClient.Verify()` and report Firebase
   status as one of `unavailable` / `disabled` / `connected` / `unhealthy`.
   Raw SDK error details are logged server-side but NEVER returned to the
   unauthenticated caller -- returned only a sanitized `"unhealthy"` string
   (prevents path/project-id leakage per SS11.4.10).

2. `main.go` -- Captured `firebase.New()` result as `fbClient` and passed it
   to `api.NewServer(cfg, st, authSvc, fbClient)`.

3. `handlers_test.go` -- Updated the single test call site to pass `nil` for
   the Firebase client (tests don't need Firebase).

**Verification:** The `/api/v1/health` endpoint is unauthenticated and the
Firebase `Verify()` probe is lightweight (one Identity Toolkit lookup against
a `.invalid` throwaway address). No credential leakage -- the real error is
logged via `log.Printf` and the client sees only a fixed-string status.

---

## FINDING 2 (MEDIUM) -- Fix config-schema key-name divergence

**File:** `config_schemas/firebase.yaml`

**Problem:** Schema used nested `firebase:` block with `enabled`, `project_id`,
`service_account_path`, `web_app_id`. Go struct tags are flat:
`firebase_enabled`, `firebase_project_id`, `firebase_service_account_path`.
Copying the schema into `API_CONFIG` YAML would silently not populate the
struct -- operator thinks Firebase is configured, API starts with it disabled.

**Fix:** Changed all keys to flat top-level names matching the Go struct tags:
`firebase_enabled`, `firebase_project_id`, `firebase_service_account_path`,
`firebase_web_app_id`. Added comment: "These are top-level API_CONFIG keys,
not a nested firebase block." Updated the JSON Schema `properties` and
conditional `if/then` block to use the flat keys.

---

## FINDING 3 (MEDIUM) -- Log detail in telemetry stubs

**File:** `api/internal/firebase/firebase.go`

**Problem:** `telemetryStub` accepted `detail` (the crash message, event name,
or trace name) but discarded it with `_ = detail`. An operator searching logs
for a specific event would find only `component=test` with no distinguishing
information.

**Fix:** Changed log format from:
```
firebase: %s hook received component=%s (note: ...)
```
to:
```
firebase: %s hook received component=%s detail=%s (note: ...)
```
Removed the `_ = detail` line. The format string now has 4 args (surface,
component, detail, surface).

---

## FINDING 4 (LOW) -- Tighten disabled-hook count assertion

**File:** `api/internal/firebase/firebase_test.go`

**Problem:** The test asserted `strings.Count(out, "firebase: disabled") < 2`,
which would PASS if only 2 of the 4 expected log lines appeared. A regression
that silently turns one hook into a zero-op would go undetected.

**Fix:** Changed to exact-match assertion:
```go
if got := strings.Count(out, "firebase: disabled"); got != 4 {
    t.Fatalf("expected 4 'firebase: disabled' lines (1 init + 3 hooks), got %d:\n%s", got, out)
}
```

---

## FINDING 5 (LOW) -- Add nil-logger test

**File:** `api/internal/firebase/firebase_test.go`

**Problem:** The nil-safe `if logger == nil { logger = log.Default() }` path
had zero test coverage. A regression removing the nil-check would pass all
existing tests but panic at runtime.

**Fix:** Added `TestNewWithNilLoggerDoesNotPanic`:
```go
func TestNewWithNilLoggerDoesNotPanic(t *testing.T) {
    c, err := New(context.Background(), Options{Enabled: false})
    if err != nil {
        t.Fatal(err)
    }
    if c.Active() {
        t.Fatal("disabled client must report Active()=false")
    }
}
```

---

## Additional security hardening (coordinator review)

**File:** `api/internal/api/router.go`

**Finding:** Health endpoint returned raw `err.Error()` to unauthenticated
callers, potentially leaking internal paths/project IDs from Firebase SDK.

**Fix:** Log the real error server-side (`log.Printf("sftp-api: firebase verify
failed: %v", err)`) but return only a fixed-string `"unhealthy"` to the client.

---

## Build + Vet + Test Results

```
$ cd api && go vet ./...
(exit 0 -- clean)

$ cd api && go build -o /dev/null ./cmd/sftp-api/
(exit 0 -- build succeeds)

$ cd api && go test ./... -count=1
ok  	github.com/vasic-digital/sftp/api/internal/api	5.662s
ok  	github.com/vasic-digital/sftp/api/internal/authn	0.941s
ok  	github.com/vasic-digital/sftp/api/internal/firebase	0.008s
ok  	github.com/vasic-digital/sftp/api/internal/store	0.018s
ok  	github.com/vasic-digital/sftp/api/internal/crypt	0.042s
ok  	github.com/vasic-digital/sftp/api/internal/sftpsync	0.013s
(exit 0 -- all packages pass)
```

All 7 firebase tests (including the new `TestNewWithNilLoggerDoesNotPanic`)
and all existing api/authn/store/crypt/sftpsync tests pass on the first run.
