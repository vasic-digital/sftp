package crypt

import (
	"strings"
	"testing"
)

// golden vectors produced by `openssl passwd -6 -salt <salt> <password>`
// on OpenSSL 3.5.4 (captured 2026-07-11 as STREAM-2 evidence — see
// qa/results/STREAM-2-report.md). The in-project implementation MUST be
// byte-identical: atmoz/sftp's `usermod -p` accepts exactly this format.
var golden = []struct {
	password string
	salt     string
	want     string
}{
	{
		password: "password123",
		salt:     "abcd1234",
		want:     "$6$abcd1234$7NLbx1ZM8lie0XNZL1m5Rqsi7Wq9h90yfkd9m1254W0eGGVldajbioqTsEdrsMcke.LhZw3OxV4lNVxs9tny60",
	},
	{
		password: "hunter2",
		salt:     "zz",
		want:     "$6$zz$MFKplP0V/L6Uj1cQElKpERQCARYucMRoaLHZ1XunZAwd5y8156WPyuNRgod.sPSm8C.pZhN9.vrdW.MuF3r/61",
	},
	{
		password: "a",
		salt:     "x",
		want:     "$6$x$6Zqbz8j5rMHIeJ1ujjjFXuZXSa/VORj.fVUEQcJc.rjR9.wCKlhZuymRQLtIEzcxNmqwX/fRNvM45BbvFayY51",
	},
	{
		password: "The quick brown fox jumps over the lazy dog!",
		salt:     "saltysalt",
		want:     "$6$saltysalt$45FQqQzpZTSMTrM0WMyLB3PQttspnpD4QUPdXT7Cn3l5YZQXOmY.1z9qYcxdEegh/0qzynCF5AXyVD0WJGByn/",
	},
	{
		password: "this is a much longer password with spaces and 123 digits !@#",
		salt:     "NaCl",
		want:     "$6$NaCl$GsvHZ7je2rOF7Btp8v0CHr9vsS6K8JhGO3yjV5nVCJDlPfhXGQOAXGhd/I1dFYM94dTMm/XckDKbsy9NxAIEP/",
	},
}

func TestHashWithSaltMatchesOpenSSL(t *testing.T) {
	for _, v := range golden {
		got := HashWithSalt(v.password, v.salt)
		if got != v.want {
			t.Errorf("HashWithSalt(%q, %q):\n got  %q\n want %q",
				v.password, v.salt, got, v.want)
		}
	}
}

func TestHashProducesValidFormat(t *testing.T) {
	h1, err := Hash("secret")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if !strings.HasPrefix(h1, "$6$") {
		t.Errorf("prefix missing $6$: %q", h1)
	}
	parts := strings.Split(h1, "$")
	// ["", "6", salt, digest]
	if len(parts) != 4 {
		t.Fatalf("parts = %d, want 4: %q", len(parts), h1)
	}
	if len(parts[2]) != 16 {
		t.Errorf("salt len = %d, want 16", len(parts[2]))
	}
	if len(parts[3]) != 86 {
		t.Errorf("digest len = %d, want 86", len(parts[3]))
	}

	// Random salt: two hashes of the same password must differ.
	h2, err := Hash("secret")
	if err != nil {
		t.Fatalf("hash 2: %v", err)
	}
	if h1 == h2 {
		t.Errorf("two random-salt hashes are identical")
	}
}

func TestVerify(t *testing.T) {
	for _, v := range golden {
		if !Verify(v.password, v.want) {
			t.Errorf("Verify(%q, golden) = false, want true", v.password)
		}
		if Verify(v.password+"x", v.want) {
			t.Errorf("Verify(%q, golden) = true, want false", v.password+"x")
		}
	}
}

func TestVerifyRoundTrip(t *testing.T) {
	h, err := Hash("round-trip-password")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if !Verify("round-trip-password", h) {
		t.Errorf("round trip verify failed")
	}
}

func TestVerifyRejectsMalformed(t *testing.T) {
	bad := []string{
		"",
		"not-a-hash",
		"$2a$12$somebcrypthash",     // bcrypt, not sha512-crypt
		"$6$",                       // empty salt/digest
		"$6$salt",                   // missing digest segment
		"$6$rounds=abc$salt$digest", // non-numeric rounds
		"$6$rounds=10$salt$digest",  // rounds below spec floor
		"$1$salt$digest",            // md5-crypt — wrong scheme
	}
	for _, b := range bad {
		if Verify("x", b) {
			t.Errorf("Verify(x, %q) = true, want false", b)
		}
	}
}

func TestSaltTruncation(t *testing.T) {
	// Salts longer than 16 chars are truncated per the spec; the truncated
	// form must hash identically.
	long := HashWithSalt("pw", "abcdefghijklmnopTRUNCATED")
	short := HashWithSalt("pw", "abcdefghijklmnop")
	if long != short {
		t.Errorf("truncated-salt hash mismatch:\n long  %q\n short %q", long, short)
	}
}
