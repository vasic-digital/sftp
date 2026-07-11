package api

import (
	"github.com/gin-gonic/gin"
)

// errorBody is the single JSON error envelope every failing endpoint
// returns: a machine-readable `code` plus a human-readable `error`.
type errorBody struct {
	Code  string `json:"code"`
	Error string `json:"error"`
}

// respondError writes the JSON error envelope with the given status.
func respondError(c *gin.Context, status int, code, message string) {
	c.JSON(status, errorBody{Code: code, Error: message})
}

// Error codes used across handlers (stable wire values — tests assert them).
const (
	codeBadRequest        = "bad_request"
	codeValidation        = "validation_error"
	codeUnauthorized      = "unauthorized"
	codeNotFound          = "not_found"
	codeConflict          = "conflict"
	codeRateLimited       = "rate_limited"
	codeInternal          = "internal_error"
	codePublicNotAcked    = "public_access_not_acknowledged"
	codeInvalidCredential = "invalid_credentials"
)
