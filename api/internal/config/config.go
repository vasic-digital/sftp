// Package config loads the SFTP Enterprise API runtime configuration.
//
// Precedence: built-in defaults < optional config file (API_CONFIG, parsed
// via digital.vasic.config LoadFile, JSON or YAML depending on extension)
// < environment variables. Env always wins over file values (project rule:
// ".env holds host/runtime config").
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"gopkg.in/yaml.v3"

	cfglib "digital.vasic.config/pkg/config"
)

// Config is the fully resolved API runtime configuration.
type Config struct {
	// Bind is the interface the HTTP server binds to (default 127.0.0.1).
	Bind string `json:"bind" yaml:"bind"`
	// Port is the TCP port the HTTP server listens on (default 7722).
	Port int `json:"port" yaml:"port"`
	// DBDriver selects the database backend: "sqlite" (default) or "postgres".
	DBDriver string `json:"db_driver" yaml:"db_driver"`
	// DBPath is the SQLite database file path (default data/sftp.db).
	DBPath string `json:"db_path" yaml:"db_path"`
	// DBDSN is the PostgreSQL connection URL (postgres://...). When set and
	// DBDriver is "postgres", DBPath is ignored.
	DBDSN string `json:"db_dsn" yaml:"db_dsn"`
	// UsersConfPath is where sftpsync renders the atmoz users.conf
	// (default data/users.conf).
	UsersConfPath string `json:"users_conf_path" yaml:"users_conf_path"`
	// SFTPDataDir is the host-side path mounted at /home inside the SFTP
	// container (default data). sftpsync.ProvisionHomeDirs uses this to
	// enforce read_only permissions at the filesystem level (FTP-021).
	// When empty, home-directory provisioning is skipped (the API does
	// not have filesystem access to the SFTP data directory).
	SFTPDataDir string `json:"sftp_data_dir" yaml:"sftp_data_dir"`
	// JWTSecret signs access + refresh tokens. REQUIRED outside test runs.
	JWTSecret string `json:"jwt_secret" yaml:"jwt_secret"`
	// AccessTokenTTL is the access token lifetime (default 15m).
	AccessTokenTTL time.Duration `json:"access_token_ttl" yaml:"access_token_ttl"`
	// RefreshTokenTTL is the refresh token lifetime (default 168h).
	RefreshTokenTTL time.Duration `json:"refresh_token_ttl" yaml:"refresh_token_ttl"`
	// SuperAdminUsername seeds the super-admin account (default admin).
	SuperAdminUsername string `json:"superadmin_username" yaml:"superadmin_username"`
	// SuperAdminPassword seeds the super-admin password. REQUIRED outside
	// test runs — there is intentionally NO insecure default.
	SuperAdminPassword string `json:"-" yaml:"-"`
	// Version is reported by /api/v1/health.
	Version string `json:"version" yaml:"version"`
	// TestMode relaxes the required-secret checks (tests set secrets
	// explicitly and use temp dirs). It is only ever set from the
	// API_TEST_MODE env var, never from a config file.
	TestMode bool `json:"-" yaml:"-"`
	// LoginRateLimit caps auth-endpoint requests per window per IP.
	LoginRateLimit int `json:"login_rate_limit" yaml:"login_rate_limit"`
	// LoginRateWindow is the auth-endpoint rate-limit window.
	LoginRateWindow time.Duration `json:"login_rate_window" yaml:"login_rate_window"`
	// FirebaseEnabled gates the optional Firebase subsystem (default false).
	FirebaseEnabled bool `json:"firebase_enabled" yaml:"firebase_enabled"`
	// FirebaseProjectID is the Firebase project id (FIREBASE_PROJECT_ID).
	FirebaseProjectID string `json:"firebase_project_id" yaml:"firebase_project_id"`
	// FirebaseServiceAccountPath points at the operator-provided service
	// account JSON (git-ignored, §11.4.10).
	FirebaseServiceAccountPath string `json:"firebase_service_account_path" yaml:"firebase_service_account_path"`
	// VaultDataDir is the filesystem directory where the persistent
	// encrypted vault stores its data blobs (default data/vault).
	VaultDataDir string `json:"vault_data_dir" yaml:"vault_data_dir"`
	// CORSOrigin is the allowed Origin for CORS requests. When empty
	// (default) no CORS headers are emitted — use this when the API and
	// SPA are served from the same origin or behind a reverse proxy.
	CORSOrigin string `json:"cors_origin" yaml:"cors_origin"`
	// ServeWeb enables the embedded web SPA serving. When true, static
	// files from WebDistDir are served and non-API routes fall back to
	// index.html (SPA client-side routing).
	ServeWeb bool `json:"serve_web" yaml:"serve_web"`
	// WebDistDir is the filesystem path to the built SPA distribution
	// directory (default "web/dist").
	WebDistDir string `json:"web_dist_dir" yaml:"web_dist_dir"`
}

// Default returns the baseline configuration before file/env overrides.
func Default() *Config {
	return &Config{
		Bind:               "127.0.0.1",
		Port:               7722,
		DBPath:             "data/sftp.db",
		UsersConfPath:      "data/users.conf",
		SFTPDataDir:        "data",
		AccessTokenTTL:     15 * time.Minute,
		RefreshTokenTTL:    168 * time.Hour,
		SuperAdminUsername: "admin",
		Version:            "0.1.0-dev",
		LoginRateLimit:     10,
		LoginRateWindow:    time.Minute,
		VaultDataDir:       "data/vault",
		WebDistDir:          "web/dist",
	}
}

// Load resolves the configuration: defaults, then the optional file named
// by API_CONFIG (JSON via digital.vasic.config, YAML when the extension is
// .yaml/.yml — LoadFile itself is JSON-only), then environment variables.
// Env always overrides file values.
func Load() (*Config, error) {
	c := Default()

	if path := strings.TrimSpace(os.Getenv("API_CONFIG")); path != "" {
		if err := loadFileInto(path, c); err != nil {
			return nil, fmt.Errorf("config: load API_CONFIG %q: %w", path, err)
		}
	}

	applyEnv(c)
	return c, nil
}

// loadFileInto merges file values into c. digital.vasic.config LoadFile
// handles JSON; YAML files are parsed here because LoadFile is JSON-only
// (verified in config/pkg/config/config.go — it calls json.Unmarshal).
func loadFileInto(path string, c *Config) error {
	switch strings.ToLower(filepath.Ext(path)) {
	case ".yaml", ".yml":
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return yaml.Unmarshal(data, c)
	default:
		return cfglib.LoadFile(path, c)
	}
}

// applyEnv overlays every supported environment variable onto c.
// Only non-empty values override.
func applyEnv(c *Config) {
	if v := getenv("API_BIND"); v != "" {
		c.Bind = v
	}
	if v := getenv("API_PORT"); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil && n > 0 {
			c.Port = n
		}
	}
	if v := getenv("DB_DRIVER"); v != "" {
		c.DBDriver = v
	}
	if v := getenv("DB_PATH"); v != "" {
		c.DBPath = v
	}
	if v := getenv("DB_DSN"); v != "" {
		c.DBDSN = v
	}
	if v := getenv("USERS_CONF_PATH"); v != "" {
		c.UsersConfPath = v
	}
	if v := getenv("SFTP_DATA_DIR"); v != "" {
		c.SFTPDataDir = v
	}
	if v := getenv("JWT_SECRET"); v != "" {
		c.JWTSecret = v
	}
	if v := getenv("ACCESS_TOKEN_TTL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			c.AccessTokenTTL = d
		}
	}
	if v := getenv("REFRESH_TOKEN_TTL"); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			c.RefreshTokenTTL = d
		}
	}
	if v := getenv("SUPERADMIN_USERNAME"); v != "" {
		c.SuperAdminUsername = v
	}
	if v := getenv("SUPERADMIN_PASSWORD"); v != "" {
		c.SuperAdminPassword = v
	}
	if v := getenv("API_VERSION"); v != "" {
		c.Version = v
	}
	if v := getenv("API_TEST_MODE"); v == "1" || v == "true" {
		c.TestMode = true
	}
	if v := getenv("LOGIN_RATE_LIMIT"); v != "" {
		var n int
		if _, err := fmt.Sscanf(v, "%d", &n); err == nil && n > 0 {
			c.LoginRateLimit = n
		}
	}
	if v := getenv("LOGIN_RATE_WINDOW"); v != "" {
		if d, err := time.ParseDuration(v); err == nil && d > 0 {
			c.LoginRateWindow = d
		}
	}
	if v := getenv("FIREBASE_ENABLED"); v == "1" || v == "true" {
		c.FirebaseEnabled = true
	}
	if v := getenv("FIREBASE_PROJECT_ID"); v != "" {
		c.FirebaseProjectID = v
	}
	if v := getenv("FIREBASE_SERVICE_ACCOUNT_PATH"); v != "" {
		c.FirebaseServiceAccountPath = v
	}
	if v := getenv("VAULT_DATA_DIR"); v != "" {
		c.VaultDataDir = v
	}
	if v := getenv("API_CORS_ORIGIN"); v != "" {
		c.CORSOrigin = v
	}
	if v := getenv("SERVE_WEB"); v == "1" || v == "true" {
		c.ServeWeb = true
	}
	if v := getenv("WEB_DIST_DIR"); v != "" {
		c.WebDistDir = v
	}
}

func getenv(key string) string {
	return strings.TrimSpace(os.Getenv(key))
}

// Validate enforces the startup invariants. In non-test mode a JWT secret
// and a super-admin password are mandatory — the API refuses to start with
// an insecure default credential.
func (c *Config) Validate() error {
	if c.Port <= 0 || c.Port > 65535 {
		return fmt.Errorf("config: invalid API port %d", c.Port)
	}
	if c.Bind == "" {
		return fmt.Errorf("config: API bind address must not be empty")
	}
	if c.DBPath == "" && c.DBDSN == "" {
		return fmt.Errorf("config: DB path (SQLite) or DB DSN (PostgreSQL) must be set")
	}
	if c.DBDriver != "" && c.DBDriver != "sqlite" && c.DBDriver != "postgres" {
		return fmt.Errorf("config: DB driver must be sqlite or postgres, got %q", c.DBDriver)
	}
	if c.UsersConfPath == "" {
		return fmt.Errorf("config: users.conf path must not be empty")
	}
	if c.AccessTokenTTL <= 0 {
		return fmt.Errorf("config: access token TTL must be positive")
	}
	if c.RefreshTokenTTL <= c.AccessTokenTTL {
		return fmt.Errorf("config: refresh token TTL must exceed access token TTL")
	}
	if c.SuperAdminUsername == "" {
		return fmt.Errorf("config: super-admin username must not be empty")
	}
	if !c.TestMode {
		if len(c.JWTSecret) < 32 {
			return fmt.Errorf("config: JWT_SECRET is required (min 32 chars); refusing to start with an insecure default")
		}
		if c.SuperAdminPassword == "" {
			return fmt.Errorf("config: SUPERADMIN_PASSWORD is required; refusing to start with an insecure default credential")
		}
	}
	return nil
}

// Addr returns the listen address for the HTTP server.
func (c *Config) Addr() string {
	return fmt.Sprintf("%s:%d", c.Bind, c.Port)
}
