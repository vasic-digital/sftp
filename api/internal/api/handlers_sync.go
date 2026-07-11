package api

import (
	"context"
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/crypt"
	"github.com/vasic-digital/sftp/api/internal/sftpsync"
	"github.com/vasic-digital/sftp/api/internal/vault"
)

// cryptVault manages sha512-crypt ($6$) hashes rendered into users.conf.
// It wraps a persistent encrypted vault.Vault so passwords survive API
// restarts. Before this, hashes lived in an in-memory map and were lost on
// every restart — accounts created in a previous process run rendered with
// `*` (no password login) until their password was set again.
//
// Security boundary (§11.4.10): the vault stores ONLY the crypt hash
// (never the plaintext). The plaintext exists only within the request
// handler that received it and is discarded immediately after the hash is
// computed and stored.
type cryptVault struct {
	v *vault.Vault
}

func newCryptVault(v *vault.Vault) *cryptVault {
	return &cryptVault{v: v}
}

// set computes the sha512-crypt hash of plaintext and persists it in the
// encrypted vault. Called from account create/update handlers while the
// plaintext is still in scope.
func (cv *cryptVault) set(username, plaintext string) error {
	h, err := crypt.Hash(plaintext)
	if err != nil {
		return err
	}
	return cv.v.Store(context.Background(), username, h)
}

// get loads the crypt hash from the vault. Returns "" on any error
// (missing entry, I/O failure, corrupt blob) — the sftpsync layer treats
// an empty hash as "no password login", so this fails safely.
func (cv *cryptVault) get(username string) string {
	h, err := cv.v.Load(context.Background(), username)
	if err != nil {
		return ""
	}
	return h
}

// delete removes an entry from the vault. Errors are silently ignored
// because callers cannot recover (the account record is already deleted
// from the store).
func (cv *cryptVault) delete(username string) {
	_ = cv.v.Delete(context.Background(), username)
}

// handleSync renders users.conf from the current account set.
func (s *Server) handleSync(c *gin.Context) {
	accounts, err := s.store.ListAccounts(c.Request.Context())
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not list accounts")
		return
	}
	lines, err := sftpsync.Write(s.cfg.UsersConfPath, accounts, s.vault.get)
	if err != nil {
		respondError(c, http.StatusInternalServerError, codeInternal, "could not write users.conf")
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"rendered_accounts": lines,
		"path":              s.cfg.UsersConfPath,
	})
}
