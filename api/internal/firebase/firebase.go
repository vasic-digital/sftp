// Package firebase wires the Firebase Admin SDK as an OPTIONAL subsystem
// of the SFTP Enterprise management API (ATM-007).
//
// The subsystem follows a strict graceful-degrade contract:
//
//   - FIREBASE_ENABLED=false (the default) → the client is inert, every
//     hook is a safe no-op, and the API starts normally. The startup path
//     logs exactly "firebase: disabled".
//   - FIREBASE_ENABLED=true but misconfigured (missing project id, missing
//     or unreadable/invalid service-account file) → New returns an error
//     and the API FAILS FAST with a clear message (§11.4.6 — no guessing,
//     no silent half-enabled state).
//   - FIREBASE_ENABLED=true and properly configured → the Admin SDK is
//     initialized from the operator-provided service-account JSON whose
//     path comes from FIREBASE_SERVICE_ACCOUNT_PATH (git-ignored,
//     §11.4.10 — the file itself is NEVER committed).
//
// The Admin SDK for Go has no Crashlytics/Analytics/Performance client:
// those surfaces are exposed here as honest no-op-safe hooks that log a
// single line explaining the limitation instead of pretending to record
// telemetry (§11.4.6).
package firebase

import (
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"strings"

	fb "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"
)

// Options carries the resolved Firebase runtime configuration.
type Options struct {
	// Enabled gates the whole subsystem (FIREBASE_ENABLED).
	Enabled bool
	// ProjectID is the Firebase project id (FIREBASE_PROJECT_ID).
	ProjectID string
	// ServiceAccountPath is the path to the operator-provided service
	// account JSON (FIREBASE_SERVICE_ACCOUNT_PATH). The file is
	// git-ignored and MUST never be committed (§11.4.10).
	ServiceAccountPath string
	// Logger receives the honest status lines. Nil → log.Default().
	Logger *log.Logger
}

// Client is the Firebase subsystem handle. It is always safe to use:
// when inactive every method is a no-op that logs honestly.
type Client struct {
	opts   Options
	log    *log.Logger
	app    *fb.App
	auth   *auth.Client
	active bool
}

// New builds the client. When opts.Enabled is false the returned client
// is inert and err is nil — the API continues without Firebase. When
// enabled, any configuration or initialization defect is a hard error
// (fail fast, §11.4.6).
func New(ctx context.Context, opts Options) (*Client, error) {
	logger := opts.Logger
	if logger == nil {
		logger = log.Default()
	}
	c := &Client{opts: opts, log: logger}

	if !opts.Enabled {
		logger.Printf("firebase: disabled")
		return c, nil
	}

	if strings.TrimSpace(opts.ProjectID) == "" {
		return nil, errors.New("firebase: FIREBASE_ENABLED=true but FIREBASE_PROJECT_ID is empty")
	}
	if strings.TrimSpace(opts.ServiceAccountPath) == "" {
		return nil, errors.New("firebase: FIREBASE_ENABLED=true but FIREBASE_SERVICE_ACCOUNT_PATH is empty")
	}
	info, err := os.Stat(opts.ServiceAccountPath)
	if err != nil {
		return nil, fmt.Errorf("firebase: service account file not accessible at %q: %w", opts.ServiceAccountPath, err)
	}
	if info.IsDir() {
		return nil, fmt.Errorf("firebase: service account path %q is a directory, expected a JSON file", opts.ServiceAccountPath)
	}

	app, err := fb.NewApp(ctx,
		&fb.Config{ProjectID: opts.ProjectID},
		option.WithCredentialsFile(opts.ServiceAccountPath),
	)
	if err != nil {
		return nil, fmt.Errorf("firebase: admin SDK init failed (check the service account JSON at %q): %v", opts.ServiceAccountPath, err)
	}

	authClient, err := app.Auth(ctx)
	if err != nil {
		return nil, fmt.Errorf("firebase: auth client init failed: %w", err)
	}

	c.app = app
	c.auth = authClient
	c.active = true
	logger.Printf("firebase: enabled (project %s)", opts.ProjectID)
	return c, nil
}

// Active reports whether the Admin SDK was actually initialized.
func (c *Client) Active() bool { return c.active }

// Verify performs a real connectivity + credentials round-trip against
// the Identity Toolkit backend. A successful probe returns nil; the
// expected "user not found" answer for the throwaway probe address ALSO
// returns nil because it proves the credentials were accepted and the
// backend responded (§11.4.6 — a network-reachable, authenticated 404 is
// positive evidence of connectivity). Any other error is returned.
//
// Verify is NOT called from New: it requires the Identity Toolkit API to
// be enabled on the project, and operators may enable Firebase for other
// surfaces first. It is exposed for health endpoints and operator checks.
func (c *Client) Verify(ctx context.Context) error {
	if !c.active {
		return errors.New("firebase: verify called on a disabled client")
	}
	_, err := c.auth.GetUserByEmail(ctx, "firebase-connectivity-probe@invalid.invalid")
	if err == nil {
		// The probe address must never resolve to a real user; if it ever
		// does, that is itself a finding worth surfacing.
		return errors.New("firebase: connectivity probe unexpectedly resolved to a real user")
	}
	if auth.IsUserNotFound(err) {
		return nil
	}
	return fmt.Errorf("firebase: connectivity probe failed: %w", err)
}

// RecordCrash is the Crashlytics hook. The Go Admin SDK exposes no
// Crashlytics client, so when active this logs that the event was
// received but not forwarded; when disabled it logs the disabled state.
// It never errors — telemetry must never break the request path.
func (c *Client) RecordCrash(component, message string) {
	c.telemetryStub("crashlytics", component, message)
}

// RecordEvent is the Analytics hook (same contract as RecordCrash).
func (c *Client) RecordEvent(component, name string) {
	c.telemetryStub("analytics", component, name)
}

// RecordTrace is the Performance Monitoring hook (same contract).
func (c *Client) RecordTrace(component, name string) {
	c.telemetryStub("performance", component, name)
}

func (c *Client) telemetryStub(surface, component, detail string) {
	if !c.active {
		c.log.Printf("firebase: %s hook ignored (firebase: disabled) component=%s", surface, component)
		return
	}
	// Honest limitation: the Admin SDK for Go has no Crashlytics /
	// Analytics / Performance ingestion API — those are client-side
	// (mobile/web SDK) surfaces. We log, never bluff (§11.4.6).
	c.log.Printf("firebase: %s hook received component=%s detail=%s (note: Go Admin SDK has no %s ingestion API; event logged only)",
		surface, component, detail, surface)
}
