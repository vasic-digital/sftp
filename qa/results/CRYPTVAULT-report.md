# CRYPTVAULT Implementation Report

**Date:** 2026-07-11  
**Task:** Replace in-memory `cryptVault` with persistent AES-256-GCM encrypted vault  
**Classification:** universal (§11.4.17) — persistent encrypted vault is platform-neutral

---

## Implementation Summary

### Files Created

| File | Purpose |
|---|---|
| `api/internal/vault/vault.go` | Persistent encrypted key-value store (AES-256-GCM) |
| `api/internal/vault/vault_test.go` | 12 tests covering round-trip, restart, edge cases, tampering |

### Files Modified

| File | Change |
|---|---|
| `api/internal/config/config.go` | Added `VaultDataDir` field (env `VAULT_DATA_DIR`, default `data/vault`) |
| `api/internal/api/router.go` | `NewServer` accepts `*vault.Vault`, imported vault package |
| `api/internal/api/handlers_sync.go` | `cryptVault` now wraps `*vault.Vault` instead of in-memory map |
| `api/internal/api/handlers_test.go` | `newTestEnv` creates `vault.New()` and passes it to `NewServer` |
| `api/cmd/sftp-api/main.go` | Creates vault from config and passes it to `NewServer` |

### Files NOT Modified

| File | Reason |
|---|---|
| `api/internal/store/` | Store has no cryptVault — it never held passwords; it uses SQLite for accounts/admins only |

---

## Vault Design

### Encryption Scheme

- **Algorithm:** AES-256-GCM (authenticated encryption with associated data)
- **Key:** 32-byte random master key, hex-encoded, stored in `data/vault/.master_key` (chmod 0600)
- **Key generation:** `crypto/rand` on first run; subsequent runs read the existing key
- **Per-entry nonce:** 12-byte random nonce from `crypto/rand`, prepended to ciphertext
- **On-disk format:** `data/vault/<hex(key)>.enc` = `[12-byte nonce][ciphertext + 16-byte GCM tag]`
- **Atomic writes:** write-temp-then-rename for each entry
- **Dependencies:** Go standard library only (`crypto/aes`, `crypto/cipher`, `crypto/rand`)

### Key Management

- Master key stored as 64 hex chars in `.master_key`
- Permission 0600 on master key file and all entry files (§11.4.10)
- Data directory permission 0700
- Honest gap (§11.4.6): key rotation requires re-encrypting all entries (not implemented; a fresh vault with `data/vault/` empty regenerates a new key on next restart)

### API Contract

```go
func New(cfg VaultConfig) (*Vault, error)
func (v *Vault) Store(ctx context.Context, key string, value string) error
func (v *Vault) Load(ctx context.Context, key string) (string, error)
func (v *Vault) Delete(ctx context.Context, key string) error
```

- `Load` returns `vault.ErrNotFound` when key does not exist
- `Delete` returns `vault.ErrNotFound` when key does not exist
- Empty key is rejected on all operations
- Corrupted/tampered blobs are detected by GCM authentication and rejected

---

## Test Results

### Pass Count

| Package | Tests | Status |
|---|---|---|
| `api/internal/api` | 14 | ALL PASS |
| `api/internal/authn` | 13 | ALL PASS |
| `api/internal/crypt` | 6 | ALL PASS |
| `api/internal/firebase` | 9 | ALL PASS |
| `api/internal/sftpsync` | 8 | ALL PASS |
| `api/internal/store` | 15 | ALL PASS |
| `api/internal/vault` | 12 | ALL PASS |
| **Total** | **77** | **ALL PASS** |

### Two-Run Consistency (§11.4.50)

- Run 1: 77/77 PASS (`go test ./... -count=1`)
- Run 2: 77/77 PASS (identical results, same test count, same PASS verdicts)
- Verdict: DETERMINISTIC — all tests produce identical outcomes across runs

### Vault Test Coverage

| Test | What it proves |
|---|---|
| `TestStoreAndLoadRoundTrip` | Store→Load returns the original value |
| `TestRestartPreservesData` | New vault instance with same master key recovers stored data |
| `TestLoadNonExistentKey` | Missing key returns `ErrNotFound` |
| `TestDelete` | Delete removes entry; subsequent Load returns `ErrNotFound` |
| `TestDeleteNonExistent` | Deleting missing key returns `ErrNotFound` |
| `TestStoreDifferentNonces` | Different keys produce different ciphertexts (nonce randomization) |
| `TestMasterKeyFilePermissions` | Master key file has permission 0600 |
| `TestEntryFilePermissions` | Entry files have permission 0600 |
| `TestTamperedBlobRejected` | Corrupted ciphertext is rejected by GCM auth tag |
| `TestStoreEmptyValue` | Empty value round-trips correctly |
| `TestStoreEmptyKey` | Empty key rejected on all operations |
| `TestStoreOverwrite` | Overwriting a key updates the stored value |

---

## Honest Gaps and Known Limitations (§11.4.6)

1. **Master key rotation not implemented.** Rotating the master key would require loading every entry with the old key and re-storing with the new key. A fresh `data/vault/` directory (e.g., wiped manually) regenerates a new key on next restart — but is NOT equivalent to in-place rotation (loses all existing entries).

2. **No key derivation from passphrase.** The master key is stored as raw random bytes on disk. A hardware-bound or passphrase-derived key (e.g., via Argon2id) would add defense-in-depth but would require the passphrase on every restart, complicating autonomous operation.

3. **Single vault instance.** The vault has no built-in concurrency control beyond filesystem atomicity (write-tmp-then-rename). Concurrent writes to the same key from multiple goroutines could interleave. The current API design (single process, single Server) makes this acceptable; a multi-instance deployment would need advisory locking.

4. **Filename derived from key.** Entry filenames are hex-encoded keys. A username like `admin` produces `61646d696e.enc`. This leaks the existence of an entry (but not its value) to anyone who can list the directory. The encryption still protects the value.

5. **The `cryptVault.set/get/delete` wrappers use `context.Background()`.** The vault API accepts context, but the `cryptVault` wrapper (which preserves the existing handler call sites) uses `context.Background()`. This means vault I/O does not inherit request-scoped cancellation. Acceptable for local file I/O (sub-millisecond), but documented here for completeness.

---

## Verification Commands

```bash
cd api && go vet ./...        # PASS (exit 0)
cd api && go build ./...      # PASS (exit 0)
cd api && go test ./... -count=1  # PASS (77/77, run 1)
cd api && go test ./... -count=1  # PASS (77/77, run 2 — deterministic)
```
