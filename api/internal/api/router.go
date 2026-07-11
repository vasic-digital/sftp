// Package api wires the HTTP surface of the SFTP management API: the Gin
// router, middleware stack, auth/account/sync handlers, and their tests.
package api

import (
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/config"
	"github.com/vasic-digital/sftp/api/internal/store"

	mwgin "digital.vasic.middleware/pkg/gin"
	"digital.vasic.middleware/pkg/logging"
	"digital.vasic.middleware/pkg/recovery"
	"digital.vasic.middleware/pkg/requestid"
)

// contextKeyClaims is the Gin context key under which validated JWT claims
// are stored by the auth middleware.
const contextKeyClaims = "authn.claims"

// Server bundles the router's collaborators.
type Server struct {
	cfg   *config.Config
	store *store.Store
	authn *authn.Service
	vault *cryptVault
}

// NewServer constructs a Server from already-opened collaborators.
func NewServer(cfg *config.Config, st *store.Store, auth *authn.Service) *Server {
	return &Server{cfg: cfg, store: st, authn: auth, vault: newCryptVault()}
}

// Engine builds the Gin engine with the full middleware stack and routes.
//
// Middleware strategy (verified decision, see api/README.md):
//   - requestid / logging / recovery are reused from the shared middleware
//     submodule via gin.Wrap — they are ADDITIVE (never reject a request),
//     which is the only pattern gin.Wrap is safe for (the adapter does not
//     abort the Gin context when a wrapped middleware rejects).
//   - JWT auth and auth-endpoint rate limiting are NATIVE Gin middleware:
//     both must abort the chain on rejection.
func (s *Server) Engine() *gin.Engine {
	r := gin.New()

	r.Use(mwgin.Wrap(requestid.New()))
	r.Use(mwgin.Wrap(recovery.New(&recovery.Config{PrintStack: false})))
	r.Use(mwgin.Wrap(logging.New(&logging.Config{
		SkipPaths: map[string]struct{}{"/api/v1/health": {}},
	})))

	v1 := r.Group("/api/v1")
	v1.GET("/health", s.handleHealth)

	// Auth endpoints: rate-limited, no JWT required.
	auth := v1.Group("/auth")
	auth.Use(s.rateLimitMiddleware(s.cfg.LoginRateLimit, s.cfg.LoginRateWindow))
	auth.POST("/login", s.handleLogin)
	auth.POST("/refresh", s.handleRefresh)

	// Everything else under /api/v1 requires a valid access token.
	secured := v1.Group("")
	secured.Use(s.authMiddleware())
	secured.GET("/auth/me", s.handleMe)
	secured.GET("/accounts", s.handleListAccounts)
	secured.POST("/accounts", s.handleCreateAccount)
	secured.GET("/accounts/:username", s.handleGetAccount)
	secured.PUT("/accounts/:username", s.handleUpdateAccount)
	secured.DELETE("/accounts/:username", s.handleDeleteAccount)
	secured.POST("/sync", s.handleSync)

	return r
}

// handleHealth is the unauthenticated liveness probe.
func (s *Server) handleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"version": s.cfg.Version,
		"time":    time.Now().UTC().Format(time.RFC3339),
	})
}

// authMiddleware rejects requests without a valid access-token bearer
// header and stores the validated claims in the Gin context.
func (s *Server) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			respondError(c, http.StatusUnauthorized, codeUnauthorized, "missing bearer token")
			c.Abort()
			return
		}
		claims, err := s.authn.ValidateAccess(strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			respondError(c, http.StatusUnauthorized, codeUnauthorized, "invalid or expired token")
			c.Abort()
			return
		}
		c.Set(contextKeyClaims, claims)
		c.Next()
	}
}

// claimsFromContext retrieves claims stored by authMiddleware.
func claimsFromContext(c *gin.Context) (*authn.Claims, bool) {
	v, ok := c.Get(contextKeyClaims)
	if !ok {
		return nil, false
	}
	claims, ok := v.(*authn.Claims)
	return claims, ok
}

// ipLimiter is a minimal fixed-window per-client-IP rate limiter. The
// shared ratelimit middleware could not be reused here: gin.Wrap does not
// abort the chain when the wrapped middleware rejects (verified in
// middleware/pkg/gin/gin.go), so a 429 would be followed by the handler
// running anyway and rewriting the status.
type ipLimiter struct {
	mu      sync.Mutex
	entries map[string]*limitEntry
	rate    int
	window  time.Duration
}

type limitEntry struct {
	windowStart time.Time
	count       int
}

// rateLimitMiddleware allows `rate` requests per `window` per client IP.
// rate <= 0 disables limiting (used by tests).
func (s *Server) rateLimitMiddleware(rate int, window time.Duration) gin.HandlerFunc {
	if window <= 0 {
		window = time.Minute
	}
	l := &ipLimiter{entries: map[string]*limitEntry{}, rate: rate, window: window}
	return func(c *gin.Context) {
		if rate <= 0 {
			c.Next()
			return
		}
		ip := c.ClientIP()
		now := time.Now()

		l.mu.Lock()
		e, ok := l.entries[ip]
		if !ok || now.Sub(e.windowStart) >= l.window {
			e = &limitEntry{windowStart: now}
			l.entries[ip] = e
		}
		e.count++
		over := e.count > l.rate
		l.mu.Unlock()

		if over {
			c.Header("Retry-After", "60")
			respondError(c, http.StatusTooManyRequests, codeRateLimited, "too many requests")
			c.Abort()
			return
		}
		c.Next()
	}
}
