// Package crypt implements sha512-crypt ($6$), the password hash format
// rendered into the atmoz/sftp users.conf file.
//
// Why this exists (STREAM-2 crypt decision, see api/README.md):
//
//	atmoz/sftp feeds users.conf entries to `usermod -p`, which accepts any
//	hash glibc crypt(3) can verify — including sha512-crypt ($6$). The
//	algorithm is fully specified (Ulrich Drepper, "SHA-crypt") and produces
//	output identical to `openssl passwd -6 <password>`. Implementing it
//	in-project (sha512 from the Go stdlib + crypto/rand, ~100 lines) avoids
//	adding ANY new module dependency — go.sum had no crypt package and the
//	build must stay offline-reproducible.
//
// The bcrypt hash stored in the SQLite DB is a DIFFERENT credential used
// only for API-level validation; it is never rendered into users.conf.
package crypt

import (
	"crypto/rand"
	"crypto/sha512"
	"crypto/subtle"
	"fmt"
	"strings"
)

// magic is the sha512-crypt identifier ($6$ per glibc crypt(3)).
const magic = "$6$"

// defaultRounds matches glibc crypt's default (and `openssl passwd -6`).
const defaultRounds = 5000

// alphabet is the crypt(3) base-64 alphabet (NOT standard base64).
const alphabet = "./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// Hash returns the sha512-crypt hash of password with a random 16-char
// salt, format: $6$<salt>$<digest>. Output is byte-compatible with
// `openssl passwd -6 <password>`.
func Hash(password string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("crypt: generate salt: %w", err)
	}
	for i := range salt {
		salt[i] = alphabet[int(salt[i])%len(alphabet)]
	}
	return HashWithSalt(password, string(salt)), nil
}

// HashWithSalt returns the sha512-crypt hash of password for the given
// salt (<= 16 chars, longer salts are truncated per the spec). Deterministic:
// the same (password, salt) always yields the same hash — used in tests to
// compare against golden openssl output.
func HashWithSalt(password, salt string) string {
	if len(salt) > 16 {
		salt = salt[:16]
	}
	return magic + salt + "$" + digest(password, salt, defaultRounds)
}

// Verify reports whether password matches the given sha512-crypt hash.
// The salt and rounds are parsed from the hash itself. Uses a constant-time
// comparison on the digest segment.
func Verify(password, hashed string) bool {
	if !strings.HasPrefix(hashed, magic) {
		return false
	}
	rest := strings.TrimPrefix(hashed, magic)
	// Optional rounds=N$ prefix (we never emit it, but accept it).
	rounds := defaultRounds
	if strings.HasPrefix(rest, "rounds=") {
		idx := strings.IndexByte(rest, '$')
		if idx < 0 {
			return false
		}
		var r int
		if _, err := fmt.Sscanf(rest[:idx], "rounds=%d", &r); err != nil || r < 1000 || r > 999999999 {
			return false
		}
		rounds = r
		rest = rest[idx+1:]
	}
	idx := strings.IndexByte(rest, '$')
	if idx < 0 {
		return false
	}
	salt := rest[:idx]
	if len(salt) > 16 {
		salt = salt[:16]
	}
	computed := magic + rest[:idx] + "$" + digest(password, salt, rounds)
	return subtle.ConstantTimeCompare([]byte(computed), []byte(hashed)) == 1
}

// digest is the core sha512-crypt permutation, implementing Ulrich
// Drepper's SHA-crypt specification exactly as glibc's sha512-crypt.c
// does (verified byte-identical against `openssl passwd -6`).
func digest(password, salt string, rounds int) string {
	pw := []byte(password)
	s := []byte(salt)

	// Alternate sum: altSum = SHA512(pw + salt + pw).
	alt := sha512.New()
	alt.Write(pw)
	alt.Write(s)
	alt.Write(pw)
	altSum := alt.Sum(nil)

	// Intermediate result A:
	//   A = SHA512(pw + salt + altSum[:min(len(pw),64)])
	// then, walking the bits of len(pw) LSB-first: append altSum for a 1
	// bit, append pw for a 0 bit.
	a := sha512.New()
	a.Write(pw)
	a.Write(s)
	n := len(pw)
	if n > 64 {
		n = 64
	}
	a.Write(altSum[:n])
	for cnt := len(pw); cnt > 0; cnt >>= 1 {
		if cnt&1 == 1 {
			a.Write(altSum)
		} else {
			a.Write(pw)
		}
	}
	sum := a.Sum(nil)

	// P byte sequence: SHA512 of len(pw) copies of pw, repeated to
	// len(pw) bytes total.
	dp := sha512.New()
	for i := 0; i < len(pw); i++ {
		dp.Write(pw)
	}
	dpSum := dp.Sum(nil)
	pSeq := make([]byte, 0, len(pw))
	for len(pSeq) < len(pw) {
		pSeq = append(pSeq, dpSum...)
	}
	pSeq = pSeq[:len(pw)]

	// S byte sequence: SHA512 of (16 + A[0]) copies of salt, then the
	// digest TRUNCATED to the salt length (this is what glibc feeds into
	// the rounds loop — verified byte-identical against `openssl passwd -6`
	// and passlib's reference implementation).
	sLen := 16 + int(sum[0])
	ds := sha512.New()
	for i := 0; i < sLen; i++ {
		ds.Write(s)
	}
	sSeq := ds.Sum(nil)[:len(s)]

	// Main rounds loop (burns CPU cycles; default 5000).
	for i := 0; i < rounds; i++ {
		c := sha512.New()
		if i%2 == 1 {
			c.Write(pSeq)
		} else {
			c.Write(sum)
		}
		if i%3 != 0 {
			c.Write(sSeq)
		}
		if i%7 != 0 {
			c.Write(pSeq)
		}
		if i%2 == 1 {
			c.Write(sum)
		} else {
			c.Write(pSeq)
		}
		sum = c.Sum(nil)
	}

	// Final permutation of the 64-byte digest into the crypt base-64 string.
	return encode(sum)
}

// encode permutes and base-64 encodes the 64-byte sha512 digest into the
// 86-char crypt string, per the SHA-crypt specification: 21 groups of
// three digest bytes (b0,b1,b2) = (d[(42+22i)%63], d[(21+22i)%63],
// d[(22i)%63]) → 4 chars each, then a final group of the single byte
// d[63] → 2 chars (21*4 + 2 = 86).
func encode(d []byte) string {
	var sb strings.Builder
	sb.Grow(86)

	for i := 0; i < 21; i++ {
		b0 := d[(42+22*i)%63]
		b1 := d[(21+22*i)%63]
		b2 := d[(22*i)%63]
		sb.WriteByte(alphabet[b0&0x3f])
		sb.WriteByte(alphabet[((b0>>6)|(b1<<2))&0x3f])
		sb.WriteByte(alphabet[((b1>>4)|(b2<<4))&0x3f])
		sb.WriteByte(alphabet[(b2>>2)&0x3f])
	}
	// Final group: the remaining digest byte → 2 chars.
	last := d[63]
	sb.WriteByte(alphabet[last&0x3f])
	sb.WriteByte(alphabet[(last>>6)&0x3f])

	return sb.String()
}
