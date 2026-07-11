// Package sftpsync renders the SFTP account database into the atmoz/sftp
// users.conf file the container consumes (mounted read-only, see
// deploy/docker-compose.yml `SFTP_USERS_FILE`).
//
// File format (project MVP spec, docs/research/mvp/MVP.md):
//
//	user:password:uid:gid:home_directory[:options]
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
// PERMISSION MAPPING DECISION (evidence-based):
//
//	The users.conf format has no read/write permission semantics — that is
//	filesystem UID/GID ownership. atmoz's only per-user option flag is `e`
//	(chroot to home). Therefore:
//	  - every account renders its home dir as the 5th field;
//	  - read_write accounts get NO option suffix (full access to their
//	    home, which is the container-default behaviour);
//	  - read_only accounts get the `:e` chroot suffix so the session is
//	    confined to the home directory (the only restriction the atmoz
//	    layer can express); the read-only enforcement itself is a
//	    filesystem-ownership concern handled by the deploy layer
//	    (documented in api/README.md as a known boundary — the API cannot
//	    chown host directories from inside rootless constraints);
//	  - public accounts are rendered with password `*` (impossible
//	    password — no password login) plus the `:e` chroot suffix; public
//	    accounts are reachable only with key-based auth provisioned out
//	    of band. Public access is NEVER a default anywhere in the system
//	    (the API layer 422s any public grant without explicit
//	    acknowledgement).
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

// chrootOption is the atmoz users.conf option that chroots the session to
// the user's home directory.
const chrootOption = "e"

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
func renderLine(a *store.Account, uid, gid int, hashes HashFunc) string {
	password := ""
	if hashes != nil {
		password = hashes(a.Username)
	}
	options := ""
	switch a.Permission {
	case store.PermissionReadWrite:
		// Default container behaviour: full access to the home dir.
	case store.PermissionReadOnly:
		options = chrootOption
	case store.PermissionPublic:
		password = noLoginPassword
		options = chrootOption
	}
	if password == "" {
		// Defensive: never render an empty password (that would mean an
		// empty-password login). This happens when no crypt hash was
		// provisioned for the account — fail safe to no-password-login.
		password = noLoginPassword
	}
	line := fmt.Sprintf("%s:%s:%d:%d:%s", a.Username, password, uid, gid, a.HomeDir)
	if options != "" {
		line += ":" + options
	}
	return line
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
