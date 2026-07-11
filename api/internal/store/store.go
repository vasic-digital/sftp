// Package store is the SQLite persistence layer for the SFTP Enterprise
// API: account CRUD, super-admin credentials, and schema migrations.
//
// It builds on digital.vasic.database/pkg/sqlite (modernc.org/sqlite,
// pure Go — no CGO required). The store never logs or returns password
// material beyond the stored bcrypt hash (§11.4.10).
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"digital.vasic.database/pkg/sqlite"
)

// Permission values — closed set.
const (
	// PermissionReadOnly grants download-only SFTP access.
	PermissionReadOnly = "read_only"
	// PermissionReadWrite grants upload + download SFTP access.
	PermissionReadWrite = "read_write"
	// PermissionPublic exposes the account without authentication.
	// NEVER a default; requires explicit acknowledgement at the API layer.
	PermissionPublic = "public"
)

// Errors returned by the store. Callers match with errors.Is.
var (
	// ErrNotFound is returned when a username does not exist.
	ErrNotFound = errors.New("store: not found")
	// ErrDuplicateUsername is returned when creating an existing username.
	ErrDuplicateUsername = errors.New("store: username already exists")
	// ErrValidation is returned when a record violates a store invariant.
	ErrValidation = errors.New("store: validation error")
)

// usernamePattern is the allowed account username shape:
// [a-z_][a-z0-9_-]{0,31} — Linux-friendly, max 32 chars.
var usernamePattern = regexp.MustCompile(`^[a-z_][a-z0-9_-]{0,31}$`)

// ValidateUsername checks the username against the closed pattern.
func ValidateUsername(username string) error {
	if !usernamePattern.MatchString(username) {
		return fmt.Errorf("%w: username %q must match %s", ErrValidation, username, usernamePattern.String())
	}
	return nil
}

// ValidatePermission checks the permission against the closed set.
func ValidatePermission(permission string) error {
	switch permission {
	case PermissionReadOnly, PermissionReadWrite, PermissionPublic:
		return nil
	default:
		return fmt.Errorf("%w: permission must be one of %s|%s|%s, got %q",
			ErrValidation, PermissionReadOnly, PermissionReadWrite, PermissionPublic, permission)
	}
}

// Account is one SFTP account row. PasswordHash holds the bcrypt hash
// used for API-level validation; the atmoz users.conf rendering derives
// its own sha512-crypt hash and never reuses this value.
type Account struct {
	Username     string
	PasswordHash string
	Permission   string
	// UID/GID are optional; nil means the sync layer auto-assigns.
	UID *int
	GID *int
	// HomeDir defaults to "/<username>" when empty.
	HomeDir   string
	Enabled   bool
	CreatedAt time.Time
	UpdatedAt time.Time
}

// Validate checks the account invariants enforced by the store.
func (a *Account) Validate() error {
	if err := ValidateUsername(a.Username); err != nil {
		return err
	}
	if err := ValidatePermission(a.Permission); err != nil {
		return err
	}
	if a.PasswordHash == "" {
		return fmt.Errorf("%w: password hash must not be empty", ErrValidation)
	}
	if a.UID != nil && *a.UID < 0 {
		return fmt.Errorf("%w: uid must be >= 0", ErrValidation)
	}
	if a.GID != nil && *a.GID < 0 {
		return fmt.Errorf("%w: gid must be >= 0", ErrValidation)
	}
	if a.HomeDir != "" && !strings.HasPrefix(a.HomeDir, "/") {
		return fmt.Errorf("%w: home dir must be an absolute path", ErrValidation)
	}
	return nil
}

// Admin is one super-admin row (API authentication only, never an SFTP
// account).
type Admin struct {
	Username     string
	PasswordHash string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// Store owns the SQLite connection and all persistence operations.
type Store struct {
	client *sqlite.Client
}

// migrations is the ordered schema history. Each entry runs once,
// tracked in schema_migrations.
var migrations = []string{
	`CREATE TABLE IF NOT EXISTS accounts (
		username      TEXT PRIMARY KEY,
		password_hash TEXT NOT NULL,
		permission    TEXT NOT NULL CHECK(permission IN ('read_only','read_write','public')),
		uid           INTEGER,
		gid           INTEGER,
		home_dir      TEXT NOT NULL DEFAULT '',
		enabled       INTEGER NOT NULL DEFAULT 1,
		created_at    TEXT NOT NULL,
		updated_at    TEXT NOT NULL
	)`,
	`CREATE TABLE IF NOT EXISTS admins (
		username      TEXT PRIMARY KEY,
		password_hash TEXT NOT NULL,
		created_at    TEXT NOT NULL,
		updated_at    TEXT NOT NULL
	)`,
}

// Open connects (creating the parent directory as needed) and applies
// any pending migrations.
func Open(ctx context.Context, path string) (*Store, error) {
	if path == "" {
		return nil, fmt.Errorf("store: db path must not be empty")
	}
	if path != ":memory:" {
		if dir := filepath.Dir(path); dir != "." && dir != "" {
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return nil, fmt.Errorf("store: create db dir: %w", err)
			}
		}
	}

	cfg := sqlite.DefaultConfig(path)
	client := sqlite.New(cfg)
	if err := client.Connect(ctx); err != nil {
		return nil, fmt.Errorf("store: connect: %w", err)
	}

	s := &Store{client: client}
	if err := s.migrate(ctx); err != nil {
		_ = client.Close()
		return nil, err
	}
	return s, nil
}

// migrate creates the bookkeeping table and applies pending migrations
// inside a transaction per migration.
func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.client.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version    INTEGER PRIMARY KEY,
		applied_at TEXT NOT NULL
	)`); err != nil {
		return fmt.Errorf("store: create schema_migrations: %w", err)
	}

	for i, m := range migrations {
		version := i + 1
		var applied int
		err := s.client.QueryRow(ctx,
			"SELECT COUNT(*) FROM schema_migrations WHERE version = ?", version,
		).Scan(&applied)
		if err != nil {
			return fmt.Errorf("store: check migration %d: %w", version, err)
		}
		if applied > 0 {
			continue
		}
		tx, err := s.client.Begin(ctx)
		if err != nil {
			return fmt.Errorf("store: begin migration %d: %w", version, err)
		}
		if _, err := tx.Exec(ctx, m); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("store: apply migration %d: %w", version, err)
		}
		if _, err := tx.Exec(ctx,
			"INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
			version, time.Now().UTC().Format(time.RFC3339Nano),
		); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("store: record migration %d: %w", version, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("store: commit migration %d: %w", version, err)
		}
	}
	return nil
}

// Close releases the SQLite connection.
func (s *Store) Close() error {
	return s.client.Close()
}

// HealthCheck verifies the database is reachable.
func (s *Store) HealthCheck(ctx context.Context) error {
	return s.client.HealthCheck(ctx)
}

// CreateAccount inserts a new account. Returns ErrDuplicateUsername when
// the username already exists.
func (s *Store) CreateAccount(ctx context.Context, a *Account) error {
	if err := a.Validate(); err != nil {
		return err
	}
	now := time.Now().UTC()
	a.CreatedAt = now
	a.UpdatedAt = now

	_, err := s.client.Exec(ctx,
		`INSERT INTO accounts
			(username, password_hash, permission, uid, gid, home_dir, enabled, created_at, updated_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		a.Username, a.PasswordHash, a.Permission,
		nullInt(a.UID), nullInt(a.GID), a.HomeDir, boolInt(a.Enabled),
		a.CreatedAt.Format(time.RFC3339Nano), a.UpdatedAt.Format(time.RFC3339Nano),
	)
	if err != nil {
		if isUniqueViolation(err) {
			return fmt.Errorf("%w: %q", ErrDuplicateUsername, a.Username)
		}
		return fmt.Errorf("store: create account: %w", err)
	}
	return nil
}

// GetAccount returns one account by username, or ErrNotFound.
func (s *Store) GetAccount(ctx context.Context, username string) (*Account, error) {
	row := s.client.QueryRow(ctx,
		`SELECT username, password_hash, permission, uid, gid, home_dir, enabled, created_at, updated_at
		 FROM accounts WHERE username = ?`, username)
	a, err := scanAccount(row)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("%w: %q", ErrNotFound, username)
		}
		return nil, fmt.Errorf("store: get account: %w", err)
	}
	return a, nil
}

// ListAccounts returns all accounts ordered by username.
func (s *Store) ListAccounts(ctx context.Context) ([]*Account, error) {
	rows, err := s.client.Query(ctx,
		`SELECT username, password_hash, permission, uid, gid, home_dir, enabled, created_at, updated_at
		 FROM accounts ORDER BY username ASC`)
	if err != nil {
		return nil, fmt.Errorf("store: list accounts: %w", err)
	}
	defer func() { _ = rows.Close() }()

	var out []*Account
	for rows.Next() {
		a, err := scanAccount(rows)
		if err != nil {
			return nil, fmt.Errorf("store: scan account: %w", err)
		}
		out = append(out, a)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: iterate accounts: %w", err)
	}
	return out, nil
}

// UpdateAccount replaces the mutable fields of an existing account.
// Returns ErrNotFound when the username does not exist.
func (s *Store) UpdateAccount(ctx context.Context, a *Account) error {
	if err := a.Validate(); err != nil {
		return err
	}
	a.UpdatedAt = time.Now().UTC()

	res, err := s.client.Exec(ctx,
		`UPDATE accounts
		 SET password_hash = ?, permission = ?, uid = ?, gid = ?, home_dir = ?, enabled = ?, updated_at = ?
		 WHERE username = ?`,
		a.PasswordHash, a.Permission, nullInt(a.UID), nullInt(a.GID), a.HomeDir,
		boolInt(a.Enabled), a.UpdatedAt.Format(time.RFC3339Nano), a.Username,
	)
	if err != nil {
		return fmt.Errorf("store: update account: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("store: update rows affected: %w", err)
	}
	if n == 0 {
		return fmt.Errorf("%w: %q", ErrNotFound, a.Username)
	}
	return nil
}

// DeleteAccount removes an account. Returns ErrNotFound when missing.
func (s *Store) DeleteAccount(ctx context.Context, username string) error {
	res, err := s.client.Exec(ctx, "DELETE FROM accounts WHERE username = ?", username)
	if err != nil {
		return fmt.Errorf("store: delete account: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("store: delete rows affected: %w", err)
	}
	if n == 0 {
		return fmt.Errorf("%w: %q", ErrNotFound, username)
	}
	return nil
}

// SeedAdmin inserts the super-admin row if and only if no admin with
// that username exists yet. Returns true when the row was created.
// The caller passes an already-bcrypt-hashed password; the store never
// sees plaintext.
func (s *Store) SeedAdmin(ctx context.Context, username, passwordHash string) (bool, error) {
	if username == "" || passwordHash == "" {
		return false, fmt.Errorf("%w: admin username and password hash are required", ErrValidation)
	}
	var existing int
	if err := s.client.QueryRow(ctx,
		"SELECT COUNT(*) FROM admins WHERE username = ?", username,
	).Scan(&existing); err != nil {
		return false, fmt.Errorf("store: check admin: %w", err)
	}
	if existing > 0 {
		return false, nil
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	if _, err := s.client.Exec(ctx,
		"INSERT INTO admins (username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?)",
		username, passwordHash, now, now,
	); err != nil {
		return false, fmt.Errorf("store: seed admin: %w", err)
	}
	return true, nil
}

// GetAdmin returns one admin by username, or ErrNotFound.
func (s *Store) GetAdmin(ctx context.Context, username string) (*Admin, error) {
	var a Admin
	var createdAt, updatedAt string
	err := s.client.QueryRow(ctx,
		"SELECT username, password_hash, created_at, updated_at FROM admins WHERE username = ?",
		username,
	).Scan(&a.Username, &a.PasswordHash, &createdAt, &updatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("%w: %q", ErrNotFound, username)
		}
		return nil, fmt.Errorf("store: get admin: %w", err)
	}
	a.CreatedAt = parseTime(createdAt)
	a.UpdatedAt = parseTime(updatedAt)
	return &a, nil
}

// rowScanner covers both db.Row and db.Rows for scanAccount.
type rowScanner interface {
	Scan(dest ...any) error
}

func scanAccount(row rowScanner) (*Account, error) {
	var a Account
	var uid, gid sql.NullInt64
	var enabled int
	var createdAt, updatedAt string
	if err := row.Scan(
		&a.Username, &a.PasswordHash, &a.Permission, &uid, &gid,
		&a.HomeDir, &enabled, &createdAt, &updatedAt,
	); err != nil {
		return nil, err
	}
	if uid.Valid {
		v := int(uid.Int64)
		a.UID = &v
	}
	if gid.Valid {
		v := int(gid.Int64)
		a.GID = &v
	}
	a.Enabled = enabled != 0
	a.CreatedAt = parseTime(createdAt)
	a.UpdatedAt = parseTime(updatedAt)
	return &a, nil
}

func nullInt(v *int) any {
	if v == nil {
		return nil
	}
	return *v
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

func parseTime(s string) time.Time {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}
	}
	return t
}

// isUniqueViolation detects a UNIQUE constraint failure from both the
// modernc and mattn sqlite drivers (message text is stable across both).
func isUniqueViolation(err error) bool {
	msg := err.Error()
	return strings.Contains(msg, "UNIQUE constraint failed") ||
		strings.Contains(msg, "constraint failed") && strings.Contains(msg, "accounts.username")
}
