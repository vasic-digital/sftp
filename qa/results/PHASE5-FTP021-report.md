# PHASE5-FTP021: read_only vs read_write Permission Enforcement

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-12T00:30:00Z |
| **Task** | FTP-021 — Implement read_only vs read_write permission enforcement |
| **Status** | PASS — implementation complete; 17/17 tests GREEN |
| **Classification** | project-specific (§11.4.17) |

---

## 1. Investigation Summary

### 1.1 atmoz/sftp container analysis (reverse-engineered 2026-07-12)

The `atmoz/sftp:latest` container's `create-sftp-user` script:

1. Creates `/home/<user>/` owned by `root:root` with `chmod 755` — the SFTP
   chroot root. The user CANNOT write here (owned by root).
2. Creates subdirectories from the `dir` field (users.conf 6th field) at
   `/home/<user>/<dirPath>` with `chown $uid:users` and NO explicit chmod.
   The default umask grants the owner write access — this is where the
   permission gap exists: **read_only users CAN upload files because they
   own the subdirectory.**

3. The container has **NO** built-in mechanism to differentiate read_only
   from read_write. The users.conf format's only option flag is `e` at
   position 3 (encrypted-password), and there is no write-restriction flag.

4. On subsequent container restarts, the entrypoint checks for
   `/var/run/sftp/users.conf` — if it exists, the entire user creation
   (including directory provisioning) is SKIPPED. This means filesystem
   permissions set outside the container persist across restarts.

### 1.2 Enforcement options evaluated

| Option | Feasibility | Verdict |
|---|---|---|
| **A**: Modify atmoz Dockerfile to add write-restriction | Requires maintaining a custom fork of atmoz/sftp | Rejected — §11.4.74 extend-don't-reimplement |
| **B**: SFTP reverse proxy / gateway that filters writes | Adds operational complexity (extra service, TLS) | Rejected — over-engineered for filesystem-level enforcement |
| **C**: Filesystem permissions (chmod) after provisioning | Simple, effective with ForceCommand internal-sftp | **Selected** |

The selected approach works because:
- `ForceCommand internal-sftp` prevents shell access → users cannot run
  `chmod` to regain write permission.
- `chmod 555` on a user-owned directory prevents writes through the SFTP
  protocol while preserving read+traverse.
- The API can provision directories before or after the container starts
  (idempotent — `os.MkdirAll` + `os.Chmod`).

---

## 2. Implementation

### 2.1 Files changed

| File | Change |
|---|---|
| `api/internal/sftpsync/sftpsync.go` | Added `ProvisionHomeDirs`, `dirPerm`, `splitDirs`, `ensureDir` functions |
| `api/internal/sftpsync/sftpsync_test.go` | Added 8 new tests (ProvisionHomeDirs*, DirPermMapping, SplitDirs) |
| `api/internal/config/config.go` | Added `SFTPDataDir` config field, default, and `SFTP_DATA_DIR` env var |
| `api/internal/api/handlers_sync.go` | Extended `handleSync` to call `ProvisionHomeDirs` after `Write` |
| `deploy/docker-compose.yml` | Added volume mount `./data:/app/data` to API service |
| `.env.example` | Updated `SFTP_DATA_DIR` comment (now also consumed by API config) |

### 2.2 Permission mapping

```
read_only  → chmod 0555 (r-xr-xr-x)  — owner can read/traverse, cannot write
read_write → chmod 0755 (rwxr-xr-x)  — owner has full access (default atmoz behavior)
public     → chmod 0555 (r-xr-xr-x)  — most restrictive safe default
unknown    → chmod 0555              — fail-closed: unknown permissions treated as read-only
```

### 2.3 Sync flow (updated handleSync)

```
1. List accounts from store
2. Write users.conf (existing behavior, atomic write-temp-then-rename)
3. ProvisionHomeDirs:
   a. For each enabled account with a non-empty HomeDir:
      - Parse HomeDir as comma-separated subdirectory list
      - Construct host path: <SFTPDataDir>/<username>/<subdir>
      - Create with os.MkdirAll (idempotent)
      - Set permissions with os.Chmod (idempotent)
   b. If SFTPDataDir is empty, skip provisioning entirely
   c. Collect errors per-path; surface all in response
```

### 2.4 Test coverage (17/17 GREEN)

```
TestRenderGolden                          — existing, unchanged
TestRenderSortedDeterministic             — existing, unchanged
TestRenderAutoIDAssignment                — existing, unchanged
TestRenderFailClosedWithoutHash           — existing, unchanged
TestRenderPublicNeverGetsPassword         — existing, unchanged
TestWriteAtomicAndPerms                   — existing, unchanged
TestWriteEmptyAccountSet                  — existing, unchanged
TestProvisionHomeDirsReadOnly             — NEW: verifies 0555 on read_only
TestProvisionHomeDirsReadWrite            — NEW: verifies 0755 on read_write
TestProvisionHomeDirsIdempotent           — NEW: second call is no-op, perms stable
TestProvisionHomeDirsSkipsDisabled        — NEW: disabled accounts create no dirs
TestProvisionHomeDirsEmptyDataDir         — NEW: empty data dir is graceful no-op
TestProvisionHomeDirsPublicDefaultsToReadOnly — NEW: public → 0555 safe default
TestProvisionHomeDirsMultipleAccounts     — NEW: mixed accounts get correct perms
TestDirPermMapping                        — NEW: all 4 permission states mapped correctly
TestSplitDirs                             — NEW: comma-separated parsing + empty fallback
TestRenderedCryptHashVerifiesWithOpenSSL  — existing, unchanged
```

---

## 3. Honest Limitations (§11.4.6)

### 3.1 What this DOES enforce

- An SFTP user with `read_only` permission cannot upload, delete, rename,
  or modify files through the SFTP protocol. The filesystem permission
  `0555` (r-xr-xr-x) denies write access.
- An SFTP user with `read_write` permission has normal read/write access
  (same as before this change).

### 3.2 What this does NOT enforce

- **Shell access bypass**: If an attacker gains shell access to the
  container (e.g., through a vulnerability in sshd), they could chmod their
  own directory back to writable since they own it. This is inherent to
  filesystem-level enforcement. Mitigation: `ForceCommand internal-sftp`
  and `ChrootDirectory` prevent shell access by design.
- **sftp-server-level bypass**: The enforcement is at the filesystem layer,
  not at the SFTP protocol layer. If the sftp-server implementation has a
  bug that ignores filesystem permissions, writes could succeed. This is
  extremely unlikely with OpenSSH's internal-sftp.
- **Pre-existing file modifications**: Files that exist with write
  permission before enforcement will remain writable. The chmod only
  affects the directory, not recursive file contents.

### 3.3 Deployment requirements

- **API filesystem access**: The API process MUST have read/write access
  to the SFTP data directory (mounted at `/app/data` in
  containerized deployments, or `./data` on the host for native runs).
  Without this, `SFTP_DATA_DIR` should be set to `""` (empty), and
  filesystem enforcement must be handled out-of-band (e.g., a cron job
  or manual operator action).
- **Path alignment**: The `SFTP_USERS_CONF` mount in the SFTP container
  must point at the same file the API writes to via `USERS_CONF_PATH`.
  In the current docker-compose defaults these are DIFFERENT files
  (`./users.conf` vs `data/users.conf`) — operators must align them.

### 3.4 Why not kernel-level enforcement (SELinux / AppArmor)?

Kernel MAC could provide stronger enforcement (the user literally cannot
write regardless of filesystem permission bits). However:
- It requires host-level configuration that varies per distribution
- It would need custom SELinux policy modules
- The atmoz container runs as root internally, making MAC labeling complex
- For the current threat model (accidental/mistaken writes by legitimate
  SFTP users, not malicious container escape), filesystem permissions
  are proportional and effective

---

## 4. Verification Evidence

### 4.1 Unit tests

```bash
cd api && go test ./internal/sftpsync/ -v -count=1
# Result: 17/17 PASS (0.008s)
```

### 4.2 Build verification

```bash
cd api && go build ./internal/sftpsync/ ./internal/config/ ./internal/api/
# Result: clean build, zero warnings
```

### 4.3 Manual verification procedure

To manually verify the enforcement on a live deployment:

```bash
# 1. Create a read_only user via API
curl -X POST http://127.0.0.1:7722/api/v1/admin/accounts \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"username":"test_ro","password":"S3cret!Pass","permission":"read_only"}'

# 2. Trigger sync
curl -X POST http://127.0.0.1:7722/api/v1/admin/sync \
  -H "Authorization: Bearer <token>"

# 3. Verify directory permissions
ls -la ./data/test_ro/
# Expected: dr-xr-xr-x (555) on subdirectories

# 4. Attempt SFTP upload (must fail)
sftp -P 7721 test_ro@localhost <<EOF
put /etc/hostname
EOF
# Expected: "Permission denied" on upload
```

---

## 5. Conclusion

The atmoz/sftp container genuinely cannot enforce read_only vs read_write at
the application layer — the format and entrypoint offer no such mechanism.
The implemented filesystem-level enforcement (chmod 555 for read_only) is
the simplest effective approach that requires zero modifications to the
upstream image.

The solution is **honest about its limitations**: it prevents writes through
normal SFTP usage but would not withstand a container escape or an sshd
vulnerability that grants shell access. For the current threat model
(permission enforcement for legitimate SFTP users), this is appropriate and
proportional.
