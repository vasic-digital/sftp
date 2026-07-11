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
	// DBPath is the SQLite database file path (default data/sftp.db).
	DBPath string `json:"db_path" yaml:"db_path"`
	// UsersConfPath is where sftpsync renders the atmoz users.conf
	// (default data/users.conf).
	UsersConfPath string `json:"users_conf_path" yaml:"users_conf_path"`
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
}

// Default returns the baseline configuration before file/env overrides.
func Default() *Config {
	return &Config{
		Bind:               "127.0.0.1",
		Port:               7722,
		DBPath:             "data/sftp.db",
		UsersConfPath:      "data/users.conf",
		AccessTokenTTL:     15 * time.Minute,
		RefreshTokenTTL:    168 * time.Hour,
		SuperAdminUsername: "admin",
		Version:            "0.1.0-dev",
		LoginRateLimit:     10,
		LoginRateWindow:    time.Minute,
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
	if v := getenv("DB_PATH"); v != "" {
		c.DBPath = v
	}
	if v := getenv("USERS_CONF_PATH"); v != "" {
		c.UsersConfPath = v
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
	if c.DBPath == "" {
		return fmt.Errorf("config: DB path must not be empty")
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
