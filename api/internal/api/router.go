// Package api wires the HTTP surface of the SFTP management API: the Gin
// router, middleware stack, auth/account/sync handlers, and their tests.
package api

import (
	"log"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/config"
	"github.com/vasic-digital/sftp/api/internal/firebase"
	"github.com/vasic-digital/sftp/api/internal/store"
	"github.com/vasic-digital/sftp/api/internal/vault"

	mwgin "digital.vasic.middleware/pkg/gin"
	"digital.vasic.middleware/pkg/recovery"
	"digital.vasic.middleware/pkg/requestid"
)

// contextKeyClaims is the Gin context key under which validated JWT claims
// are stored by the auth middleware.
const contextKeyClaims = "authn.claims"

// Server bundles the router's collaborators.
type Server struct {
	cfg      *config.Config
	store    *store.Store
	authn    *authn.Service
	firebase *firebase.Client
	vault    *cryptVault
}

// NewServer constructs a Server from already-opened collaborators.
// v is the persistent encrypted vault for users.conf password hashes;
// it MUST be non-nil (the API refuses to start without it).
// fb may be nil when Firebase is disabled.
func NewServer(cfg *config.Config, st *store.Store, auth *authn.Service, fb *firebase.Client, v *vault.Vault) *Server {
	return &Server{cfg: cfg, store: st, authn: auth, firebase: fb, vault: newCryptVault(v)}
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
	// Gin-native request logger — reads c.Writer.Status() AFTER c.Next()
	// so the logged status code is always the actual response status.
	// The generic logging middleware wrapped via mwgin.Wrap cannot be used
	// here because its statusRecorder wraps c.Writer but Gin handlers write
	// to c.Writer directly, bypassing the wrapper (the Wrap adapter
	// ignores the wrapped http.ResponseWriter and only calls c.Next()).
	r.Use(s.requestLogger())
	r.Use(s.securityHeadersMiddleware())
	if s.cfg.CORSOrigin != "" {
		r.Use(s.corsMiddleware())
	}

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
	secured.POST("/auth/logout", s.handleLogout)
	secured.GET("/accounts", s.handleListAccounts)
	secured.POST("/accounts", s.handleCreateAccount)
	secured.GET("/accounts/:username", s.handleGetAccount)
	secured.PUT("/accounts/:username", s.handleUpdateAccount)
	secured.DELETE("/accounts/:username", s.handleDeleteAccount)
	secured.POST("/sync", s.handleSync)

	return r
}

// requestLogger logs every HTTP request AFTER the handler has written the
// response, ensuring the logged status code is the actual status — never
// the default 200 from a wrapper that Gin's internals bypassed.
func (s *Server) requestLogger() gin.HandlerFunc {
	skipPaths := map[string]struct{}{"/api/v1/health": {}}
	return func(c *gin.Context) {
		if _, skip := skipPaths[c.Request.URL.Path]; skip {
			c.Next()
			return
		}
		start := time.Now()
		c.Next()
		log.Printf("[HTTP] %s %s %d %s",
			c.Request.Method,
			c.Request.URL.Path,
			c.Writer.Status(),
			time.Since(start),
		)
	}
}

// handleHealth is the unauthenticated liveness probe.
func (s *Server) handleHealth(c *gin.Context) {
	resp := gin.H{
		"status":  "ok",
		"version": s.cfg.Version,
		"time":    time.Now().UTC().Format(time.RFC3339),
	}
	if s.firebase == nil {
		resp["firebase"] = "unavailable"
	} else if !s.firebase.Active() {
		resp["firebase"] = "disabled"
	} else {
		if err := s.firebase.Verify(c.Request.Context()); err != nil {
			log.Printf("sftp-api: firebase verify failed: %v", err)
			resp["firebase"] = "unhealthy"
		} else {
			resp["firebase"] = "connected"
		}
	}
	c.JSON(http.StatusOK, resp)
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

// corsMiddleware adds CORS headers when the request Origin matches the
// configured CORSOrigin. Preflight OPTIONS requests receive a 204.
// credentials mode is enabled so HttpOnly cookies are sent cross-origin
// during development (Vite dev server on a different port).
func (s *Server) corsMiddleware() gin.HandlerFunc {
	allowed := s.cfg.CORSOrigin
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		if origin != allowed {
			c.Next()
			return
		}
		c.Header("Access-Control-Allow-Origin", allowed)
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type, X-Request-ID")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Max-Age", "86400")

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

// securityHeadersMiddleware sets response headers that harden the API
// against common browser-side attacks. These are additive — they never
// reject a request.
func (s *Server) securityHeadersMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("X-Frame-Options", "DENY")
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")
		c.Next()
	}
}
