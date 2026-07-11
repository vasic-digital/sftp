package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/store"
)

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
func (s *Server) handleRefresh(c *gin.Context) {
	var req refreshRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, codeBadRequest, "invalid JSON body")
		return
	}
	if req.RefreshToken == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "refresh_token is required")
		return
	}
	claims, err := s.authn.ValidateRefresh(req.RefreshToken)
	if err != nil {
		respondError(c, http.StatusUnauthorized, codeUnauthorized, "invalid or expired refresh token")
		return
	}
	pair, err := s.authn.IssuePair(claims.Subject)
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not issue tokens")
		return
	}
	c.JSON(http.StatusOK, tokenResponse{
		AccessToken:      pair.AccessToken,
		RefreshToken:     pair.RefreshToken,
		TokenType:        "Bearer",
		ExpiresIn:        int64(s.authn.AccessTTL().Seconds()),
		RefreshExpiresIn: int64(s.authn.RefreshTTL().Seconds()),
	})
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
