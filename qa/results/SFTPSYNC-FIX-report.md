# SFTP Sync Write Function — ENOSPC Temp File Leak Fix Report

**Date:** 2026-07-11
**File:** `api/internal/sftpsync/sftpsync.go`
**Function:** `Write`
**Issue:** STREAM-9 chaos test — known ENOSPC temp file leak

## Bug

When `os.WriteFile(tmp, content, 0600)` fails with ENOSPC (disk full), Go's `os.WriteFile`
creates the file via `O_CREAT` before the write fails, leaving a 0-byte `.tmp` file on disk.
The error path did not clean this up.

## Before/After Diff

```diff
 	if err := os.WriteFile(tmp, []byte(content), 0o600); err != nil {
+		_ = os.Remove(tmp) // Clean up 0-byte file left by O_CREAT on ENOSPC
 		return 0, fmt.Errorf("sftpsync: write %s: %w", tmp, err)
 	}
```

Note: The `os.Rename` error path two lines below already had the `_ = os.Remove(tmp)` cleanup.
This fix adds the same cleanup to the `os.WriteFile` error path, which was the only path
missing it.

## Verification Results

| Step | Command | Result |
|------|---------|--------|
| `go vet` | `cd api && go vet ./...` | PASS (exit 0, no output) |
| `go build` | `cd api && go build -o /dev/null ./cmd/sftp-api/` | PASS (exit 0, no output) |
| `go test` | `cd api && go test ./... -count=1` | PASS (all 5 test packages OK, including `sftpsync`) |

### Test Details

```
ok  	github.com/vasic-digital/sftp/api/internal/api	5.423s
ok  	github.com/vasic-digital/sftp/api/internal/authn	0.924s
ok  	github.com/vasic-digital/sftp/api/internal/crypt	0.074s
ok  	github.com/vasic-digital/sftp/api/internal/firebase	0.010s
ok  	github.com/vasic-digital/sftp/api/internal/sftpsync	0.014s
ok  	github.com/vasic-digital/sftp/api/internal/store	0.020s
```

## Impact

No functional change to the happy path. The fix prevents a slow disk-space leak: on every
ENOSPC write error, a 0-byte `.tmp` file was left behind, accumulating over retry attempts.
The `_ = os.Remove(tmp)` call is intentionally silent (its error is discarded) because:
1. If the file doesn't exist (unlikely but possible), the error is irrelevant.
2. The primary error (write failure) is already being returned — adding a non-critical
   cleanup failure would obscure the actual problem.
