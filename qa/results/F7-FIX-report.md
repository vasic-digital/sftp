# F7-FIX: Firebase SDK error wrapping — `%w` to `%v`

**Revision:** 1
**Last modified:** 2026-07-11T22:07:00Z

## Summary

Replaced `%w` with `%v` in the Firebase Admin SDK initialization error
wrapping to break the error chain, preventing future Firebase SDK versions
from potentially leaking key material through `errors.Unwrap()` / `errors.Is` / `errors.As`.

## Before

```go
return nil, fmt.Errorf("firebase: admin SDK init failed (check the service account JSON at %q): %w", opts.ServiceAccountPath, err)
```

`%w` wraps the underlying Firebase SDK error, making its internal state
(which may include credential material in edge-case SDK error messages)
reachable via the standard library `errors.Unwrap()` chain.

## After

```go
return nil, fmt.Errorf("firebase: admin SDK init failed (check the service account JSON at %q): %v", opts.ServiceAccountPath, err)
```

`%v` formats the error message as a plain string, breaking the unwrap
chain. The human-readable diagnostic is preserved (the operator still sees
the SDK error text); only the programmatic unwrap path is severed.

## Impact analysis

- No caller in the codebase uses `errors.Is` or `errors.As` on this error
  value. The error is always consumed as a string diagnostic or as a fatal
  startup signal.
- The change does not alter any contract — the return type is still
  `error`, and the string representation remains identical for the same
  underlying error.

## Verification

| Check | Result |
|---|---|
| `go vet ./internal/firebase/` | exit 0 |
| `go test ./internal/firebase/ -count=1` (pass 1) | 9/9 PASS |
| `go test ./internal/firebase/ -count=1` (pass 2) | 9/9 PASS |

### Pass 1 output

```
=== RUN   TestDisabledIsInertAndLogs
--- PASS: TestDisabledIsInertAndLogs (0.00s)
=== RUN   TestEnabledWithoutProjectIDFailsFast
--- PASS: TestEnabledWithoutProjectIDFailsFast (0.00s)
=== RUN   TestEnabledWithoutServiceAccountPathFailsFast
--- PASS: TestEnabledWithoutServiceAccountPathFailsFast (0.00s)
=== RUN   TestEnabledWithMissingServiceAccountFileFailsFast
--- PASS: TestEnabledWithMissingServiceAccountFileFailsFast (0.00s)
=== RUN   TestEnabledWithDirectoryInsteadOfFileFailsFast
--- PASS: TestEnabledWithDirectoryInsteadOfFileFailsFast (0.00s)
=== RUN   TestEnabledWithInvalidServiceAccountJSONFailsFast
--- PASS: TestEnabledWithInvalidServiceAccountJSONFailsFast (0.00s)
=== RUN   TestNewWithNilLoggerDoesNotPanic
--- PASS: TestNewWithNilLoggerDoesNotPanic (0.00s)
=== RUN   TestEnabledWithWellFormedButUndecryptableServiceAccountFailsFast
--- PASS: TestEnabledWithWellFormedButUndecryptableServiceAccountFailsFast (0.00s)
=== RUN   TestActiveClientTelemetryLogsFormat
--- PASS: TestActiveClientTelemetryLogsFormat (0.00s)
PASS
```

### Pass 2 output

Identical — all 9 tests PASS (deterministic consistency confirmed).

## File changed

- `api/internal/firebase/firebase.go` line 96: `%w` → `%v`

## Constraint

This change was NOT committed per the task constraint.
