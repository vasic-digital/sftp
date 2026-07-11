package sftpsync

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/vasic-digital/sftp/api/internal/crypt"
	"github.com/vasic-digital/sftp/api/internal/store"
)

func intPtr(v int) *int { return &v }

func mkAccount(username, permission string, uid, gid *int, home string, enabled bool) *store.Account {
	return &store.Account{
		Username:     username,
		PasswordHash: "$2a$12$placeholder-bcrypt-never-rendered",
		Permission:   permission,
		UID:          uid,
		GID:          gid,
		HomeDir:      home,
		Enabled:      enabled,
		CreatedAt:    time.Now(),
		UpdatedAt:    time.Now(),
	}
}

func TestRenderGolden(t *testing.T) {
	// Fixed crypt hash for the golden file — this is the REAL openssl
	// passwd -6 output for ("password123", salt "abcd1234"), also asserted
	// byte-identical in the crypt package tests.
	const aliceHash = "$6$abcd1234$7NLbx1ZM8lie0XNZL1m5Rqsi7Wq9h90yfkd9m1254W0eGGVldajbioqTsEdrsMcke.LhZw3OxV4lNVxs9tny60"
	const carolHash = "$6$zz$MFKplP0V/L6Uj1cQElKpERQCARYucMRoaLHZ1XunZAwd5y8156WPyuNRgod.sPSm8C.pZhN9.vrdW.MuF3r/61"

	accounts := []*store.Account{
		mkAccount("bob", store.PermissionReadOnly, nil, nil, "/sftp_data/bob", true),
		mkAccount("alice", store.PermissionReadWrite, intPtr(1000), intPtr(1000), "/sftp_data/alice", true),
		mkAccount("carol", store.PermissionPublic, nil, nil, "/sftp_data/carol", true),
		mkAccount("dave", store.PermissionReadWrite, nil, nil, "/sftp_data/dave", false), // disabled → omitted
	}
	hashes := func(username string) string {
		switch username {
		case "alice":
			return aliceHash
		case "bob":
			return carolHash
		default:
			return ""
		}
	}

	got := Render(accounts, hashes)
	want := "alice:" + aliceHash + ":1000:1000:/sftp_data/alice\n" +
		"bob:" + carolHash + ":1001:1001:/sftp_data/bob:e\n" +
		"carol:*:1002:1002:/sftp_data/carol:e\n"

	if got != want {
		t.Fatalf("golden render mismatch:\n--- got ---\n%s--- want ---\n%s", got, want)
	}
}

func TestRenderSortedDeterministic(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("zeta", store.PermissionReadWrite, nil, nil, "/z", true),
		mkAccount("alpha", store.PermissionReadWrite, nil, nil, "/a", true),
		mkAccount("mid", store.PermissionReadWrite, nil, nil, "/m", true),
	}
	out := Render(accounts, nil)
	names := []string{}
	for _, line := range strings.Split(strings.TrimSpace(out), "\n") {
		names = append(names, strings.SplitN(line, ":", 2)[0])
	}
	if strings.Join(names, ",") != "alpha,mid,zeta" {
		t.Fatalf("order = %v, want alpha,mid,zeta", names)
	}
	// Second render must be byte-identical (deterministic).
	if Render(accounts, nil) != out {
		t.Fatal("render not deterministic")
	}
}

func TestRenderAutoIDAssignment(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("a", store.PermissionReadWrite, nil, nil, "/a", true),
		mkAccount("b", store.PermissionReadWrite, nil, nil, "/b", true),
		mkAccount("c", store.PermissionReadWrite, intPtr(1050), nil, "/c", true), // explicit uid, auto gid
	}
	out := Render(accounts, nil)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if !strings.Contains(lines[0], ":1001:1001:") {
		t.Fatalf("first auto id = %q, want uid/gid 1001", lines[0])
	}
	if !strings.Contains(lines[1], ":1002:1002:") {
		t.Fatalf("second auto id = %q, want uid/gid 1002", lines[1])
	}
	if !strings.Contains(lines[2], ":1050:1050:") {
		t.Fatalf("explicit uid line = %q, want gid mirroring uid 1050", lines[2])
	}
}

func TestRenderFailClosedWithoutHash(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("alice", store.PermissionReadWrite, nil, nil, "/a", true),
	}
	out := Render(accounts, nil)
	if !strings.HasPrefix(out, "alice:*:") {
		t.Fatalf("missing hash must render '*' (no password login), got %q", out)
	}
}

func TestRenderPublicNeverGetsPassword(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("pub", store.PermissionPublic, nil, nil, "/p", true),
	}
	out := Render(accounts, func(string) string { return "$6$salt$somehash" })
	if !strings.HasPrefix(out, "pub:*:") {
		t.Fatalf("public account must render '*' even when a hash is provisioned, got %q", out)
	}
	if !strings.HasSuffix(strings.TrimSpace(out), ":e") {
		t.Fatalf("public account must be chrooted, got %q", out)
	}
}

func TestWriteAtomicAndPerms(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "users.conf")
	accounts := []*store.Account{
		mkAccount("alice", store.PermissionReadOnly, nil, nil, "/a", true),
	}
	lines, err := Write(path, accounts, nil)
	if err != nil {
		t.Fatalf("write: %v", err)
	}
	if lines != 1 {
		t.Fatalf("lines = %d, want 1", lines)
	}
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if !strings.HasPrefix(string(content), "alice:*:1001:1001:/a:e") {
		t.Fatalf("file content = %q", content)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Fatalf("file mode = %o, want 600 (holds password hashes)", perm)
	}
	// No temp file left behind.
	if _, err := os.Stat(path + ".tmp"); !os.IsNotExist(err) {
		t.Fatal("temp file not cleaned up")
	}
}

func TestWriteEmptyAccountSet(t *testing.T) {
	path := filepath.Join(t.TempDir(), "users.conf")
	lines, err := Write(path, nil, nil)
	if err != nil {
		t.Fatalf("write empty: %v", err)
	}
	if lines != 0 {
		t.Fatalf("lines = %d, want 0", lines)
	}
	content, _ := os.ReadFile(path)
	if len(content) != 0 {
		t.Fatalf("empty account set must produce empty file, got %q", content)
	}
}

func TestRenderedCryptHashVerifiesWithOpenSSL(t *testing.T) {
	// End-to-end proof of the password-field decision: a hash produced by
	// our crypt package, rendered into a users.conf line, parses and
	// verifies with the same Verify function used to check openssl output.
	h, err := crypt.Hash("S3cret!Pass")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	accounts := []*store.Account{
		mkAccount("alice", store.PermissionReadWrite, nil, nil, "/a", true),
	}
	out := Render(accounts, func(string) string { return h })
	fields := strings.Split(strings.TrimSpace(out), ":")
	if len(fields) != 5 {
		t.Fatalf("line fields = %d, want 5: %q", len(fields), out)
	}
	if !crypt.Verify("S3cret!Pass", fields[1]) {
		t.Fatal("rendered hash does not verify against the original password")
	}
	if crypt.Verify("wrong", fields[1]) {
		t.Fatal("rendered hash accepted a wrong password")
	}
}
