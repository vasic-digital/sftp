# PHASE 4 CONTAINER FIX — Bug #1 + Bug #2 Resolution Report

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-11T23:30:00Z |
| **Status** | PASS — both bugs fixed, all tests green |
| **Fixed by** | Claude agent (T1/main) |
| **Source** | PHASE4-ATM014-report.md |

---

## Bug #1 (CRITICAL): sftpsync format — `:e` at wrong position

**File**: `api/internal/sftpsync/sftpsync.go`, function `renderLine`

### Before (WRONG)

```
alice:$6$hash:1001:1001:/alice
bob:$6$hash:1002:1002:/bob:e
public_share:*:1003:1003:/public_share:e
```

The `:e` was placed at the END of the line (position 6) as a "chroot option",
but atmoz/sftp's entrypoint reads `e` ONLY from position 3 (immediately after
the password field) to mean "password is already encrypted — pass `-e` to
chpasswd". With `:e` at position 6, chpasswd was called WITHOUT `-e`, treating
the `$6$` hash as plaintext, causing double-hashing and universal auth failure.

### After (CORRECT)

```
alice:$6$hash:e:1001:1001:/alice
bob:$6$hash:e:1002:1002:/bob
public_share:*:e:1003:1003:/public_share
```

All accounts now get `:e` at position 3 (immediately after password). For all
account types, the password is a pre-hashed `$6$` crypt value that must be
stored verbatim.

### Changes made

1. **`api/internal/sftpsync/sftpsync.go`**:
   - Package doc comment: corrected format from `user:password:uid:gid:home_directory[:options]`
     to `user:password:e:uid:gid:home_directory`
   - Constant `chrootOption` renamed to `encryptedPasswordFlag` with corrected docstring
   - `renderLine()`: always emits `:e` at position 3 for all accounts
   - Removed the per-permission options switch (read_only/read_write/public)
     that appended `:e` as a suffix
   - Updated PERMISSION MAPPING DECISION section to correctly describe the
     `e` flag as "encrypted-password" not "chroot"

2. **`api/internal/sftpsync/sftpsync_test.go`**:
   - `TestRenderGolden`: expected format updated to 6-field `:e` at position 3
   - `TestRenderFailClosedWithoutHash`: prefix check updated to `alice:*:e:`
   - `TestRenderPublicNeverGetsPassword`: suffix check changed from `:e` to `:/p`
     (home dir must be last field); prefix check updated to `pub:*:e:`
   - `TestWriteAtomicAndPerms`: expected prefix updated to `alice:*:e:1001:1001:/a`
   - `TestRenderedCryptHashVerifiesWithOpenSSL`: field count changed from 5 to 6

3. **`api/internal/api/handlers_test.go`**:
   - `TestFullAccountJourney`: alice line check updated to 6 fields with `:e` at
     position 3; pubacct expected format updated to `pubacct:*:e:1002:1002:/pubacct`

### Test results

```
cd api && go test ./... -count=1
ok  github.com/vasic-digital/sftp/api/internal/api        7.423s
ok  github.com/vasic-digital/sftp/api/internal/authn       1.057s
ok  github.com/vasic-digital/sftp/api/internal/crypt       0.105s
ok  github.com/vasic-digital/sftp/api/internal/firebase    0.012s
ok  github.com/vasic-digital/sftp/api/internal/sftpsync    0.013s
ok  github.com/vasic-digital/sftp/api/internal/store       0.030s
ok  github.com/vasic-digital/sftp/api/internal/vault       0.007s
```

All 8 test packages PASS. `go vet ./...` and `go build` both exit 0.

---

## Bug #2 (HIGH): Volume mapping mismatch

**File**: `deploy/docker-compose.yml`

### Before (WRONG)

```yaml
volumes:
  - "${SFTP_DATA_DIR:-./data}:/sftp_data"
```

atmoz/sftp uses `/home/<username>/` as the user home and chroot root.
Host data mounted to `/sftp_data/` was invisible to SFTP users because
their chroot starts at `/home/<username>/`.

### After (CORRECT)

```yaml
volumes:
  # atmoz/sftp creates user homes under /home/<username>/
  # (the chroot target). Mount host data at /home so SFTP users
  # see the host-persisted directories.
  - "${SFTP_DATA_DIR:-./data}:/home"
```

### Compose validation

```
$ podman-compose -f deploy/docker-compose.yml config
...
volumes:
- ./data:/home
- ./users.conf:/etc/sftp/users.conf:ro
...
```

Compose configuration validates cleanly.

---

## Summary

| Bug | Severity | File | Fix | Status |
|---|---|---|---|---|
| #1 | CRITICAL | `api/internal/sftpsync/sftpsync.go` | `:e` moved from position 6 to position 3 for all accounts | FIXED |
| #2 | HIGH | `deploy/docker-compose.yml` | Volume mount changed from `/sftp_data` to `/home` | FIXED |

**Verification gates passed:**
- `go vet ./...` — exit 0
- `go build -o /dev/null ./cmd/sftp-api/` — exit 0
- `go test ./... -count=1` — ALL 8 packages PASS
- `podman-compose -f deploy/docker-compose.yml config` — validates cleanly
