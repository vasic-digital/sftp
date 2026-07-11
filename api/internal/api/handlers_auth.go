package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/store"
)

// refreshTokenCookie is the name of the HttpOnly cookie that carries the
// refresh token. It replaces localStorage for refresh tokens (XSS-resistant).
const refreshTokenCookie = "sftp_refresh_token"

// loginRequest is the body of POST /api/v1/auth/login.
//
// SECURITY (§11.4.10): the password is consumed in-memory to verify the
// stored bcrypt hash and is NEVER logged, echoed, or included in any
// response.
type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// tokenResponse is returned by login and refresh.
type tokenResponse struct {
	AccessToken      string `json:"access_token"`
	RefreshToken     string `json:"refresh_token"`
	TokenType        string `json:"token_type"`
	ExpiresIn        int64  `json:"expires_in"`
	RefreshExpiresIn int64  `json:"refresh_expires_in"`
}

// handleLogin authenticates the super-admin and issues a JWT pair.
func (s *Server) handleLogin(c *gin.Context) {
	var req loginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, codeBadRequest, "invalid JSON body")
		return
	}
	if req.Username == "" || req.Password == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "username and password are required")
		return
	}

	admin, err := s.store.GetAdmin(c.Request.Context(), req.Username)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			// Same response as a wrong password — no user enumeration.
			respondError(c, http.StatusUnauthorized, codeInvalidCredential, "invalid username or password")
			return
		}
		respondError(c, http.StatusInternalServerError, codeInternal, "could not look up admin")
		return
	}
	if err := authn.VerifyPassword(admin.PasswordHash, req.Password); err != nil {
		respondError(c, http.StatusUnauthorized, codeInvalidCredential, "invalid username or password")
		return
	}

	pair, err := s.authn.IssuePair(admin.Username)
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not issue tokens")
		return
	}

	s.setRefreshTokenCookie(c, pair.RefreshToken)

	c.JSON(http.StatusOK, tokenResponse{
		AccessToken:      pair.AccessToken,
		RefreshToken:     pair.RefreshToken,
		TokenType:        "Bearer",
		ExpiresIn:        int64(s.authn.AccessTTL().Seconds()),
		RefreshExpiresIn: int64(s.authn.RefreshTTL().Seconds()),
	})
}

// refreshRequest is the body of POST /api/v1/auth/refresh.
type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// handleRefresh exchanges a valid refresh token for a fresh JWT pair.
// The refresh token is read from the HttpOnly cookie first; if absent,
// the JSON request body is checked for backward compatibility.
func (s *Server) handleRefresh(c *gin.Context) {
	token := s.readRefreshToken(c)
	if token == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "refresh_token is required")
		return
	}
	claims, err := s.authn.ValidateRefresh(token)
	if err != nil {
		respondError(c, http.StatusUnauthorized, codeUnauthorized, "invalid or expired refresh token")
		return
	}
	pair, err := s.authn.IssuePair(claims.Subject)
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not issue tokens")
		return
	}

	s.setRefreshTokenCookie(c, pair.RefreshToken)

	c.JSON(http.StatusOK, tokenResponse{
		AccessToken:      pair.AccessToken,
		RefreshToken:     pair.RefreshToken,
		TokenType:        "Bearer",
		ExpiresIn:        int64(s.authn.AccessTTL().Seconds()),
		RefreshExpiresIn: int64(s.authn.RefreshTTL().Seconds()),
	})
}

// logoutRequest is the body of POST /api/v1/auth/logout.
type logoutRequest struct {
	RefreshToken string `json:"refresh_token"`
}

// handleLogout revokes the provided refresh token so it cannot be reused.
// The refresh token is read from the HttpOnly cookie first; if absent,
// the JSON request body is checked for backward compatibility.
// The cookie is always cleared on success.
func (s *Server) handleLogout(c *gin.Context) {
	token := s.readRefreshToken(c)
	if token == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "refresh_token is required")
		return
	}
	if err := s.authn.RevokeRefreshToken(token); err != nil {
		respondError(c, http.StatusUnauthorized, codeUnauthorized, "invalid or expired refresh token")
		return
	}
	// Clear the cookie regardless of how the token was read.
	s.clearRefreshTokenCookie(c)
	c.JSON(http.StatusOK, gin.H{"message": "logged out"})
}

// handleMe returns the identity carried by the caller's access token.
func (s *Server) handleMe(c *gin.Context) {
	claims, ok := claimsFromContext(c)
	if !ok {
		respondError(c, http.StatusUnauthorized, codeUnauthorized, "missing claims")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"username":   claims.Subject,
		"expires_at": claims.ExpiresAt.UTC().Format(time.RFC3339),
	})
}

// readRefreshToken attempts to read the refresh token from the HttpOnly
// cookie first. If the cookie is absent or empty, it falls back to the
// JSON request body for backward compatibility with clients that have not
// yet migrated to cookie-based tokens.
func (s *Server) readRefreshToken(c *gin.Context) string {
	if token, err := c.Cookie(refreshTokenCookie); err == nil && token != "" {
		return token
	}
	// Fall back to JSON body for backward compatibility.
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		return ""
	}
	return strings.TrimSpace(req.RefreshToken)
}

// setRefreshTokenCookie writes the refresh token as an HttpOnly,
// SameSite=Strict cookie. Secure is enabled when the request arrived over
// TLS (production behind a reverse proxy). The cookie path is scoped to
// /api/v1/auth so it is only sent on auth endpoints.
func (s *Server) setRefreshTokenCookie(c *gin.Context, token string) {
	maxAge := int(s.authn.RefreshTTL().Seconds())
	c.SetSameSite(http.SameSiteStrictMode)
	c.SetCookie(
		refreshTokenCookie,
		token,
		maxAge,
		"/api/v1/auth",
		"",
		c.Request.TLS != nil,
		true, // httpOnly
	)
}

// clearRefreshTokenCookie removes the refresh token cookie by setting
// MaxAge to -1.
func (s *Server) clearRefreshTokenCookie(c *gin.Context) {
	c.SetCookie(refreshTokenCookie, "", -1, "/api/v1/auth", "", c.Request.TLS != nil, true)
}
