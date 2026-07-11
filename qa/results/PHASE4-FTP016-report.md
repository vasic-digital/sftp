# PHASE4-FTP016 — Vault Master Key Rotation

**Date:** 2026-07-11
**Status:** PASS

## Summary

Implemented `RotateKey() error` method on the Vault struct in
`api/internal/vault/` with comprehensive test coverage.

## Implementation

### `RotateKey()` — `vault.go` lines 149-209

6-step rotation protocol:

1. Generate fresh 32-byte random master key (`crypto/rand`)
2. Construct GCM instances for both old and new keys
3. List all existing entries via `listEntries()` (scans `*.enc` files)
4. Decrypt each entry with old GCM, re-encrypt with new GCM (fresh random nonce),
   write-temp-then-rename — any failure returns immediately leaving old key active
5. Atomically replace on-disk master key file (`.master_key.tmp` → `.master_key`)
6. Only after all steps succeed: swap in-memory `v.key`

### Helper: `reEncryptEntry()` — `vault.go` lines 214-243

Per-entry re-encryption: read blob → GCM-decrypt with old key → GCM-encrypt
with new key (fresh nonce) → write-temp-then-rename.

### Helper: `listEntries()` — `vault.go` lines 247-268

Scans the data directory for `*.enc` files, hex-decodes the filename stem
to recover the logical key name. Gracefully skips malformed filenames and
`.tmp` artifacts.

## Test Coverage — all PASS

| Test | Description |
|---|---|
| `TestRotateKeyRoundTrip` | Store 3 entries → rotate → all readable with original values |
| `TestRotateKeyOldKeyFailsDecryption` | Snapshot old key → rotate → old key GCM `Open` fails with "authentication failed" — proves re-encryption happened |
| `TestRotateKeyEmptyVault` | Rotate on vault with zero entries → succeeds (no-op) → store/load still works with new key |

All 12 pre-existing tests + 3 new tests = **15/15 PASS**.

## Verification

```
$ go vet ./internal/vault/
(no output — clean)

$ go test ./internal/vault/ -count=1 -v
=== RUN   TestRotateKeyRoundTrip
--- PASS: TestRotateKeyRoundTrip (0.00s)
=== RUN   TestRotateKeyOldKeyFailsDecryption
    vault_test.go:356: old key correctly rejected: cipher: message authentication failed
--- PASS: TestRotateKeyOldKeyFailsDecryption (0.00s)
=== RUN   TestRotateKeyEmptyVault
--- PASS: TestRotateKeyEmptyVault (0.00s)
PASS
ok  	github.com/vasic-digital/sftp/api/internal/vault	0.002s
```

## Files Changed

- `api/internal/vault/vault.go` — added `RotateKey()`, `reEncryptEntry()`, `listEntries()`, `strings` import
- `api/internal/vault/vault_test.go` — added 3 tests, `crypto/aes` + `crypto/cipher` imports, `hexDecodedLen` helper

## Constraint Compliance

- Scope: `api/internal/vault/` ONLY — satisfied
- NEVER commit — satisfied (no commit executed)
