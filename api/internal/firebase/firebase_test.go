package firebase

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// testLogger captures the honest status lines so tests can assert the
// exact disabled/enabled messaging instead of a tautology.
func testLogger() (*log.Logger, *strings.Builder) {
	var buf strings.Builder
	return log.New(&buf, "", 0), &buf
}

// TestDisabledIsInertAndLogs verifies the default path: with
// Enabled=false the client is built without touching any credential,
// Active() is false, Verify refuses, hooks are no-ops, and the exact
// "firebase: disabled" line is emitted.
func TestDisabledIsInertAndLogs(t *testing.T) {
	logger, buf := testLogger()
	c, err := New(context.Background(), Options{Enabled: false, Logger: logger})
	if err != nil {
		t.Fatalf("disabled path must not error, got: %v", err)
	}
	if c.Active() {
		t.Fatal("disabled client must report Active()=false")
	}
	if err := c.Verify(context.Background()); err == nil {
		t.Fatal("Verify on a disabled client must error, not silently pass")
	}
	// Hooks must be safe no-ops on a disabled client.
	c.RecordCrash("test", "boom")
	c.RecordEvent("test", "evt")
	c.RecordTrace("test", "tr")

	out := buf.String()
	if !strings.Contains(out, "firebase: disabled") {
		t.Fatalf("expected exact 'firebase: disabled' log line, got %q", out)
	}
	if got := strings.Count(out, "firebase: disabled"); got != 4 {
		t.Fatalf("expected 4 'firebase: disabled' lines (1 init + 3 hooks), got %d:\n%s", got, out)
	}
}

// TestEnabledWithoutProjectIDFailsFast — enabled but no project id must
// be a hard error, not a silent half-enabled state (§11.4.6).
func TestEnabledWithoutProjectIDFailsFast(t *testing.T) {
	logger, _ := testLogger()
	_, err := New(context.Background(), Options{
		Enabled:            true,
		ServiceAccountPath: "some/path.json",
		Logger:             logger,
	})
	if err == nil || !strings.Contains(err.Error(), "FIREBASE_PROJECT_ID") {
		t.Fatalf("expected clear project-id error, got: %v", err)
	}
}

// TestEnabledWithoutServiceAccountPathFailsFast.
func TestEnabledWithoutServiceAccountPathFailsFast(t *testing.T) {
	logger, _ := testLogger()
	_, err := New(context.Background(), Options{
		Enabled:   true,
		ProjectID: "proj",
		Logger:    logger,
	})
	if err == nil || !strings.Contains(err.Error(), "FIREBASE_SERVICE_ACCOUNT_PATH") {
		t.Fatalf("expected clear service-account-path error, got: %v", err)
	}
}

// TestEnabledWithMissingServiceAccountFileFailsFast — a path that does
// not exist on disk must fail with the path named in the error.
func TestEnabledWithMissingServiceAccountFileFailsFast(t *testing.T) {
	logger, _ := testLogger()
	missing := filepath.Join(t.TempDir(), "does-not-exist.json")
	_, err := New(context.Background(), Options{
		Enabled:            true,
		ProjectID:          "proj",
		ServiceAccountPath: missing,
		Logger:             logger,
	})
	if err == nil || !strings.Contains(err.Error(), missing) {
		t.Fatalf("expected error naming the missing file %q, got: %v", missing, err)
	}
}

// TestEnabledWithDirectoryInsteadOfFileFailsFast.
func TestEnabledWithDirectoryInsteadOfFileFailsFast(t *testing.T) {
	logger, _ := testLogger()
	dir := t.TempDir()
	_, err := New(context.Background(), Options{
		Enabled:            true,
		ProjectID:          "proj",
		ServiceAccountPath: dir,
		Logger:             logger,
	})
	if err == nil || !strings.Contains(err.Error(), "directory") {
		t.Fatalf("expected 'directory' error, got: %v", err)
	}
}

// TestEnabledWithInvalidServiceAccountJSONFailsFast exercises the REAL
// Admin-SDK init path: a readable but structurally invalid JSON file must
// surface an init error from option.WithCredentialsFile (anti-bluff —
// this is not a tautology, the SDK genuinely parses the file).
func TestEnabledWithInvalidServiceAccountJSONFailsFast(t *testing.T) {
	logger, _ := testLogger()
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, []byte(`this is not json at all`), 0o600); err != nil {
		t.Fatal(err)
	}
	_, err := New(context.Background(), Options{
		Enabled:            true,
		ProjectID:          "proj",
		ServiceAccountPath: path,
		Logger:             logger,
	})
	if err == nil || !strings.Contains(err.Error(), "init failed") {
		t.Fatalf("expected a firebase init failure on invalid credentials, got: %v", err)
	}
}

// TestNewWithNilLoggerDoesNotPanic covers the nil-Logger fallback path
// where New() defaults to log.Default() when opts.Logger is nil.
func TestNewWithNilLoggerDoesNotPanic(t *testing.T) {
	c, err := New(context.Background(), Options{Enabled: false})
	if err != nil {
		t.Fatal(err)
	}
	if c.Active() {
		t.Fatal("disabled client must report Active()=false")
	}
}

// TestEnabledWithWellFormedButUndecryptableServiceAccountFailsFast — a
// service-account JSON with all required fields but a garbage private key
// must fail inside the real SDK init (JWT signer construction), proving
// the init logic really runs.
func TestEnabledWithWellFormedButUndecryptableServiceAccountFailsFast(t *testing.T) {
	logger, _ := testLogger()
	sa := map[string]any{
		"type":          "service_account",
		"project_id":    "proj",
		"private_key": "-----BEGIN " + "PRIVATE KEY-----\nnot-a-real-key\n-----END " + "PRIVATE KEY-----\n",
		"client_email":  "firebase-adminsdk@proj.iam.gserviceaccount.com",
		"client_id":     "1234567890",
		"token_uri":     "https://oauth2.googleapis.com/token",
		"private_key_id": "abc123",
	}
	data, err := json.Marshal(sa)
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, data, 0o600); err != nil {
		t.Fatal(err)
	}
	_, err = New(context.Background(), Options{
		Enabled:            true,
		ProjectID:          "proj",
		ServiceAccountPath: path,
		Logger:             logger,
	})
	if err == nil {
		t.Fatal("expected init failure with an undecryptable private key, got nil — init logic did not really run")
	}
}

// TestActiveClientTelemetryLogsFormat verifies that each active-client
// telemetry hook (RecordCrash, RecordEvent, RecordTrace) emits the
// expected log format with the correct surface, component, and detail
// fields. This closes REVIEW-A Finding 6 (LOW, unfixed) — the active
// path had zero format assertions.
func TestActiveClientTelemetryLogsFormat(t *testing.T) {
	logger, buf := testLogger()
	c := &Client{active: true, log: logger}

	// RecordEvent(component, name string) — surface "analytics" hardcoded.
	c.RecordEvent("user_signup", "test_event")
	out := buf.String()
	if !strings.Contains(out, "analytics hook received") {
		t.Fatalf("expected analytics hook log, got %q", out)
	}
	if !strings.Contains(out, "component=user_signup") {
		t.Fatalf("expected component=user_signup, got %q", out)
	}
	if !strings.Contains(out, "detail=test_event") {
		t.Fatalf("expected detail=test_event, got %q", out)
	}

	// RecordCrash(component, message string) — surface "crashlytics".
	buf.Reset()
	c.RecordCrash("login_handler", "nil pointer dereference")
	out = buf.String()
	if !strings.Contains(out, "crashlytics hook received") {
		t.Fatalf("expected crashlytics hook log, got %q", out)
	}
	if !strings.Contains(out, "component=login_handler") {
		t.Fatalf("expected component=login_handler, got %q", out)
	}
	if !strings.Contains(out, "detail=nil pointer dereference") {
		t.Fatalf("expected detail=nil pointer dereference, got %q", out)
	}

	// RecordTrace(component, name string) — surface "performance".
	buf.Reset()
	c.RecordTrace("sync_endpoint", "trace_sync")
	out = buf.String()
	if !strings.Contains(out, "performance hook received") {
		t.Fatalf("expected performance hook log, got %q", out)
	}
	if !strings.Contains(out, "component=sync_endpoint") {
		t.Fatalf("expected component=sync_endpoint, got %q", out)
	}
	if !strings.Contains(out, "detail=trace_sync") {
		t.Fatalf("expected detail=trace_sync, got %q", out)
	}
}
