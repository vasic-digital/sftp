package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/authn"
	"github.com/vasic-digital/sftp/api/internal/store"
)

// accountRequest is the body of POST/PUT /api/v1/accounts[/:username].
//
// SECURITY (§11.4.10): Password is write-only — it is bcrypt-hashed
// in-memory and NEVER echoed back, logged, or included in any response.
//
// `public` permission is NEVER a default and requires explicit
// acknowledgement: PublicAcknowledged MUST be true when Permission is
// "public", otherwise the request is rejected with 422.
type accountRequest struct {
	Username           string `json:"username"`
	Password           string `json:"password"`
	Permission         string `json:"permission"`
	PublicAcknowledged bool   `json:"public_acknowledged"`
	UID                *int   `json:"uid"`
	GID                *int   `json:"gid"`
	HomeDir            string `json:"home_dir"`
	Enabled            *bool  `json:"enabled"`
}

// accountResponse is the JSON representation of an account. It carries NO
// password material of any kind (neither the bcrypt hash nor the crypt
// hash rendered into users.conf).
type accountResponse struct {
	Username   string `json:"username"`
	Permission string `json:"permission"`
	UID        *int   `json:"uid"`
	GID        *int   `json:"gid"`
	HomeDir    string `json:"home_dir"`
	Enabled    bool   `json:"enabled"`
	CreatedAt  string `json:"created_at"`
	UpdatedAt  string `json:"updated_at"`
}

func toAccountResponse(a *store.Account) accountResponse {
	return accountResponse{
		Username:   a.Username,
		Permission: a.Permission,
		UID:        a.UID,
		GID:        a.GID,
		HomeDir:    a.HomeDir,
		Enabled:    a.Enabled,
		CreatedAt:  a.CreatedAt.UTC().Format(time.RFC3339),
		UpdatedAt:  a.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

// applyDefaults fills unset fields with the documented defaults:
// permission read_only, home /<username>, enabled true.
func (r *accountRequest) applyDefaults() {
	if r.Permission == "" {
		r.Permission = store.PermissionReadOnly
	}
	if r.HomeDir == "" {
		r.HomeDir = "/" + r.Username
	}
}

// checkPublicAck enforces the explicit-acknowledgement guard for public
// access. Returns false (after writing the 422 response) when violated.
func checkPublicAck(c *gin.Context, permission string, acked bool) bool {
	if permission == store.PermissionPublic && !acked {
		respondError(c, http.StatusUnprocessableEntity, codePublicNotAcked,
			"public access is never a default: set public_acknowledged=true to confirm")
		return false
	}
	return true
}

// handleCreateAccount creates a new SFTP account (201 on success).
func (s *Server) handleCreateAccount(c *gin.Context) {
	var req accountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, codeBadRequest, "invalid JSON body")
		return
	}
	if req.Username == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "username is required")
		return
	}
	if req.Password == "" {
		respondError(c, http.StatusBadRequest, codeValidation, "password is required")
		return
	}
	req.applyDefaults()
	if !checkPublicAck(c, req.Permission, req.PublicAcknowledged) {
		return
	}

	hash, err := authn.HashPassword(req.Password)
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not hash password")
		return
	}
	// Compute the users.conf crypt hash while the plaintext is still in
	// scope — the vault keeps only the hash (§11.4.10).
	if err := s.vault.set(req.Username, req.Password); err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not derive login credential")
		return
	}

	enabled := true
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	a := &store.Account{
		Username:     req.Username,
		PasswordHash: hash,
		Permission:   req.Permission,
		UID:          req.UID,
		GID:          req.GID,
		HomeDir:      req.HomeDir,
		Enabled:      enabled,
	}
	if err := s.store.CreateAccount(c.Request.Context(), a); err != nil {
		switch {
		case errors.Is(err, store.ErrDuplicateUsername):
			respondError(c, http.StatusConflict, codeConflict, "username already exists")
		case errors.Is(err, store.ErrValidation):
			respondError(c, http.StatusBadRequest, codeValidation, err.Error())
		default:
			respondError(c, http.StatusInternalServerError, codeInternal, "could not create account")
		}
		return
	}
	c.JSON(http.StatusCreated, toAccountResponse(a))
}

// handleListAccounts returns all accounts (without any password material).
func (s *Server) handleListAccounts(c *gin.Context) {
	accounts, err := s.store.ListAccounts(c.Request.Context())
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not list accounts")
		return
	}
	out := make([]accountResponse, 0, len(accounts))
	for _, a := range accounts {
		out = append(out, toAccountResponse(a))
	}
	c.JSON(http.StatusOK, gin.H{"accounts": out, "count": len(out)})
}

// handleGetAccount returns one account by username.
func (s *Server) handleGetAccount(c *gin.Context) {
	a, err := s.store.GetAccount(c.Request.Context(), c.Param("username"))
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(c, http.StatusNotFound, codeNotFound, "account not found")
			return
		}
		respondError(c, http.StatusInternalServerError, codeInternal, "could not get account")
		return
	}
	c.JSON(http.StatusOK, toAccountResponse(a))
}

// handleUpdateAccount replaces an account's mutable fields. The username
// in the path wins over any username in the body. Password is optional:
// when provided it is re-hashed; when omitted the existing hash is kept.
func (s *Server) handleUpdateAccount(c *gin.Context) {
	username := c.Param("username")
	existing, err := s.store.GetAccount(c.Request.Context(), username)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(c, http.StatusNotFound, codeNotFound, "account not found")
			return
		}
		respondError(c, http.StatusInternalServerError, codeInternal, "could not get account")
		return
	}

	var req accountRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		respondError(c, http.StatusBadRequest, codeBadRequest, "invalid JSON body")
		return
	}
	req.Username = username
	req.applyDefaults()
	if !checkPublicAck(c, req.Permission, req.PublicAcknowledged) {
		return
	}

	hash := existing.PasswordHash
	if req.Password != "" {
		hash, err = authn.HashPassword(req.Password)
		if err != nil {
			respondError(c, http.StatusInternalServerError, codeInternal, "could not hash password")
			return
		}
		if err := s.vault.set(username, req.Password); err != nil {
			respondError(c, http.StatusInternalServerError, codeInternal, "could not derive login credential")
			return
		}
	}
	enabled := existing.Enabled
	if req.Enabled != nil {
		enabled = *req.Enabled
	}
	a := &store.Account{
		Username:     username,
		PasswordHash: hash,
		Permission:   req.Permission,
		UID:          req.UID,
		GID:          req.GID,
		HomeDir:      req.HomeDir,
		Enabled:      enabled,
	}
	if err := s.store.UpdateAccount(c.Request.Context(), a); err != nil {
		switch {
		case errors.Is(err, store.ErrNotFound):
			respondError(c, http.StatusNotFound, codeNotFound, "account not found")
		case errors.Is(err, store.ErrValidation):
			respondError(c, http.StatusBadRequest, codeValidation, err.Error())
		default:
			respondError(c, http.StatusInternalServerError, codeInternal, "could not update account")
		}
		return
	}
	c.JSON(http.StatusOK, toAccountResponse(a))
}

// handleDeleteAccount removes an account.
func (s *Server) handleDeleteAccount(c *gin.Context) {
	username := c.Param("username")
	if err := s.store.DeleteAccount(c.Request.Context(), username); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			respondError(c, http.StatusNotFound, codeNotFound, "account not found")
			return
		}
		respondError(c, http.StatusInternalServerError, codeInternal, "could not delete account")
		return
	}
	s.vault.delete(username)
	c.Status(http.StatusNoContent)
}
