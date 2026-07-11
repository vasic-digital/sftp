package api

import (
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"

	"github.com/vasic-digital/sftp/api/internal/crypt"
	"github.com/vasic-digital/sftp/api/internal/sftpsync"
)

// cryptVault holds the sha512-crypt ($6$) hashes rendered into users.conf
// for password-authenticating accounts. It lives in process memory only —
// hashes are computed at account create/update time from the write-only
// request password (§11.4.10: plaintext exists only within the request
// handler that received it).
//
// Design boundary (documented in api/README.md): an in-memory vault means
// users.conf entries for accounts created in a PREVIOUS process run are
// rendered with `*` (no password login) after an API restart until the
// account's password is set again. The DB holds only the API-side bcrypt
// hash, which cannot be converted into a crypt hash. This is the safe
// failure direction (fail closed), and the /sync response reports the
// count so operators can detect it.
type cryptVault struct {
	mu     sync.RWMutex
	hashes map[string]string
}

func newCryptVault() *cryptVault {
	return &cryptVault{hashes: map[string]string{}}
}

// set computes and stores the crypt hash for username's plaintext
// password. Called from account create/update handlers while the
// plaintext is still in scope.
func (v *cryptVault) set(username, plaintext string) error {
	h, err := crypt.Hash(plaintext)
	if err != nil {
		return err
	}
	v.mu.Lock()
	v.hashes[username] = h
	v.mu.Unlock()
	return nil
}

func (v *cryptVault) get(username string) string {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return v.hashes[username]
}

func (v *cryptVault) delete(username string) {
	v.mu.Lock()
	delete(v.hashes, username)
	v.mu.Unlock()
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
