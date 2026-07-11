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
	want := "alice:" + aliceHash + ":e:1000:1000:/sftp_data/alice\n" +
		"bob:" + carolHash + ":e:1001:1001:/sftp_data/bob\n" +
		"carol:*:e:1002:1002:/sftp_data/carol\n"

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
	if !strings.HasPrefix(out, "alice:*:e:") {
		t.Fatalf("missing hash must render '*' (no password login), got %q", out)
	}
}

func TestRenderPublicNeverGetsPassword(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("pub", store.PermissionPublic, nil, nil, "/p", true),
	}
	out := Render(accounts, func(string) string { return "$6$salt$somehash" })
	if !strings.HasPrefix(out, "pub:*:e:") {
		t.Fatalf("public account must render '*' with encrypted flag at position 3, got %q", out)
	}
	if !strings.HasSuffix(strings.TrimSpace(out), ":/p") {
		t.Fatalf("public account home dir must be last field, got %q", out)
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
	if !strings.HasPrefix(string(content), "alice:*:e:1001:1001:/a") {
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

func TestProvisionHomeDirsReadOnly(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("bob", store.PermissionReadOnly, nil, nil, "/uploads", true),
	}
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("provision: %v", err)
	}
	if len(paths) != 1 {
		t.Fatalf("paths = %d, want 1", len(paths))
	}

	// The directory should exist at <dataDir>/bob/uploads
	created := filepath.Join(dir, "bob", "uploads")
	info, err := os.Stat(created)
	if err != nil {
		t.Fatalf("stat created dir: %v", err)
	}
	if !info.IsDir() {
		t.Fatal("created path is not a directory")
	}
	// read_only → 0o555 (r-xr-xr-x, owner cannot write)
	if perm := info.Mode().Perm(); perm != 0o555 {
		t.Fatalf("perm = %o, want 0555 (read_only)", perm)
	}
}

func TestProvisionHomeDirsReadWrite(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("alice", store.PermissionReadWrite, nil, nil, "/data", true),
	}
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("provision: %v", err)
	}
	if len(paths) != 1 {
		t.Fatalf("paths = %d, want 1", len(paths))
	}

	created := filepath.Join(dir, "alice", "data")
	info, err := os.Stat(created)
	if err != nil {
		t.Fatalf("stat created dir: %v", err)
	}
	// read_write → 0o755 (rwxr-xr-x)
	if perm := info.Mode().Perm(); perm != 0o755 {
		t.Fatalf("perm = %o, want 0755 (read_write)", perm)
	}
}

func TestProvisionHomeDirsIdempotent(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("bob", store.PermissionReadOnly, nil, nil, "/files", true),
	}
	// First call creates.
	if _, err := ProvisionHomeDirs(dir, accounts); err != nil {
		t.Fatalf("first provision: %v", err)
	}
	// Second call is idempotent — no error, same paths.
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("second provision: %v", err)
	}
	if len(paths) != 1 {
		t.Fatalf("paths = %d, want 1", len(paths))
	}
	created := filepath.Join(dir, "bob", "files")
	info, err := os.Stat(created)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o555 {
		t.Fatalf("perm = %o, want 0555 after idempotent call", perm)
	}
}

func TestProvisionHomeDirsSkipsDisabled(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("dave", store.PermissionReadOnly, nil, nil, "/uploads", false), // disabled
	}
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("provision: %v", err)
	}
	if len(paths) != 0 {
		t.Fatalf("paths = %d, want 0 (disabled account)", len(paths))
	}
	// Directory must not exist.
	if _, err := os.Stat(filepath.Join(dir, "dave", "uploads")); !os.IsNotExist(err) {
		t.Fatal("directory should not exist for disabled account")
	}
}

func TestProvisionHomeDirsEmptyDataDir(t *testing.T) {
	accounts := []*store.Account{
		mkAccount("bob", store.PermissionReadOnly, nil, nil, "/x", true),
	}
	paths, err := ProvisionHomeDirs("", accounts)
	if err != nil {
		t.Fatalf("provision with empty data dir: %v", err)
	}
	if len(paths) != 0 {
		t.Fatalf("paths = %d, want 0 (empty data dir skips provisioning)", len(paths))
	}
}

func TestProvisionHomeDirsPublicDefaultsToReadOnly(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("pub", store.PermissionPublic, nil, nil, "/open", true),
	}
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("provision: %v", err)
	}
	if len(paths) != 1 {
		t.Fatalf("paths = %d, want 1", len(paths))
	}
	created := filepath.Join(dir, "pub", "open")
	info, err := os.Stat(created)
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	// public defaults to 0555 (most restrictive safe default)
	if perm := info.Mode().Perm(); perm != 0o555 {
		t.Fatalf("perm = %o, want 0555 (public defaults to read_only)", perm)
	}
}

func TestProvisionHomeDirsMultipleAccounts(t *testing.T) {
	dir := t.TempDir()
	accounts := []*store.Account{
		mkAccount("ro1", store.PermissionReadOnly, nil, nil, "/a", true),
		mkAccount("rw1", store.PermissionReadWrite, nil, nil, "/b", true),
		mkAccount("ro2", store.PermissionReadOnly, nil, nil, "/c", true),
	}
	paths, err := ProvisionHomeDirs(dir, accounts)
	if err != nil {
		t.Fatalf("provision: %v", err)
	}
	if len(paths) != 3 {
		t.Fatalf("paths = %d, want 3", len(paths))
	}
	// Verify each has correct perms.
	cases := []struct {
		user string
		sub  string
		perm os.FileMode
	}{
		{"ro1", "a", 0o555},
		{"rw1", "b", 0o755},
		{"ro2", "c", 0o555},
	}
	for _, tc := range cases {
		p := filepath.Join(dir, tc.user, tc.sub)
		info, err := os.Stat(p)
		if err != nil {
			t.Fatalf("stat %s: %v", p, err)
		}
		if perm := info.Mode().Perm(); perm != tc.perm {
			t.Fatalf("%s perm = %o, want %o", p, perm, tc.perm)
		}
	}
}

func TestDirPermMapping(t *testing.T) {
	if dirPerm(store.PermissionReadWrite) != 0o755 {
		t.Fatal("read_write should map to 0755")
	}
	if dirPerm(store.PermissionReadOnly) != 0o555 {
		t.Fatal("read_only should map to 0555")
	}
	if dirPerm(store.PermissionPublic) != 0o555 {
		t.Fatal("public should map to 0555 (safe default)")
	}
	if dirPerm("unknown") != 0o555 {
		t.Fatal("unknown permission should default to 0555 (safe default)")
	}
}

func TestSplitDirs(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"/sftp_data/bob", []string{"/sftp_data/bob"}},
		{"a,b,c", []string{"a", "b", "c"}},
		{"a, b ,c", []string{"a", "b", "c"}}, // trims spaces
		{"", []string{""}}, // empty string returns chroot-root fallback
		{",", []string{""}}, // only commas returns chroot-root fallback
	}
	for _, tt := range tests {
		got := splitDirs(tt.input)
		if len(got) != len(tt.want) {
			t.Fatalf("splitDirs(%q) = %v, want %v", tt.input, got, tt.want)
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Fatalf("splitDirs(%q)[%d] = %q, want %q", tt.input, i, got[i], tt.want[i])
			}
		}
	}
	// Empty result produces single empty string (fallback to chroot root).
	if got := splitDirs(""); len(got) != 1 || got[0] != "" {
		t.Fatalf("splitDirs(\"\") = %v, want [\"\"]", got)
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
	if len(fields) != 6 {
		t.Fatalf("line fields = %d, want 6: %q", len(fields), out)
	}
	if !crypt.Verify("S3cret!Pass", fields[1]) {
		t.Fatal("rendered hash does not verify against the original password")
	}
	if crypt.Verify("wrong", fields[1]) {
		t.Fatal("rendered hash accepted a wrong password")
	}
}
