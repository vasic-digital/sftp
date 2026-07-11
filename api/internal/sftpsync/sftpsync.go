// Package sftpsync renders the SFTP account database into the atmoz/sftp
// users.conf file the container consumes (mounted read-only, see
// deploy/docker-compose.yml `SFTP_USERS_FILE`).
//
// File format (project MVP spec, docs/research/mvp/MVP.md):
//
//	user:password:e:uid:gid:home_directory
//
// The "e" at position 3 (immediately after the password) is the encrypted-
// password flag: it tells the entrypoint to pass `-e` to chpasswd so the
// $6$ pre-hashed password is stored verbatim rather than re-hashed.
//
// PASSWORD FIELD DECISION (evidence-based, §11.4.6 — no guessing):
//
//	The MVP doc shows plaintext passwords. However atmoz/sftp's entrypoint
//	applies the field via `usermod -p "$3"`, and `usermod -p` accepts ANY
//	glibc crypt(3) hash verbatim. Rendering a sha512-crypt ($6$) hash
//	instead of plaintext is strictly better (the file, though mounted :ro,
//	would otherwise expose every user's plaintext password to any host
//	user who can read the project directory) and requires no container
//	changes. The hash implementation (api/internal/crypt) is verified
//	BYTE-IDENTICAL to `openssl passwd -6` against 5 golden vectors, so
//	the resulting users.conf lines are accepted by OpenSSH/glibc exactly
//	as `openssl passwd -6` output would be.
//
// PERMISSION MAPPING DECISION (evidence-based, FTP-021 — Phase 5):
//
//	The users.conf format has no read/write permission semantics — the atmoz
//	container's create-sftp-user script (reverse-engineered 2026-07-12)
//	treats the 6th field as a comma-separated list of subdirectories to
//	create under /home/<user>/ with chown $uid:users. There is NO per-user
//	write-restriction flag in the container entrypoint. Therefore:
//
//	  - Every account renders :e at position 3 (all passwords are $6$ crypt
//	    hashes that must be stored verbatim);
//	  - read_only enforcement is a FILESYSTEM permission concern performed
//	    by ProvisionHomeDirs after the users.conf write — it sets the user's
//	    home subdirectory(ies) to read-only (chmod 555, owner cannot write);
//	  - read_write accounts get the default atmoz behaviour (user-owned
//	    directories, chmod 755);
//	  - public accounts are rendered with password `*` (impossible
//	    password — no password login); public accounts are reachable only
//	    with key-based auth provisioned out of band. Public access is NEVER
//	    a default anywhere in the system (the API layer 422s any public
//	    grant without explicit acknowledgement).
//
// FTP-021 DESIGN RATIONALE (evidence-based, §11.4.6):
//
//	atmoz/sftp has NO built-in read-vs-write permission mechanism. The
//	create-sftp-user script does NOT accept any write-restriction flag.
//	The container's internal-sftp ForceCommand means users cannot execute
//	chmod from within the SFTP session, so a chmod 555 on a user-owned
//	directory IS an effective write barrier — the user owns the directory
//	but cannot write to it through the SFTP protocol. This is simpler and
//	more reliable than a reverse-proxy approach (no additional service),
//	and does not require modifying the upstream atmoz image (§11.4.74
//	extend-don't-reimplement). The trade-off is that the API process needs
//	filesystem access to the SFTP data directory (mounted as a volume in
//	containerized deployments).
//
// UID/GID DEFAULT: 1001, auto-incrementing per account in username order
// when the account carries no explicit uid/gid (MVP uses 1000+; 1001 is
// the project default per the brief, leaving 1000 free for a host user).
package sftpsync

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/vasic-digital/sftp/api/internal/store"
)

// DefaultUID is the first auto-assigned uid/gid for accounts without an
// explicit one.
const DefaultUID = 1001

// noLoginPassword disables password authentication for the account (used
// for public accounts, which authenticate by key only).
const noLoginPassword = "*"

// encryptedPasswordFlag is the atmoz users.conf flag placed at position 3
// (immediately after the password field). It tells the entrypoint to pass
// `-e` to chpasswd so the pre-hashed $6$ crypt value is stored verbatim
// instead of being double-hashed as plaintext.
const encryptedPasswordFlag = "e"

// HashFunc resolves the sha512-crypt ($6$) users.conf password field for
// an account. The store deliberately never holds plaintext, so the API
// layer supplies a resolver that knows the credential (e.g. from an
// in-memory provision map populated at account create/update time). A nil
// HashFunc renders every non-public account with `*` (no password login).
type HashFunc func(username string) string

// Render converts accounts into users.conf content (deterministic: lines
// sorted by username). Disabled accounts are omitted — a disabled account
// must not be able to log in, and atmoz re-reads the file on container
// restart (MVP doc: add/remove users by editing this file).
func Render(accounts []*store.Account, hashes HashFunc) string {
	sorted := make([]*store.Account, 0, len(accounts))
	for _, a := range accounts {
		if a.Enabled {
			sorted = append(sorted, a)
		}
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Username < sorted[j].Username })

	var sb strings.Builder
	nextUID := DefaultUID
	for _, a := range sorted {
		uid, gid := resolveIDs(a, &nextUID)
		sb.WriteString(renderLine(a, uid, gid, hashes))
		sb.WriteByte('\n')
	}
	return sb.String()
}

// resolveIDs returns the account's explicit uid/gid, or auto-assigns the
// next free id (shared for uid and gid, matching the MVP examples).
func resolveIDs(a *store.Account, next *int) (int, int) {
	uid, gid := 0, 0
	if a.UID != nil {
		uid = *a.UID
	}
	if a.GID != nil {
		gid = *a.GID
	}
	if uid == 0 {
		uid = *next
		*next = *next + 1
	}
	if gid == 0 {
		gid = uid
	}
	return uid, gid
}

// renderLine builds one users.conf line for the account.
//
// atmoz/sftp users.conf format (positional):
//
//	user:password:e:uid:gid:home_directory
//
// The "e" at position 3 (IMMEDIATELY after the password) is the encrypted-
// password flag: it tells the entrypoint's create-sftp-user script to call
// chpasswd -e, storing the pre-hashed $6$ value verbatim. Without "e" in
// this position, chpasswd re-hashes the field as plaintext → double-hashing
// → all authentication fails.
//
// PERMISSION HANDLING:
//   - read_write: full $6$ crypt hash with :e for verbatim storage;
//     filesystem permissions set by ProvisionHomeDirs (user-owned, 755).
//   - read_only:  same hash rendering; filesystem permissions set by
//     ProvisionHomeDirs (chmod 555 — owner cannot write through SFTP).
//   - public:     password "*" (impossible password — no password login),
//     still with :e so the "encrypted" flag is set; public accounts are
//     reachable only via key-based auth provisioned out of band
//
// FTP-021 PERMISSION ENFORCEMENT:
// The users.conf format has no read/write permission semantics. atmoz/sftp's
// create-sftp-user script creates subdirectories with chown $uid:users and
// no explicit chmod, so the default umask grants the owner write access. The
// ProvisionHomeDirs function (called after Write in the sync handler) sets:
//   - read_only:  chmod 555 (owner can read/traverse but not write;
//     ForceCommand internal-sftp prevents the user from chmod'ing it back)
//   - read_write: chmod 755 (owner has full read/write access)
func renderLine(a *store.Account, uid, gid int, hashes HashFunc) string {
	password := ""
	if hashes != nil {
		password = hashes(a.Username)
	}
	if a.Permission == store.PermissionPublic {
		password = noLoginPassword
	}
	if password == "" {
		// Defensive: never render an empty password (that would mean an
		// empty-password login). This happens when no crypt hash was
		// provisioned for the account — fail safe to no-password-login.
		password = noLoginPassword
	}
	return fmt.Sprintf("%s:%s:e:%d:%d:%s", a.Username, password, uid, gid, a.HomeDir)
}

// Write renders the accounts and atomically writes the users.conf file
// (write-temp-then-rename, per §9 data-safety discipline) with 0600
// permissions — the file holds password hashes and must not be
// world-readable on the host. Returns the number of rendered lines.
func Write(path string, accounts []*store.Account, hashes HashFunc) (int, error) {
	content := Render(accounts, hashes)
	lines := 0
	if content != "" {
		lines = strings.Count(content, "\n")
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, fmt.Errorf("sftpsync: create dir %s: %w", dir, err)
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, []byte(content), 0o600); err != nil {
		_ = os.Remove(tmp) // Clean up 0-byte file left by O_CREAT on ENOSPC
		return 0, fmt.Errorf("sftpsync: write %s: %w", tmp, err)
	}
	if err := os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
		return 0, fmt.Errorf("sftpsync: rename to %s: %w", path, err)
	}
	return lines, nil
}

// ProvisionHomeDirs ensures each account's home subdirectory exists on the
// host filesystem with permissions matching the account's permission type.
//
// The dataDir is the host-side path mounted at /home inside the SFTP
// container (e.g. ./data from docker-compose). The HomeDir field from
// each account is the 6th users.conf field — atmoz/sftp's create-sftp-user
// script creates /home/<user>/<HomeDir> (comma-separated for multiple dirs).
//
// Permission mapping (FTP-021):
//   - read_only  → chmod 0o555 (r-xr-xr-x): owner can read/traverse but
//     cannot write. The container's ForceCommand internal-sftp prevents
//     the user from running chmod to regain write access.
//   - read_write → chmod 0o755 (rwxr-xr-x): owner has full access. This
//     is the default atmoz behaviour.
//   - public     → chmod 0o555: most restrictive safe default. Public
//     accounts authenticate by key only and should never default to write.
//
// Directories that already exist have their permissions updated in-place
// (idempotent). Missing intermediate parents are created with 0o755.
//
// Returns a slice of paths that were created or updated, suitable for
// logging. Errors on a single path do not stop processing of remaining
// accounts — the function collects errors and returns them joined.
func ProvisionHomeDirs(dataDir string, accounts []*store.Account) ([]string, error) {
	if dataDir == "" {
		return nil, nil
	}
	var (
		paths  []string
		errs   []string
	)

	for _, a := range accounts {
		if !a.Enabled {
			continue
		}
		if a.HomeDir == "" {
			continue
		}
		perm := dirPerm(a.Permission)
		for _, sub := range splitDirs(a.HomeDir) {
			sub = strings.TrimPrefix(sub, "/")
			p := filepath.Join(dataDir, a.Username, sub)
			// Path traversal guard: ensure the resolved path stays
			// within dataDir. Username is already validated at
			// creation time (^[a-z_][a-z0-9_-]{0,31}$) but home-dir
			// subdirectories are free-form — validate here.
			absData, _ := filepath.Abs(dataDir)
			absP, err := filepath.Abs(p)
			if err != nil {
				errs = append(errs, fmt.Sprintf("%s: cannot resolve: %v", p, err))
				continue
			}
			if !strings.HasPrefix(filepath.Clean(absP), filepath.Clean(absData)+string(os.PathSeparator)) {
				errs = append(errs, fmt.Sprintf("%s: path escapes data directory %s", p, dataDir))
				continue
			}
			if err := ensureDir(p, perm); err != nil {
				errs = append(errs, fmt.Sprintf("%s: %v", p, err))
				continue
			}
			paths = append(paths, p)
		}
	}
	if len(errs) > 0 {
		return paths, fmt.Errorf("sftpsync: provision home dirs: %s", strings.Join(errs, "; "))
	}
	return paths, nil
}

// dirPerm maps an account permission to the filesystem directory mode.
func dirPerm(permission string) os.FileMode {
	switch permission {
	case store.PermissionReadWrite:
		return 0o755
	default:
		// read_only, public, and any unknown value default to read-only.
		return 0o555
	}
}

// splitDirs splits a comma-separated directory list (the atmoz format).
func splitDirs(homeDir string) []string {
	var out []string
	for _, d := range strings.Split(homeDir, ",") {
		d = strings.TrimSpace(d)
		if d == "" {
			continue
		}
		out = append(out, d)
	}
	if len(out) == 0 {
		// If HomeDir somehow has no usable segments, fall back to the
		// root of the user's chroot (the user's home directory itself).
		return []string{""}
	}
	return out
}

// ensureDir creates a directory (and its parents with 0o755) if it does
// not exist, then sets its mode to perm regardless of prior state
// (idempotent).
func ensureDir(path string, perm os.FileMode) error {
	if err := os.MkdirAll(path, 0o755); err != nil {
		return err
	}
	return os.Chmod(path, perm)
}
