// Package main is the bootstrap entrypoint for the SFTP Enterprise
// management API (ATM-002).
//
// Startup order (each step fails fast with a clear message — no guessing,
// §11.4.6):
//
//  1. config.Load()  — defaults < optional API_CONFIG file < env vars.
//  2. Config.Validate() — refuses to start without JWT_SECRET (>=32 chars)
//     and SUPERADMIN_PASSWORD outside test mode. There is NO insecure
//     default credential (§11.4.10).
//  3. store.Open() — real SQLite file (modernc.org/sqlite, pure Go).
//  4. Seed super-admin — bcrypt-hashed password (cost >= 12) from
//     SUPERADMIN_PASSWORD. SeedAdmin only inserts when the admin row is
//     absent; the plaintext is hashed in memory and never logged.
//  5. authn.NewService — JWT access/refresh issuer.
//  5b. firebase.New — OPTIONAL subsystem (ATM-007): disabled by default
//     (logs "firebase: disabled" and continues); when FIREBASE_ENABLED=true
//     a misconfiguration (missing project id / unreadable or invalid
//     service-account JSON) fails fast with a clear error.
//  6. api.NewServer + http.Server with graceful shutdown on
//     SIGINT/SIGTERM: http.Server.Shutdown first, then store.Close.
//
// Compose management mode (§11.4.76):
//
//  When invoked with --compose-up, --compose-down, or --compose-status,
//  the binary manages the SFTP stack through the containers submodule
//  (vasic-digital/containers) instead of starting the API server. No
//  ad-hoc podman/docker commands are used.
//
// Credentials discipline (§11.4.10): SUPERADMIN_PASSWORD and JWT_SECRET are
// consumed from the environment and NEVER printed, logged, or written to
// any response.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/vasic-digital/sftp/api/internal/api"
	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/config"
	stackpkg "github.com/vasic-digital/sftp/api/internal/containers"
	"github.com/vasic-digital/sftp/api/internal/firebase"
	"github.com/vasic-digital/sftp/api/internal/store"
	"github.com/vasic-digital/sftp/api/internal/vault"
)

// shutdownTimeout bounds the graceful drain on signal.
const shutdownTimeout = 15 * time.Second

func main() {
	// Compose management flags (§11.4.76 — containers submodule is the
	// sole orchestration layer).
	composeUp := flag.Bool("compose-up", false, "Start SFTP compose stack via the containers layer")
	composeDown := flag.Bool("compose-down", false, "Stop SFTP compose stack")
	composeStatus := flag.Bool("compose-status", false, "Show health of SFTP compose stack")
	serveWeb := flag.Bool("serve-web", false, "Serve the built web SPA from web/dist/ (SPA fallback enabled)")
	flag.Parse()

	if *composeUp || *composeDown || *composeStatus {
		projectRoot := resolveProjectRoot()
		if err := runComposeCmd(*composeUp, *composeDown, *composeStatus, projectRoot); err != nil {
			log.Printf("sftp-api: compose: %v", err)
			os.Exit(1)
		}
		return
	}

	// Default: API server mode.
	if err := run(*serveWeb); err != nil {
		log.Printf("sftp-api: fatal: %v", err)
		os.Exit(1)
	}
}

// resolveProjectRoot returns the project root directory. It checks
// SFTP_PROJECT_ROOT first, then falls back to the current working
// directory. Scripts (sftp_ctl.sh) always set SFTP_PROJECT_ROOT.
func resolveProjectRoot() string {
	if v := os.Getenv("SFTP_PROJECT_ROOT"); v != "" {
		return v
	}
	wd, err := os.Getwd()
	if err != nil {
		log.Fatalf("sftp-api: cannot determine project root: %v (set SFTP_PROJECT_ROOT)", err)
	}
	return wd
}

// runComposeCmd dispatches a compose management command (up/down/status)
// through the containers submodule. It prints a human-readable summary
// and exits zero on success.
func runComposeCmd(up, down, status bool, projectRoot string) error {
	ctx := context.Background()

	stk, err := stackpkg.New(stackpkg.Config{
		ProjectRoot: projectRoot,
	})
	if err != nil {
		return fmt.Errorf("init stack: %w", err)
	}

	switch {
	case up:
		log.Printf("sftp-api: starting stack via containers layer (compose file: %s)", stk.ComposeFile())
		if err := stk.Start(ctx); err != nil {
			return fmt.Errorf("start stack: %w", err)
		}
		log.Printf("sftp-api: stack started — verify with: sftp-api --compose-status")
		return nil

	case down:
		log.Printf("sftp-api: stopping stack via containers layer")
		if err := stk.Stop(ctx); err != nil {
			return fmt.Errorf("stop stack: %w", err)
		}
		log.Printf("sftp-api: stack stopped")
		return nil

	case status:
		report, err := stk.Health(ctx)
		if err != nil {
			return fmt.Errorf("health: %w", err)
		}
		fmt.Println("=== SFTP Enterprise stack (containers layer) ===")
		fmt.Printf("Compose file : %s\n", stk.ComposeFile())
		fmt.Println()
		if len(report.Services) == 0 {
			fmt.Println("No services found — stack may not be started.")
			return nil
		}
		for _, s := range report.Services {
			marker := "  "
			if !s.Healthy {
				marker = "! "
			}
			healthStr := s.Health
			if healthStr == "" {
				healthStr = "—"
			}
			fmt.Printf("%s%-16s  state=%-10s  health=%s\n",
				marker, s.Name, s.State, healthStr)
		}
		if report.AllHealthy {
			fmt.Println("\nAll services healthy.")
		} else {
			fmt.Println("\nOne or more services are NOT healthy.")
		}
		return nil

	default:
		return fmt.Errorf("no compose command specified")
	}
}

func run(serveWeb bool) error {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if serveWeb {
		cfg.ServeWeb = true
	}
	if err := cfg.Validate(); err != nil {
		return err
	}

	dsn := cfg.DBPath
	driver := cfg.DBDriver
	if driver == "" {
		driver = "sqlite"
	}
	if driver == "postgres" && cfg.DBDSN != "" {
		dsn = cfg.DBDSN
	}
	st, err := store.Open(ctx, driver, dsn)
	if err != nil {
		return fmt.Errorf("sftp-api: open store: %w", err)
	}
	defer func() {
		if cerr := st.Close(); cerr != nil {
			log.Printf("sftp-api: store close error: %v", cerr)
		}
	}()

	// Seed the super-admin. The password is bcrypt-hashed in memory and
	// only the hash is persisted; the plaintext never leaves this scope.
	if cfg.SuperAdminPassword != "" {
		hash, err := authn.HashPassword(cfg.SuperAdminPassword)
		if err != nil {
			return fmt.Errorf("sftp-api: hash super-admin password: %w", err)
		}
		created, err := st.SeedAdmin(ctx, cfg.SuperAdminUsername, hash)
		if err != nil {
			return fmt.Errorf("sftp-api: seed super-admin: %w", err)
		}
		if created {
			log.Printf("sftp-api: super-admin %q seeded", cfg.SuperAdminUsername)
		}
	}

	authSvc, err := authn.NewService(cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	if err != nil {
		return fmt.Errorf("sftp-api: auth service: %w", err)
	}

	// Firebase is OPTIONAL (ATM-007): disabled → logs "firebase: disabled"
	// and the API continues; enabled-but-misconfigured → fail fast with a
	// clear error (§11.4.6). Telemetry hooks are no-op-safe.
	fbClient, err := firebase.New(ctx, firebase.Options{
		Enabled:            cfg.FirebaseEnabled,
		ProjectID:          cfg.FirebaseProjectID,
		ServiceAccountPath: cfg.FirebaseServiceAccountPath,
	})
	if err != nil {
		return err
	}

	vl, err := vault.New(vault.VaultConfig{DataDir: cfg.VaultDataDir})
	if err != nil {
		return fmt.Errorf("sftp-api: open vault: %w", err)
	}

	srv := api.NewServer(cfg, st, authSvc, fbClient, vl)
	httpSrv := &http.Server{
		Addr:              cfg.Addr(),
		Handler:           srv.Engine(),
		ReadHeaderTimeout: 10 * time.Second,
	}

	// Graceful shutdown: first interrupt cancels in-flight requests after
	// the drain timeout; a second interrupt forces exit.
	sigCh := make(chan os.Signal, 2)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(sigCh)

	errCh := make(chan error, 1)
	go func() {
		log.Printf("sftp-api: listening on %s (version %s)", cfg.Addr(), cfg.Version)
		errCh <- httpSrv.ListenAndServe()
	}()

	select {
	case err := <-errCh:
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("sftp-api: http server: %w", err)
		}
		return nil
	case sig := <-sigCh:
		log.Printf("sftp-api: received %s, shutting down gracefully", sig)
		shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
		defer cancel()
		if err := httpSrv.Shutdown(shutdownCtx); err != nil {
			return fmt.Errorf("sftp-api: graceful shutdown: %w", err)
		}
		log.Printf("sftp-api: shutdown complete")
		return nil
	}
}
