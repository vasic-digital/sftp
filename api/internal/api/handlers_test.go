package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/config"
	"github.com/vasic-digital/sftp/api/internal/store"
	"github.com/vasic-digital/sftp/api/internal/vault"
)

// testEnv is a fully wired API stack: REAL Gin engine + REAL SQLite DB
// file in a temp dir (no in-memory mock DB, per §11.4.27).
type testEnv struct {
	engine  *gin.Engine
	server  *Server
	cfg     *config.Config
	dir     string
	usrConf string
}

const (
	testJWTSecret       = "0123456789abcdef0123456789abcdef" // 32 chars, test-only
	testAdminUsername   = "admin"
	testAdminPassword   = "Sup3r-Adm1n-Pass!"
	testAdminBcryptHint = "not-a-real-hash" // placeholder for negative tests
)

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	gin.SetMode(gin.TestMode)
	dir := t.TempDir()
	usrConf := filepath.Join(dir, "users.conf")

	cfg := config.Default()
	cfg.TestMode = true
	cfg.DBPath = filepath.Join(dir, "sftp.db")
	cfg.UsersConfPath = usrConf
	cfg.JWTSecret = testJWTSecret
	cfg.SuperAdminUsername = testAdminUsername
	cfg.LoginRateLimit = 0 // disabled per-test unless a test opts in

	st, err := store.Open(t.Context(), "sqlite", cfg.DBPath)
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })

	authSvc, err := authn.NewService(cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	if err != nil {
		t.Fatalf("authn service: %v", err)
	}
	vl, err := vault.New(vault.VaultConfig{DataDir: filepath.Join(dir, "vault")})
	if err != nil {
		t.Fatalf("vault: %v", err)
	}
	srv := NewServer(cfg, st, authSvc, nil, vl) // nil firebase client in tests
	return &testEnv{engine: srv.Engine(), server: srv, cfg: cfg, dir: dir, usrConf: usrConf}
}

// seedAdmin seeds the super-admin with a bcrypt hash of testAdminPassword.
func (e *testEnv) seedAdmin(t *testing.T) {
	t.Helper()
	hash, err := authn.HashPassword(testAdminPassword)
	if err != nil {
		t.Fatalf("hash admin password: %v", err)
	}
	if _, err := e.server.store.SeedAdmin(t.Context(), e.cfg.SuperAdminUsername, hash); err != nil {
		t.Fatalf("seed admin: %v", err)
	}
}

// do performs one HTTP request against the in-process engine.
func (e *testEnv) do(t *testing.T, method, path string, body any, bearer string) (*httptest.ResponseRecorder, []byte) {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		reader = bytes.NewReader(raw)
	} else {
		reader = bytes.NewReader(nil)
	}
	req := httptest.NewRequest(method, path, reader)
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	rec := httptest.NewRecorder()
	e.engine.ServeHTTP(rec, req)
	return rec, rec.Body.Bytes()
}

// login authenticates as the seeded admin and returns the token pair JSON
// and the refresh token extracted from the HttpOnly Set-Cookie header.
func (e *testEnv) login(t *testing.T) (map[string]any, string) {
	t.Helper()
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/login", map[string]any{
		"username": testAdminUsername,
		"password": testAdminPassword,
	}, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("login status = %d, body = %s", rec.Code, raw)
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		t.Fatalf("unmarshal login response: %v", err)
	}
	refresh := refreshTokenFromCookie(t, rec)
	return out, refresh
}

// refreshTokenFromCookie extracts the refresh token from the Set-Cookie
// header of the response recorder.
func refreshTokenFromCookie(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	for _, c := range rec.Result().Cookies() {
		if c.Name == refreshTokenCookie {
			return c.Value
		}
	}
	return ""
}

func TestHealthEndpoint(t *testing.T) {
	e := newTestEnv(t)
	rec, raw := e.do(t, http.MethodGet, "/api/v1/health", nil, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("health status = %d", rec.Code)
	}
	var body map[string]any
	if err := json.Unmarshal(raw, &body); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if body["status"] != "ok" {
		t.Fatalf("health body = %s", raw)
	}
}

func TestLoginWrongPasswordRejected(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/login", map[string]any{
		"username": testAdminUsername,
		"password": "wrong-password",
	}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401; body = %s", rec.Code, raw)
	}
	var body map[string]any
	_ = json.Unmarshal(raw, &body)
	if body["code"] != codeInvalidCredential {
		t.Fatalf("error code = %v, want %s", body["code"], codeInvalidCredential)
	}
	// The error must not leak WHICH credential part failed.
	if msg, _ := body["error"].(string); strings.Contains(strings.ToLower(msg), "password") && !strings.Contains(msg, "username") {
		t.Fatalf("error leaks credential detail: %q", msg)
	}
}

func TestLoginUnknownUserSameResponse(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/login", map[string]any{
		"username": "nobody",
		"password": "whatever",
	}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(raw, &body)
	if body["code"] != codeInvalidCredential {
		t.Fatalf("unknown user must yield the same code as wrong password, got %v", body["code"])
	}
}

func TestSecuredEndpointsRequireToken(t *testing.T) {
	e := newTestEnv(t)
	for _, tc := range []struct{ method, path string }{
		{http.MethodGet, "/api/v1/accounts"},
		{http.MethodPost, "/api/v1/accounts"},
		{http.MethodGet, "/api/v1/auth/me"},
		{http.MethodPost, "/api/v1/auth/logout"},
		{http.MethodPost, "/api/v1/sync"},
	} {
		rec, _ := e.do(t, tc.method, tc.path, nil, "")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s without token: status = %d, want 401", tc.method, tc.path, rec.Code)
		}
		rec, _ = e.do(t, tc.method, tc.path, nil, "not-a-real-token")
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s with garbage token: status = %d, want 401", tc.method, tc.path, rec.Code)
		}
	}
}

func TestFullAccountJourney(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, refresh := e.login(t)
	access, _ := tokens["access_token"].(string)
	if access == "" || refresh == "" {
		t.Fatalf("login response missing tokens: %v", tokens)
	}
	if tokens["token_type"] != "Bearer" {
		t.Fatalf("token_type = %v", tokens["token_type"])
	}

	// /auth/me reflects the token identity.
	rec, raw := e.do(t, http.MethodGet, "/api/v1/auth/me", nil, access)
	if rec.Code != http.StatusOK || !strings.Contains(string(raw), testAdminUsername) {
		t.Fatalf("me: status = %d, body = %s", rec.Code, raw)
	}

	// Refresh yields a new usable pair.
	rec, raw = e.do(t, http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refresh_token": refresh}, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("refresh: status = %d, body = %s", rec.Code, raw)
	}
	var refreshed map[string]any
	_ = json.Unmarshal(raw, &refreshed)
	if refreshed["access_token"] == "" {
		t.Fatal("refresh response missing access_token")
	}

	// Create read-only account (default permission when omitted).
	rec, raw = e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username": "alice",
		"password": "Al1ce-Pass!",
	}, access)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create alice: status = %d, body = %s", rec.Code, raw)
	}
	var alice map[string]any
	_ = json.Unmarshal(raw, &alice)
	if alice["permission"] != "read_only" {
		t.Fatalf("default permission = %v, want read_only", alice["permission"])
	}
	if alice["home_dir"] != "/alice" {
		t.Fatalf("default home = %v, want /alice", alice["home_dir"])
	}
	if _, leaked := alice["password"]; leaked {
		t.Fatal("response leaks password field")
	}
	if _, leaked := alice["password_hash"]; leaked {
		t.Fatal("response leaks password_hash field")
	}

	// Public WITHOUT acknowledgement → 422.
	rec, raw = e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username":   "pubacct",
		"password":   "Publ1c!",
		"permission": "public",
	}, access)
	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("public without ack: status = %d, want 422; body = %s", rec.Code, raw)
	}
	var perr map[string]any
	_ = json.Unmarshal(raw, &perr)
	if perr["code"] != codePublicNotAcked {
		t.Fatalf("public-without-ack code = %v, want %s", perr["code"], codePublicNotAcked)
	}

	// Public WITH acknowledgement → 201.
	rec, raw = e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username":            "pubacct",
		"password":            "Publ1c!",
		"permission":          "public",
		"public_acknowledged": true,
	}, access)
	if rec.Code != http.StatusCreated {
		t.Fatalf("public with ack: status = %d, body = %s", rec.Code, raw)
	}

	// Duplicate username → 409.
	rec, _ = e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username": "alice",
		"password": "An0ther!",
	}, access)
	if rec.Code != http.StatusConflict {
		t.Fatalf("duplicate create: status = %d, want 409", rec.Code)
	}

	// Invalid username → 400 validation.
	rec, _ = e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username": "Bad-Name",
		"password": "Whatever1",
	}, access)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("invalid username: status = %d, want 400", rec.Code)
	}

	// List shows both accounts, ordered.
	rec, raw = e.do(t, http.MethodGet, "/api/v1/accounts", nil, access)
	if rec.Code != http.StatusOK {
		t.Fatalf("list: status = %d", rec.Code)
	}
	var list struct {
		Accounts []map[string]any `json:"accounts"`
		Count    int              `json:"count"`
	}
	if err := json.Unmarshal(raw, &list); err != nil {
		t.Fatalf("unmarshal list: %v", err)
	}
	if list.Count != 2 || list.Accounts[0]["username"] != "alice" || list.Accounts[1]["username"] != "pubacct" {
		t.Fatalf("list = %s", raw)
	}
	for _, a := range list.Accounts {
		if _, leaked := a["password_hash"]; leaked {
			t.Fatalf("list entry leaks password_hash: %v", a)
		}
	}

	// Get single account.
	rec, raw = e.do(t, http.MethodGet, "/api/v1/accounts/alice", nil, access)
	if rec.Code != http.StatusOK || !strings.Contains(string(raw), `"username":"alice"`) {
		t.Fatalf("get alice: status = %d, body = %s", rec.Code, raw)
	}

	// Update alice → read_write + new password.
	rec, raw = e.do(t, http.MethodPut, "/api/v1/accounts/alice", map[string]any{
		"permission": "read_write",
		"password":   "N3w-Pass!",
	}, access)
	if rec.Code != http.StatusOK {
		t.Fatalf("update alice: status = %d, body = %s", rec.Code, raw)
	}
	var updated map[string]any
	_ = json.Unmarshal(raw, &updated)
	if updated["permission"] != "read_write" {
		t.Fatalf("updated permission = %v", updated["permission"])
	}

	// Sync renders users.conf; we then read the REAL file and assert lines.
	rec, raw = e.do(t, http.MethodPost, "/api/v1/sync", nil, access)
	if rec.Code != http.StatusOK {
		t.Fatalf("sync: status = %d, body = %s", rec.Code, raw)
	}
	var syncRes map[string]any
	_ = json.Unmarshal(raw, &syncRes)
	if n, _ := syncRes["rendered_accounts"].(float64); n != 2 {
		t.Fatalf("rendered_accounts = %v, want 2", syncRes["rendered_accounts"])
	}
	content, err := os.ReadFile(e.usrConf)
	if err != nil {
		t.Fatalf("read users.conf: %v", err)
	}
	lines := strings.Split(strings.TrimSpace(string(content)), "\n")
	if len(lines) != 2 {
		t.Fatalf("users.conf lines = %d, want 2:\n%s", len(lines), content)
	}
	// alice: read_write, sha512-crypt hash, :e at position 3 (encrypted-password flag), auto uid 1001.
	if !strings.HasPrefix(lines[0], "alice:$6$") {
		t.Fatalf("alice line malformed: %q", lines[0])
	}
	parts := strings.Split(lines[0], ":")
	if len(parts) != 6 || !strings.HasPrefix(parts[1], "$6$") || parts[2] != "e" || parts[3] != "1001" || parts[4] != "1001" || parts[5] != "/alice" {
		t.Fatalf("alice line fields wrong: %q", lines[0])
	}
	// pubacct: public '*' password + :e at position 3.
	if lines[1] != "pubacct:*:e:1002:1002:/pubacct" {
		t.Fatalf("pubacct line = %q, want pubacct:*:e:1002:1002:/pubacct", lines[1])
	}

	// Delete alice → then 404 on get.
	rec, _ = e.do(t, http.MethodDelete, "/api/v1/accounts/alice", nil, access)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("delete alice: status = %d, want 204", rec.Code)
	}
	rec, _ = e.do(t, http.MethodGet, "/api/v1/accounts/alice", nil, access)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("get deleted alice: status = %d, want 404", rec.Code)
	}
	rec, _ = e.do(t, http.MethodDelete, "/api/v1/accounts/alice", nil, access)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("re-delete alice: status = %d, want 404", rec.Code)
	}
}

func TestRefreshRejectsAccessToken(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, _ := e.login(t)
	access, _ := tokens["access_token"].(string)
	rec, _ := e.do(t, http.MethodPost, "/api/v1/auth/refresh", map[string]any{"refresh_token": access}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("access-as-refresh: status = %d, want 401", rec.Code)
	}
}

func TestRateLimitOnAuthEndpoints(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	// Rebuild the engine with a small limit (limit is read at middleware
	// construction time).
	e.server.cfg.LoginRateLimit = 3
	e.server.cfg.LoginRateWindow = time.Minute
	e.engine = e.server.Engine()

	statuses := []int{}
	for i := 0; i < 5; i++ {
		rec, _ := e.do(t, http.MethodPost, "/api/v1/auth/login", map[string]any{
			"username": testAdminUsername,
			"password": testAdminPassword,
		}, "")
		statuses = append(statuses, rec.Code)
	}
	if statuses[0] != http.StatusOK || statuses[1] != http.StatusOK || statuses[2] != http.StatusOK {
		t.Fatalf("first 3 requests must pass, got %v", statuses)
	}
	if statuses[3] != http.StatusTooManyRequests || statuses[4] != http.StatusTooManyRequests {
		t.Fatalf("requests 4-5 must be 429, got %v", statuses)
	}
}

func TestRequestIDHeaderPresent(t *testing.T) {
	e := newTestEnv(t)
	rec, _ := e.do(t, http.MethodGet, "/api/v1/health", nil, "")
	if rec.Header().Get("X-Request-ID") == "" {
		t.Fatal("X-Request-ID header missing — requestid middleware not wired")
	}
}

func TestMalformedJSONRejected(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	req := httptest.NewRequest(http.MethodPost, "/api/v1/auth/login", strings.NewReader("{not json"))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	e.engine.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("malformed JSON: status = %d, want 400", rec.Code)
	}
}

func TestPanicRecoveryReturns500(t *testing.T) {
	// The recovery middleware must convert a panic into a 500 JSON
	// response rather than crashing the server. We register a panicking
	// route on a throwaway engine built the same way.
	gin.SetMode(gin.TestMode)
	e := newTestEnv(t)
	engine := e.engine
	engine.GET("/api/v1/panic", func(c *gin.Context) { panic("boom") })
	req := httptest.NewRequest(http.MethodGet, "/api/v1/panic", nil)
	rec := httptest.NewRecorder()
	engine.ServeHTTP(rec, req)
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("panic route: status = %d, want 500", rec.Code)
	}
}

func TestMain_StoreReopenPersists(t *testing.T) {
	// The integration env uses a REAL DB file; closing and reopening it
	// must preserve accounts (proves migrations + persistence are real).
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, _ := e.login(t)
	access, _ := tokens["access_token"].(string)
	rec, _ := e.do(t, http.MethodPost, "/api/v1/accounts", map[string]any{
		"username": "persist", "password": "P3rsist!"}, access)
	if rec.Code != http.StatusCreated {
		t.Fatalf("create: %d", rec.Code)
	}
	_ = e.server.store.Close()
	st, err := store.Open(t.Context(), "sqlite", e.cfg.DBPath)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer func() { _ = st.Close() }()
	a, err := st.GetAccount(t.Context(), "persist")
	if err != nil {
		t.Fatalf("account lost after reopen: %v", err)
	}
	if a.Permission != "read_only" {
		t.Fatalf("persisted permission = %q", a.Permission)
	}
}

func TestCryptVaultLifecycle(t *testing.T) {
	vl, err := vault.New(vault.VaultConfig{DataDir: filepath.Join(t.TempDir(), "vault")})
	if err != nil {
		t.Fatalf("new vault: %v", err)
	}
	v := newCryptVault(vl)
	if err := v.set("alice", "password1"); err != nil {
		t.Fatalf("set: %v", err)
	}
	h := v.get("alice")
	if !strings.HasPrefix(h, "$6$") {
		t.Fatalf("vault hash = %q", h)
	}
	v.delete("alice")
	if v.get("alice") != "" {
		t.Fatal("vault entry survived delete")
	}
}

func TestNoPasswordInAnyResponse(t *testing.T) {
	// Sweep: every response from the account + auth endpoints must NOT
	// contain the plaintext password or a bcrypt hash marker.
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, _ := e.login(t)
	access, _ := tokens["access_token"].(string)

	sweep := []struct {
		method, path string
		body         any
	}{
		{http.MethodPost, "/api/v1/accounts", map[string]any{"username": "sweep", "password": "Sw33p-Pass!"}},
		{http.MethodGet, "/api/v1/accounts", nil},
		{http.MethodGet, "/api/v1/accounts/sweep", nil},
		{http.MethodPut, "/api/v1/accounts/sweep", map[string]any{"permission": "read_write", "password": "Sw33p-Pass!"}},
	}
	for _, s := range sweep {
		rec, raw := e.do(t, s.method, s.path, s.body, access)
		if rec.Code >= 300 {
			t.Fatalf("%s %s: status = %d, body = %s", s.method, s.path, rec.Code, raw)
		}
		body := string(raw)
		if strings.Contains(body, "Sw33p-Pass!") || strings.Contains(body, "$2a$") || strings.Contains(body, "$2b$") || strings.Contains(body, "$6$") {
			t.Fatalf("%s %s response leaks credential material: %s", s.method, s.path, body)
		}
	}
	_ = fmt.Sprintf // keep import used if assertions change
}

func TestLogoutRequiresAuth(t *testing.T) {
	e := newTestEnv(t)
	// POST without bearer token → 401.
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/logout", map[string]any{
		"refresh_token": "anything",
	}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("logout without token: status = %d, want 401; body = %s", rec.Code, raw)
	}
}

func TestLogoutInvalidatesRefreshToken(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, refresh := e.login(t)
	access, _ := tokens["access_token"].(string)

	// Step 1: refresh still works before logout.
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/refresh", map[string]any{
		"refresh_token": refresh,
	}, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("refresh before logout: status = %d, want 200; body = %s", rec.Code, raw)
	}
	// Extract the new refresh token from the HttpOnly cookie (refresh rotation).
	newRefreshBefore := refreshTokenFromCookie(t, rec)

	// Step 2: logout with the original refresh token (authenticated).
	rec, raw = e.do(t, http.MethodPost, "/api/v1/auth/logout", map[string]any{
		"refresh_token": refresh,
	}, access)
	if rec.Code != http.StatusOK {
		t.Fatalf("logout: status = %d, want 200; body = %s", rec.Code, raw)
	}

	// Step 3: the revoked refresh token can no longer be used.
	rec, raw = e.do(t, http.MethodPost, "/api/v1/auth/refresh", map[string]any{
		"refresh_token": refresh,
	}, "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("refresh after logout: status = %d, want 401; body = %s", rec.Code, raw)
	}

	// Step 4: the NEW refresh token from step 1 (not revoked) still works.
	if newRefreshBefore != "" {
		rec, raw = e.do(t, http.MethodPost, "/api/v1/auth/refresh", map[string]any{
			"refresh_token": newRefreshBefore,
		}, "")
		if rec.Code != http.StatusOK {
			t.Fatalf("refresh with un-revoked new token: status = %d, want 200; body = %s", rec.Code, raw)
		}
	}
}

func TestLogoutEmptyRefreshTokenRejected(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, _ := e.login(t)
	access, _ := tokens["access_token"].(string)

	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/logout", map[string]any{
		"refresh_token": "",
	}, access)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("logout with empty token: status = %d, want 400; body = %s", rec.Code, raw)
	}
}

func TestLogoutWithAccessTokenRejected(t *testing.T) {
	e := newTestEnv(t)
	e.seedAdmin(t)
	tokens, _ := e.login(t)
	access, _ := tokens["access_token"].(string)

	// An access token cannot be used as a refresh_token for revocation.
	rec, raw := e.do(t, http.MethodPost, "/api/v1/auth/logout", map[string]any{
		"refresh_token": access,
	}, access)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("logout with access token as refresh: status = %d, want 401; body = %s", rec.Code, raw)
	}
}
