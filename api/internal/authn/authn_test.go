package authn

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func TestBcryptRoundTrip(t *testing.T) {
	hash, err := HashPassword("correct horse battery staple")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if hash == "correct horse battery staple" {
		t.Fatalf("hash equals plaintext")
	}
	if !strings.HasPrefix(hash, "$2a$12$") && !strings.HasPrefix(hash, "$2b$12$") {
		t.Errorf("hash prefix = %q, want $2a$12$ or $2b$12$ (cost >= 12)", hash[:7])
	}
	if err := VerifyPassword(hash, "correct horse battery staple"); err != nil {
		t.Fatalf("verify correct password: %v", err)
	}
}

func TestBcryptWrongPasswordRejected(t *testing.T) {
	hash, err := HashPassword("right")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if err := VerifyPassword(hash, "wrong"); !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("verify wrong: err = %v, want ErrInvalidCredentials", err)
	}
}

func TestHashEmptyPasswordRejected(t *testing.T) {
	if _, err := HashPassword(""); err == nil {
		t.Fatalf("empty password accepted")
	}
}

func newTestService(t *testing.T) *Service {
	t.Helper()
	s, err := NewService("test-secret-with-more-than-32-characters", 15*time.Minute, 168*time.Hour)
	if err != nil {
		t.Fatalf("new service: %v", err)
	}
	return s
}

func TestIssueAndValidateAccessToken(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Fatalf("empty token in pair")
	}
	if pair.AccessToken == pair.RefreshToken {
		t.Fatalf("access and refresh tokens are identical")
	}
	wantExp := time.Now().Add(15 * time.Minute)
	if pair.AccessExpiresAt.Before(wantExp.Add(-time.Minute)) || pair.AccessExpiresAt.After(wantExp.Add(time.Minute)) {
		t.Errorf("access expiry = %v, want ~%v", pair.AccessExpiresAt, wantExp)
	}

	claims, err := s.ValidateAccess(pair.AccessToken)
	if err != nil {
		t.Fatalf("validate access: %v", err)
	}
	if claims.Subject != "admin" {
		t.Errorf("subject = %q, want admin", claims.Subject)
	}
	if claims.Kind != "access" {
		t.Errorf("kind = %q, want access", claims.Kind)
	}
}

func TestRefreshTokenValidatesAsRefresh(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	claims, err := s.ValidateRefresh(pair.RefreshToken)
	if err != nil {
		t.Fatalf("validate refresh: %v", err)
	}
	if claims.Subject != "admin" || claims.Kind != "refresh" {
		t.Errorf("claims = %+v, want subject=admin kind=refresh", claims)
	}
}

func TestRefreshTokenRejectedAsAccess(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// A refresh token must NOT be usable as an access token (and vice versa).
	if _, err := s.ValidateAccess(pair.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("refresh-as-access: err = %v, want ErrInvalidToken", err)
	}
	if _, err := s.ValidateRefresh(pair.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("access-as-refresh: err = %v, want ErrInvalidToken", err)
	}
}

func TestExpiredTokenRejected(t *testing.T) {
	s := newTestService(t)
	// Force the clock so the issued token is already expired. 200h backdate
	// exceeds BOTH the access TTL (minutes) and the refresh TTL (168h).
	s.now = func() time.Time { return time.Now().Add(-200 * time.Hour) }
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if _, err := s.ValidateAccess(pair.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("expired access accepted: err = %v, want ErrInvalidToken", err)
	}
	if _, err := s.ValidateRefresh(pair.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("expired refresh accepted: err = %v, want ErrInvalidToken", err)
	}
}

func TestTamperedTokenRejected(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// Flip the FIRST character of the signature segment. The last base64
	// char of an unpadded segment can hold only padding bits (flipping it
	// may decode to identical bytes and NOT actually tamper the MAC —
	// that is a blind test). The first char always carries significant
	// bits, so the decoded signature provably differs.
	sigStart := strings.LastIndex(pair.AccessToken, ".") + 1
	head := pair.AccessToken[:sigStart]
	lastSeg := pair.AccessToken[sigStart:]
	flipped := "A"
	if lastSeg[0] == 'A' {
		flipped = "B"
	}
	tampered := head + flipped + lastSeg[1:]
	if _, err := s.ValidateAccess(tampered); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("tampered token accepted: err = %v", err)
	}
}

func TestWrongSecretRejected(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	other, err := NewService("a-different-secret-also-long-enough-32+", 15*time.Minute, 168*time.Hour)
	if err != nil {
		t.Fatalf("other service: %v", err)
	}
	if _, err := other.ValidateAccess(pair.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("token from another secret accepted: err = %v", err)
	}
}

func TestAlgNoneRejected(t *testing.T) {
	s := newTestService(t)
	// Hand-craft an alg=none token — the parser must refuse it because the
	// keyfunc rejects non-HMAC methods.
	claims := jwt.MapClaims{
		"iss":  "sftp-api",
		"sub":  "admin",
		"kind": "access",
		"iat":  time.Now().Unix(),
		"exp":  time.Now().Add(time.Hour).Unix(),
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodNone, claims)
	signed, err := tok.SignedString(jwt.UnsafeAllowNoneSignatureType)
	if err != nil {
		t.Fatalf("sign none: %v", err)
	}
	if _, err := s.ValidateAccess(signed); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("alg=none token accepted: err = %v, want ErrInvalidToken", err)
	}
}

func TestEmptyTokenRejected(t *testing.T) {
	s := newTestService(t)
	if _, err := s.ValidateAccess(""); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("empty token: err = %v, want ErrInvalidToken", err)
	}
}

func TestNewServiceValidation(t *testing.T) {
	if _, err := NewService("", time.Minute, time.Hour); err == nil {
		t.Errorf("empty secret accepted")
	}
	if _, err := NewService("secret", 0, time.Hour); err == nil {
		t.Errorf("zero access TTL accepted")
	}
	if _, err := NewService("secret", time.Hour, time.Minute); err == nil {
		t.Errorf("refresh <= access accepted")
	}
}

func TestIssuePairEmptySubject(t *testing.T) {
	s := newTestService(t)
	if _, err := s.IssuePair(""); err == nil {
		t.Errorf("empty subject accepted")
	}
}

func TestTokenPairHasJTI(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	claims, err := s.ValidateAccess(pair.AccessToken)
	if err != nil {
		t.Fatalf("validate access: %v", err)
	}
	if claims.JTI == "" {
		t.Fatalf("access token missing JTI")
	}
	claims, err = s.ValidateRefresh(pair.RefreshToken)
	if err != nil {
		t.Fatalf("validate refresh: %v", err)
	}
	if claims.JTI == "" {
		t.Fatalf("refresh token missing JTI")
	}
}

func TestRevokeRefreshToken(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// Validate before revoke — must succeed.
	if _, err := s.ValidateRefresh(pair.RefreshToken); err != nil {
		t.Fatalf("validate before revoke: %v", err)
	}
	// Revoke the refresh token.
	if err := s.RevokeRefreshToken(pair.RefreshToken); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	// Validate after revoke — must fail with ErrTokenRevoked.
	if _, err := s.ValidateRefresh(pair.RefreshToken); !errors.Is(err, ErrTokenRevoked) {
		t.Fatalf("validate after revoke: err = %v, want ErrTokenRevoked", err)
	}
	// Access token from the same pair is NOT revoked.
	if _, err := s.ValidateAccess(pair.AccessToken); err != nil {
		t.Fatalf("access token wrongly revoked: %v", err)
	}
}

func TestRevokeAccessTokenRejected(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// RevokeRefreshToken must reject an access token.
	if err := s.RevokeRefreshToken(pair.AccessToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("revoke access token: err = %v, want ErrInvalidToken", err)
	}
}

func TestIsJTIRevoked(t *testing.T) {
	s := newTestService(t)
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	claims, err := s.ValidateRefresh(pair.RefreshToken)
	if err != nil {
		t.Fatalf("validate refresh: %v", err)
	}
	if s.IsJTIRevoked(claims.JTI) {
		t.Fatalf("JTI must not be revoked before RevokeRefreshToken")
	}
	if err := s.RevokeRefreshToken(pair.RefreshToken); err != nil {
		t.Fatalf("revoke: %v", err)
	}
	if !s.IsJTIRevoked(claims.JTI) {
		t.Fatalf("JTI must be revoked after RevokeRefreshToken")
	}
}

func TestRevokeExpiredRefreshTokenFails(t *testing.T) {
	s := newTestService(t)
	s.now = func() time.Time { return time.Now().Add(-200 * time.Hour) }
	pair, err := s.IssuePair("admin")
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	// Restore clock so RevokeRefreshToken sees an expired token.
	s.now = time.Now
	if err := s.RevokeRefreshToken(pair.RefreshToken); !errors.Is(err, ErrInvalidToken) {
		t.Fatalf("revoke expired: err = %v, want ErrInvalidToken", err)
	}
}
