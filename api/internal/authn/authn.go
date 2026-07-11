// Package authn implements super-admin authentication for the SFTP
// Enterprise API: bcrypt password verification and JWT access/refresh
// token issue + validation.
//
// Passwords are NEVER logged, echoed, or returned (§11.4.10). They flow
// request → bcrypt compare → discard.
package authn

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

// BcryptCost is the work factor for every password hash in this project.
// 12 exceeds the mandated floor of 12 (project rule: cost >= 12).
const BcryptCost = 12

// Token kinds embedded in the "kind" claim so a refresh token can never
// be used as an access token and vice versa.
const (
	kindAccess  = "access"
	kindRefresh = "refresh"
)

// Errors returned by this package. Callers match with errors.Is.
var (
	// ErrInvalidCredentials is returned on username/password mismatch.
	ErrInvalidCredentials = errors.New("authn: invalid credentials")
	// ErrInvalidToken is returned when a token fails signature/expiry/kind
	// validation.
	ErrInvalidToken = errors.New("authn: invalid token")
)

// HashPassword returns the bcrypt hash of a plaintext password at
// BcryptCost. The plaintext is never retained by this package.
func HashPassword(password string) (string, error) {
	if password == "" {
		return "", fmt.Errorf("authn: password must not be empty")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), BcryptCost)
	if err != nil {
		return "", fmt.Errorf("authn: hash password: %w", err)
	}
	return string(hash), nil
}

// VerifyPassword compares a bcrypt hash against a plaintext candidate.
// Returns nil on match, ErrInvalidCredentials otherwise — the same error
// for a wrong password and a malformed hash so callers cannot
// distinguish the two failure modes.
func VerifyPassword(hash, password string) error {
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)); err != nil {
		return ErrInvalidCredentials
	}
	return nil
}

// Claims is the validated JWT claim set for one authenticated principal.
type Claims struct {
	Subject   string
	Kind      string
	JTI       string
	ExpiresAt time.Time
	IssuedAt  time.Time
}

// TokenPair is one issued access + refresh token set.
type TokenPair struct {
	AccessToken     string
	RefreshToken    string
	AccessExpiresAt time.Time
	// RefreshExpiresAt is when the refresh token expires.
	RefreshExpiresAt time.Time
}

// Service issues and validates tokens for super-admin principals.
type Service struct {
	secret        []byte
	accessTTL     time.Duration
	refreshTTL    time.Duration
	issuer        string
	now           func() time.Time // overridable in tests
	signingMethod *jwt.SigningMethodHMAC
	revokedMu     sync.RWMutex
	revokedJTIs   map[string]time.Time // JTI → when it was revoked
}

// NewService creates a token service. secret must be non-empty; callers
// from main enforce the >= 32-char policy via config.Validate.
func NewService(secret string, accessTTL, refreshTTL time.Duration) (*Service, error) {
	if secret == "" {
		return nil, fmt.Errorf("authn: jwt secret must not be empty")
	}
	if accessTTL <= 0 || refreshTTL <= 0 {
		return nil, fmt.Errorf("authn: token TTLs must be positive")
	}
	if refreshTTL <= accessTTL {
		return nil, fmt.Errorf("authn: refresh TTL must exceed access TTL")
	}
	return &Service{
		secret:        []byte(secret),
		accessTTL:     accessTTL,
		refreshTTL:    refreshTTL,
		issuer:        "sftp-api",
		now:           time.Now,
		signingMethod: jwt.SigningMethodHS256,
		revokedJTIs:   make(map[string]time.Time),
	}, nil
}

// AccessTTL returns the configured access-token lifetime.
func (s *Service) AccessTTL() time.Duration { return s.accessTTL }

// RefreshTTL returns the configured refresh-token lifetime.
func (s *Service) RefreshTTL() time.Duration { return s.refreshTTL }

// IssuePair signs a fresh access + refresh token pair for subject.
func (s *Service) IssuePair(subject string) (*TokenPair, error) {
	if subject == "" {
		return nil, fmt.Errorf("authn: subject must not be empty")
	}
	access, accessExp, err := s.sign(subject, kindAccess, s.accessTTL)
	if err != nil {
		return nil, err
	}
	refresh, refreshExp, err := s.sign(subject, kindRefresh, s.refreshTTL)
	if err != nil {
		return nil, err
	}
	return &TokenPair{
		AccessToken:      access,
		RefreshToken:     refresh,
		AccessExpiresAt:  accessExp,
		RefreshExpiresAt: refreshExp,
	}, nil
}

// generateJTI returns a random 16-byte hex-encoded JWT ID.
func generateJTI() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("authn: generate jti: %w", err)
	}
	return hex.EncodeToString(b), nil
}

// sign produces one signed JWT of the given kind.
func (s *Service) sign(subject, kind string, ttl time.Duration) (string, time.Time, error) {
	jti, err := generateJTI()
	if err != nil {
		return "", time.Time{}, err
	}
	now := s.now().UTC()
	exp := now.Add(ttl)
	claims := jwt.MapClaims{
		"iss":  s.issuer,
		"sub":  subject,
		"jti":  jti,
		"kind": kind,
		"iat":  now.Unix(),
		"exp":  exp.Unix(),
	}
	tok := jwt.NewWithClaims(s.signingMethod, claims)
	signed, err := tok.SignedString(s.secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("authn: sign token: %w", err)
	}
	return signed, exp, nil
}

// ValidateAccess parses + validates an access token.
func (s *Service) ValidateAccess(tokenString string) (*Claims, error) {
	return s.validate(tokenString, kindAccess)
}

// ErrTokenRevoked is returned when a valid refresh token has been revoked.
var ErrTokenRevoked = errors.New("authn: token has been revoked")

// ValidateRefresh parses + validates a refresh token and checks it has not
// been revoked.
func (s *Service) ValidateRefresh(tokenString string) (*Claims, error) {
	claims, err := s.validate(tokenString, kindRefresh)
	if err != nil {
		return nil, err
	}
	if claims.JTI != "" && s.IsJTIRevoked(claims.JTI) {
		return nil, fmt.Errorf("%w: jti %s", ErrTokenRevoked, claims.JTI)
	}
	return claims, nil
}

// RevokeRefreshToken parses a refresh token and marks its JTI as revoked.
// Future calls to ValidateRefresh with this token will fail.
func (s *Service) RevokeRefreshToken(tokenString string) error {
	claims, err := s.validate(tokenString, kindRefresh)
	if err != nil {
		return err
	}
	if claims.JTI == "" {
		return fmt.Errorf("%w: token has no jti", ErrInvalidToken)
	}
	s.revokedMu.Lock()
	s.revokedJTIs[claims.JTI] = time.Now().UTC()
	s.revokedMu.Unlock()
	return nil
}

// IsJTIRevoked reports whether jti has been revoked.
func (s *Service) IsJTIRevoked(jti string) bool {
	s.revokedMu.RLock()
	defer s.revokedMu.RUnlock()
	_, ok := s.revokedJTIs[jti]
	return ok
}

// validate enforces signature, algorithm, issuer, expiry, and kind.
func (s *Service) validate(tokenString, wantKind string) (*Claims, error) {
	if tokenString == "" {
		return nil, fmt.Errorf("%w: empty token", ErrInvalidToken)
	}
	parsed, err := jwt.Parse(tokenString, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("%w: unexpected signing method %v", ErrInvalidToken, t.Header["alg"])
		}
		return s.secret, nil
	}, jwt.WithIssuer(s.issuer), jwt.WithExpirationRequired())
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrInvalidToken, err)
	}
	mapClaims, ok := parsed.Claims.(jwt.MapClaims)
	if !ok || !parsed.Valid {
		return nil, fmt.Errorf("%w: claims not valid", ErrInvalidToken)
	}

	subject, err := mapClaims.GetSubject()
	if err != nil || subject == "" {
		return nil, fmt.Errorf("%w: missing subject", ErrInvalidToken)
	}
	kind, _ := mapClaims["kind"].(string)
	if kind != wantKind {
		return nil, fmt.Errorf("%w: token kind %q is not %q", ErrInvalidToken, kind, wantKind)
	}
	jti, _ := mapClaims["jti"].(string)

	exp, err := mapClaims.GetExpirationTime()
	if err != nil {
		return nil, fmt.Errorf("%w: missing exp", ErrInvalidToken)
	}
	iat, err := mapClaims.GetIssuedAt()
	if err != nil {
		return nil, fmt.Errorf("%w: missing iat", ErrInvalidToken)
	}

	return &Claims{
		Subject:   subject,
		Kind:      kind,
		JTI:       jti,
		ExpiresAt: exp.Time,
		IssuedAt:  iat.Time,
	}, nil
}
