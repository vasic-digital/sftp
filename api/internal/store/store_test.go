package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
)

// openTestStore opens a REAL SQLite database file in a temp dir — never
// an in-memory mock (§11.4.27: no fakes beyond unit-test scope, and even
// here we exercise the genuine on-disk path).
func openTestStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "test.db")
	s, err := Open(ctx, "sqlite", path)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() {
		if err := s.Close(); err != nil {
			t.Errorf("close store: %v", err)
		}
	})
	return s, ctx
}

func testAccount(username string) *Account {
	uid, gid := 1001, 1001
	return &Account{
		Username:     username,
		PasswordHash: "$2a$12$abcdefghijklmnopqrstuuOeFakesHashValueForTests1234",
		Permission:   PermissionReadOnly,
		UID:          &uid,
		GID:          &gid,
		HomeDir:      "/" + username,
		Enabled:      true,
	}
}

func TestCreateAndGetAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	want := testAccount("alice")
	if err := s.CreateAccount(ctx, want); err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := s.GetAccount(ctx, "alice")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Username != want.Username {
		t.Errorf("username = %q, want %q", got.Username, want.Username)
	}
	if got.PasswordHash != want.PasswordHash {
		t.Errorf("password hash mismatch")
	}
	if got.Permission != PermissionReadOnly {
		t.Errorf("permission = %q, want %q", got.Permission, PermissionReadOnly)
	}
	if got.UID == nil || *got.UID != 1001 {
		t.Errorf("uid = %v, want 1001", got.UID)
	}
	if got.GID == nil || *got.GID != 1001 {
		t.Errorf("gid = %v, want 1001", got.GID)
	}
	if got.HomeDir != "/alice" {
		t.Errorf("home = %q, want /alice", got.HomeDir)
	}
	if !got.Enabled {
		t.Errorf("enabled = false, want true")
	}
	if got.CreatedAt.IsZero() || got.UpdatedAt.IsZero() {
		t.Errorf("timestamps not populated: created=%v updated=%v", got.CreatedAt, got.UpdatedAt)
	}
}

func TestCreateDuplicateUsernameRejected(t *testing.T) {
	s, ctx := openTestStore(t)
	if err := s.CreateAccount(ctx, testAccount("alice")); err != nil {
		t.Fatalf("create: %v", err)
	}
	err := s.CreateAccount(ctx, testAccount("alice"))
	if !errors.Is(err, ErrDuplicateUsername) {
		t.Fatalf("create duplicate: err = %v, want ErrDuplicateUsername", err)
	}
}

func TestGetMissingAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	_, err := s.GetAccount(ctx, "ghost")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("get missing: err = %v, want ErrNotFound", err)
	}
}

func TestListAccountsOrdered(t *testing.T) {
	s, ctx := openTestStore(t)
	for _, name := range []string{"carol", "alice", "bob"} {
		if err := s.CreateAccount(ctx, testAccount(name)); err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
	}
	got, err := s.ListAccounts(ctx)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(got) != 3 {
		t.Fatalf("list len = %d, want 3", len(got))
	}
	wantOrder := []string{"alice", "bob", "carol"}
	for i, name := range wantOrder {
		if got[i].Username != name {
			t.Errorf("list[%d] = %q, want %q", i, got[i].Username, name)
		}
	}
}

func TestUpdateAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	a := testAccount("alice")
	if err := s.CreateAccount(ctx, a); err != nil {
		t.Fatalf("create: %v", err)
	}

	a.Permission = PermissionReadWrite
	a.Enabled = false
	a.HomeDir = "/srv/alice"
	if err := s.UpdateAccount(ctx, a); err != nil {
		t.Fatalf("update: %v", err)
	}

	got, err := s.GetAccount(ctx, "alice")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Permission != PermissionReadWrite {
		t.Errorf("permission = %q, want %q", got.Permission, PermissionReadWrite)
	}
	if got.Enabled {
		t.Errorf("enabled = true, want false")
	}
	if got.HomeDir != "/srv/alice" {
		t.Errorf("home = %q, want /srv/alice", got.HomeDir)
	}
	if !got.UpdatedAt.After(got.CreatedAt) {
		t.Errorf("updated_at (%v) not after created_at (%v)", got.UpdatedAt, got.CreatedAt)
	}
}

func TestUpdateMissingAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	err := s.UpdateAccount(ctx, testAccount("ghost"))
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("update missing: err = %v, want ErrNotFound", err)
	}
}

func TestDeleteAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	if err := s.CreateAccount(ctx, testAccount("alice")); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := s.DeleteAccount(ctx, "alice"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.GetAccount(ctx, "alice"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("get after delete: err = %v, want ErrNotFound", err)
	}
}

func TestDeleteMissingAccount(t *testing.T) {
	s, ctx := openTestStore(t)
	if err := s.DeleteAccount(ctx, "ghost"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("delete missing: err = %v, want ErrNotFound", err)
	}
}

func TestAccountValidation(t *testing.T) {
	s, ctx := openTestStore(t)

	bad := []struct {
		name    string
		account *Account
	}{
		{"empty username", &Account{Username: "", PasswordHash: "h", Permission: PermissionReadOnly}},
		{"uppercase username", &Account{Username: "Alice", PasswordHash: "h", Permission: PermissionReadOnly}},
		{"starts with digit", &Account{Username: "1alice", PasswordHash: "h", Permission: PermissionReadOnly}},
		{"too long", &Account{Username: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", PasswordHash: "h", Permission: PermissionReadOnly}},
		{"space", &Account{Username: "al ice", PasswordHash: "h", Permission: PermissionReadOnly}},
		{"invalid permission", &Account{Username: "alice", PasswordHash: "h", Permission: "root"}},
		{"empty permission", &Account{Username: "alice", PasswordHash: "h", Permission: ""}},
		{"empty password hash", &Account{Username: "alice", PasswordHash: "", Permission: PermissionReadOnly}},
		{"relative home", &Account{Username: "alice", PasswordHash: "h", Permission: PermissionReadOnly, HomeDir: "alice"}},
	}
	for _, tc := range bad {
		err := s.CreateAccount(ctx, tc.account)
		if !errors.Is(err, ErrValidation) {
			t.Errorf("%s: err = %v, want ErrValidation", tc.name, err)
		}
	}

	// Valid edge usernames.
	for _, name := range []string{"a", "_", "_user-1", "a2345678901234567890123456789012"} {
		a := testAccount(name)
		if err := s.CreateAccount(ctx, a); err != nil {
			t.Errorf("valid username %q rejected: %v", name, err)
		}
	}
}

func TestNilUIDGIDRoundTrip(t *testing.T) {
	s, ctx := openTestStore(t)
	a := testAccount("noids")
	a.UID = nil
	a.GID = nil
	if err := s.CreateAccount(ctx, a); err != nil {
		t.Fatalf("create: %v", err)
	}
	got, err := s.GetAccount(ctx, "noids")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.UID != nil || got.GID != nil {
		t.Errorf("uid/gid = %v/%v, want nil/nil", got.UID, got.GID)
	}
}

func TestSeedAndGetAdmin(t *testing.T) {
	s, ctx := openTestStore(t)
	created, err := s.SeedAdmin(ctx, "admin", "$2a$12$hash")
	if err != nil {
		t.Fatalf("seed: %v", err)
	}
	if !created {
		t.Fatalf("seed created = false, want true")
	}
	// Second seed must be a no-op.
	created, err = s.SeedAdmin(ctx, "admin", "$2a$12$other")
	if err != nil {
		t.Fatalf("re-seed: %v", err)
	}
	if created {
		t.Fatalf("re-seed created = true, want false")
	}

	admin, err := s.GetAdmin(ctx, "admin")
	if err != nil {
		t.Fatalf("get admin: %v", err)
	}
	if admin.PasswordHash != "$2a$12$hash" {
		t.Errorf("admin hash overwritten by re-seed: %q", admin.PasswordHash)
	}
}

func TestGetMissingAdmin(t *testing.T) {
	s, ctx := openTestStore(t)
	if _, err := s.GetAdmin(ctx, "ghost"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("get missing admin: err = %v, want ErrNotFound", err)
	}
}

func TestSeedAdminValidation(t *testing.T) {
	s, ctx := openTestStore(t)
	if _, err := s.SeedAdmin(ctx, "", "hash"); !errors.Is(err, ErrValidation) {
		t.Errorf("empty username: want ErrValidation, got %v", err)
	}
	if _, err := s.SeedAdmin(ctx, "admin", ""); !errors.Is(err, ErrValidation) {
		t.Errorf("empty hash: want ErrValidation, got %v", err)
	}
}

func TestHealthCheck(t *testing.T) {
	s, ctx := openTestStore(t)
	if err := s.HealthCheck(ctx); err != nil {
		t.Fatalf("health: %v", err)
	}
}

func TestMigrationsIdempotent(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "mig.db")
	s1, err := Open(ctx, "sqlite", path)
	if err != nil {
		t.Fatalf("open 1: %v", err)
	}
	if err := s1.CreateAccount(ctx, testAccount("alice")); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := s1.Close(); err != nil {
		t.Fatalf("close 1: %v", err)
	}
	// Re-open the same file: migrations must be skipped and data retained.
	s2, err := Open(ctx, "sqlite", path)
	if err != nil {
		t.Fatalf("open 2: %v", err)
	}
	defer func() { _ = s2.Close() }()
	if _, err := s2.GetAccount(ctx, "alice"); err != nil {
		t.Fatalf("get after reopen: %v", err)
	}
}
