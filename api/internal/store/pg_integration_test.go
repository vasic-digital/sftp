//go:build integration
// +build integration

package store

import (
	"context"
	"os"
	"testing"
)

func TestPostgreSQL_CRUD(t *testing.T) {
	dsn := os.Getenv("PG_TEST_DSN")
	if dsn == "" {
		dsn = "postgres://postgres:testpass@localhost:54399/sftp?sslmode=disable"
	}
	ctx := context.Background()

	st, err := Open(ctx, "postgres", dsn)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	defer st.Close()

	if err := st.HealthCheck(ctx); err != nil {
		t.Fatalf("health: %v", err)
	}

	// Seed admin
	created, err := st.SeedAdmin(ctx, "admin", "$2a$12$abcdefghijklmnopqrstuuOeFakesHashValueForTests1234")
	if err != nil {
		t.Fatalf("seed admin: %v", err)
	}
	if !created {
		t.Fatal("seed admin returned false")
	}

	admin, err := st.GetAdmin(ctx, "admin")
	if err != nil {
		t.Fatalf("get admin: %v", err)
	}
	if admin.Username != "admin" {
		t.Errorf("username = %q, want admin", admin.Username)
	}

	// Create account
	uid, gid := 1001, 1001
	a := &Account{
		Username:     "testuser",
		PasswordHash: "$2a$12$abcdefghijklmnopqrstuuOeFakesHashValueForTests1234",
		Permission:   PermissionReadWrite,
		UID:          &uid,
		GID:          &gid,
		HomeDir:      "/testuser",
		Enabled:      true,
	}
	if err := st.CreateAccount(ctx, a); err != nil {
		t.Fatalf("create: %v", err)
	}

	// Duplicate
	err = st.CreateAccount(ctx, a)
	if err == nil {
		t.Fatal("duplicate create should fail")
	}
	t.Logf("duplicate: %v", err)

	// Get
	got, err := st.GetAccount(ctx, "testuser")
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Permission != PermissionReadWrite {
		t.Errorf("permission = %q", got.Permission)
	}

	// List
	accounts, err := st.ListAccounts(ctx)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(accounts) != 1 {
		t.Errorf("count = %d, want 1", len(accounts))
	}

	// Update
	got.Permission = PermissionReadOnly
	if err := st.UpdateAccount(ctx, got); err != nil {
		t.Fatalf("update: %v", err)
	}
	updated, _ := st.GetAccount(ctx, "testuser")
	if updated.Permission != PermissionReadOnly {
		t.Errorf("updated = %q", updated.Permission)
	}

	// Delete
	if err := st.DeleteAccount(ctx, "testuser"); err != nil {
		t.Fatalf("delete: %v", err)
	}
}
