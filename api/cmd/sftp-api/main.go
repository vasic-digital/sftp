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
//  6. api.NewServer + http.Server with graceful shutdown on
//     SIGINT/SIGTERM: http.Server.Shutdown first, then store.Close.
//
// Credentials discipline (§11.4.10): SUPERADMIN_PASSWORD and JWT_SECRET are
// consumed from the environment and NEVER printed, logged, or written to
// any response.
package main

import (
	"context"
	"errors"
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
	"github.com/vasic-digital/sftp/api/internal/store"
)

// shutdownTimeout bounds the graceful drain on signal.
const shutdownTimeout = 15 * time.Second

func main() {
	if err := run(); err != nil {
		// Log the error class only — error messages from config.Validate
		// never contain secret material (they state that a value is
		// missing/invalid, not its content).
		log.Printf("sftp-api: fatal: %v", err)
		os.Exit(1)
	}
}

func run() error {
	ctx := context.Background()

	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if err := cfg.Validate(); err != nil {
		return err
	}

	st, err := store.Open(ctx, cfg.DBPath)
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

	srv := api.NewServer(cfg, st, authSvc)
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
