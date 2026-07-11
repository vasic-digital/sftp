# PHASE5-FTP019 -- sftpsync Format Fix Re-verification Report

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-12T00:10:00Z |
| **Status** | PASS |
| **Test date** | 2026-07-12 |
| **Tester** | AI agent (Claude Code) |
| **Fixed in commit** | 6d32013 (Phase 4: CRITICAL sftpsync format fix) |

## Summary

Re-verified the sftpsync `:e` flag position fix from commit 6d32013. The fix moved the encrypted-password flag from end-of-line (position 6, the old bug: `user:hash:uid:gid:dir:e`) to position 3 (the correct atmoz/sftp format: `user:hash:e:uid:gid:dir`). This was verified through a full end-to-end SFTP deployment cycle.

## Environment

- **Host:** Linux 6.12.61-6.12-alt1, amd64
- **Go:** 1.26.2
- **Podman:** 5.7.1 (rootless)
- **SFTP image:** docker.io/atmoz/sftp:latest
- **API binary:** `bin/sftp-api` (built from `api/cmd/sftp-api/`)
- **Test DB:** SQLite (file-backed at `/tmp/sftp-test/sftp.db`)
- **Firebase:** disabled (not needed for SFTP core)

## Users Created via API

| User | Permission | Password | Home Dir | Result |
|---|---|---|---|---|
| alice | read_write | AlicePass1! | /alice | 201 Created |
| bob | read_only | BobPass2! | /bob | 201 Created |
| pub | public | PubPass3! | /pub | 201 Created (public_acknowledged=true) |

API endpoints used: `POST /api/v1/auth/login` (admin), `POST /api/v1/accounts` (3 accounts), `POST /api/v1/sync`.

## users.conf Format Verification (CORE TEST)

The `/sync` endpoint rendered 3 accounts. Raw output:

```
alice:$6$caKb569a001RiulJ$ze.89QartrR4ZT4B23kAUjJILCO.MBkJR.6u/EDg6T8Y28VKDS.9qcRvIlsEHwn2NPE7Ip0vp8EnNDZ.bGHXi1:e:1001:1001:/alice
bob:$6$DWNsoLY62vVQJ4sp$FZ.hbWonZtpIJ2ESc2QWSbtQDXV/NStuiDss9knuutDRZTIPJb/9BnoAff.H.6x1JMU2wUwPiT8ToZcRlI28V0:e:1002:1002:/bob
pub:*:e:1003:1003:/pub
```

### Per-line analysis

| User | Field 1 | Field 2 | Field 3 (:e) | Field 4 (uid) | Field 5 (gid) | Field 6 (dir) | Verdict |
|---|---|---|---|---|---|---|---|
| alice | alice | $6$ sha512-crypt hash | **:e** | 1001 | 1001 | /alice | PASS |
| bob | bob | $6$ sha512-crypt hash | **:e** | 1002 | 1002 | /bob | PASS |
| pub | pub | * (no-login) | **:e** | 1003 | 1003 | /pub | PASS |

### Anti-regression checks

- **`:e` at position 3 for ALL accounts:** PASS (every line has `:e` immediately after the password)
- **No `:e` at end of line:** PASS (zero matches for `^.*:e$` pattern -- the old bug is gone)
- **Password fields:** alice + bob = `$6$` sha512-crypt hashes; pub = `*` (impossible password for public accounts)
- **UID/GID auto-assignment:** sequential from 1001, uid==gid per account

## SFTP Functional Tests

### Alice (read_write)

| Operation | Result | Evidence |
|---|---|---|
| SSH authentication | PASS | Connected to 127.0.0.1:7721 |
| cd alice | PASS | Directory exists, owned by 1001:100 |
| put (upload) | PASS | `upload_test.txt` written (55 bytes) |
| ls (directory listing) | PASS | File visible with correct ownership (1001:1001) |
| get (download) | PASS | Fetched to `/tmp/sftp-test/alice_download.txt` |
| Content integrity | PASS | Downloaded content matches uploaded: "Hello from SFTP test - Sun Jul 12 12:10:00 AM MSK 2026" |
| rm (delete) | PASS | File removed successfully |

### Bob (read_only)

| Operation | Result | Evidence |
|---|---|---|
| SSH authentication | PASS | Connected to 127.0.0.1:7721 |
| cd bob | PASS | Directory exists, owned by 1002:100 |
| put (upload) | ALLOWED | File written successfully (54 bytes) |
| ls (directory listing) | PASS | File visible with ownership 1002:1002 |

> **Note:** Bob is `read_only` in the API data model, but the atmoz/sftp users.conf format has no read/write permission semantics -- that is filesystem-layer enforcement. In this test, bob could write because the host-side directory was not set up with restrictive permissions. The API correctly records bob's permission as `read_only`; the deploy layer must enforce it via filesystem ownership/chmod on the host data directories. This is a DOCUMENTED BOUNDARY per `api/internal/sftpsync/sftpsync.go` line 35-38: "read_only enforcement is a filesystem-ownership concern handled by the deploy layer."

### Public (pub)

| Attempt | Password | Result | Exit Code |
|---|---|---|---|
| Password login | PubPass3! (original) | Permission denied | 5 |
| Password login | wrongpass (arbitrary) | Permission denied | 5 |

Both password-login attempts correctly rejected. The `*` password in users.conf is recognized by `chpasswd -e` (via the `:e` flag) as an impossible password, disabling password authentication. Public accounts are reachable only via key-based auth provisioned out of band.

## Container Behavior

The container entrypoint (`atmoz/sftp:latest`) correctly parses the 6-field users.conf with `:e` at position 3. Without the `:e` flag at this position, `chpasswd` re-hashes the `$6$` value as plaintext (double-hashing), causing all authentication to fail. This is the exact bug fixed in commit 6d32013.

Container logs confirmed:
```
[/usr/local/bin/create-sftp-user] Parsing user data: "alice:$6$...:e:1001:1001:/alice"
```

The `:e` flag tells the entrypoint to call `chpasswd -e`, storing the pre-hashed `$6$` value verbatim.

## Cleanup

- API process killed
- sftp_test container stopped and removed
- deploy_sftp_net network removed
- repo artifacts removed (users.conf, data/ directories)
- Test evidence preserved at `/tmp/sftp-test/` (api.log, users.conf, JSON responses)

## Verdict

**PASS** -- The sftpsync `:e` flag fix (commit 6d32013) is verified correct:

1. users.conf format is `user:$6$hash:e:uid:gid:dir` (position 3) -- NOT the old buggy `user:$6$hash:uid:gid:dir:e` (end of line)
2. All 3 account types (read_write, read_only, public) render correctly
3. Password authentication works for alice + bob
4. Public account correctly denies password login
5. Upload/download/delete all functional
6. Container entrypoint correctly interprets the format

## Honest boundaries

- Bob's write restriction was NOT tested at the filesystem layer (documented deploy-layer boundary)
- No host-side chmod/chown enforcement tested
- No SSH key-based auth tested for public accounts (out of scope)
- Test environment used ephemeral directory `/tmp/sftp-test/` -- no production config touched
