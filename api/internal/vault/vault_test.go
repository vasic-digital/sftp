package vault

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func openTestVault(t *testing.T) (*Vault, string) {
	t.Helper()
	dir := filepath.Join(t.TempDir(), "vault")
	v, err := New(VaultConfig{DataDir: dir})
	if err != nil {
		t.Fatalf("new vault: %v", err)
	}
	return v, dir
}

func TestStoreAndLoadRoundTrip(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	want := "sha512crypt-hash-for-alice"
	if err := v.Store(ctx, "alice", want); err != nil {
		t.Fatalf("store: %v", err)
	}
	got, err := v.Load(ctx, "alice")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if got != want {
		t.Errorf("round-trip: got %q, want %q", got, want)
	}
}

func TestRestartPreservesData(t *testing.T) {
	ctx := context.Background()
	dir := filepath.Join(t.TempDir(), "vault")

	// First instance: store data.
	v1, err := New(VaultConfig{DataDir: dir})
	if err != nil {
		t.Fatalf("new vault 1: %v", err)
	}
	want := "sha512crypt-hash-for-bob"
	if err := v1.Store(ctx, "bob", want); err != nil {
		t.Fatalf("store: %v", err)
	}

	// "Restart": create a NEW vault instance with the SAME data dir and
	// master key. This simulates an API restart.
	v2, err := New(VaultConfig{DataDir: dir})
	if err != nil {
		t.Fatalf("new vault 2: %v", err)
	}
	got, err := v2.Load(ctx, "bob")
	if err != nil {
		t.Fatalf("load after restart: %v", err)
	}
	if got != want {
		t.Errorf("restart: got %q, want %q", got, want)
	}
}

func TestLoadNonExistentKey(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	_, err := v.Load(ctx, "ghost")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("load missing: err = %v, want ErrNotFound", err)
	}
}

func TestDelete(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "eve", "hash-for-eve"); err != nil {
		t.Fatalf("store: %v", err)
	}
	if err := v.Delete(ctx, "eve"); err != nil {
		t.Fatalf("delete: %v", err)
	}
	_, err := v.Load(ctx, "eve")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("load after delete: err = %v, want ErrNotFound", err)
	}
}

func TestDeleteNonExistent(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	err := v.Delete(ctx, "ghost")
	if !errors.Is(err, ErrNotFound) {
		t.Fatalf("delete missing: err = %v, want ErrNotFound", err)
	}
}

func TestStoreDifferentNonces(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	// Store the same value under two different keys and verify the
	// resulting ciphertext blobs differ (nonce randomness guarantees
	// this with overwhelming probability).
	const plaintext = "same-plaintext-value"

	for _, key := range []string{"alice", "bob"} {
		if err := v.Store(ctx, key, plaintext); err != nil {
			t.Fatalf("store %s: %v", key, err)
		}
	}

	// Read the raw blobs from disk.
	blobAlice := readRawBlob(t, v.cfg.DataDir, "alice")
	blobBob := readRawBlob(t, v.cfg.DataDir, "bob")

	// Ciphertexts (after the 12-byte nonce) MUST differ.
	if len(blobAlice) < 12 || len(blobBob) < 12 {
		t.Fatalf("blobs too short: alice=%d bob=%d", len(blobAlice), len(blobBob))
	}
	ctAlice := blobAlice[12:]
	ctBob := blobBob[12:]
	if bytes.Equal(ctAlice, ctBob) {
		t.Error("different keys produced identical ciphertexts — nonce reuse?")
	}
}

func TestMasterKeyFilePermissions(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "vault")
	v, err := New(VaultConfig{DataDir: dir})
	if err != nil {
		t.Fatalf("new vault: %v", err)
	}

	mkPath := v.cfg.MasterKeyPath
	info, err := os.Stat(mkPath)
	if err != nil {
		t.Fatalf("stat master key: %v", err)
	}
	perm := info.Mode().Perm()
	if perm != 0o600 {
		t.Errorf("master key permissions = %04o, want 0600", perm)
	}

	// Data directory permissions.
	infoDir, err := os.Stat(dir)
	if err != nil {
		t.Fatalf("stat data dir: %v", err)
	}
	if infoDir.Mode().Perm()&0o077 != 0 {
		t.Errorf("data dir permissions = %04o, want no group/other access", infoDir.Mode().Perm())
	}
}

func TestEntryFilePermissions(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "perms", "test"); err != nil {
		t.Fatalf("store: %v", err)
	}

	// The entry file must be readable by owner only.
	ep := entryPath(v.cfg.DataDir, "perms")
	info, err := os.Stat(ep)
	if err != nil {
		t.Fatalf("stat entry: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("entry file permissions = %04o, want 0600", info.Mode().Perm())
	}
}

func TestTamperedBlobRejected(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "tamper", "secret-value"); err != nil {
		t.Fatalf("store: %v", err)
	}

	// Corrupt the blob by flipping a byte in the ciphertext portion.
	ep := entryPath(v.cfg.DataDir, "tamper")
	data, err := os.ReadFile(ep)
	if err != nil {
		t.Fatalf("read entry: %v", err)
	}
	if len(data) >= 13 {
		data[13] ^= 0x01 // flip one bit after the 12-byte nonce
	}
	if err := os.WriteFile(ep, data, 0o600); err != nil {
		t.Fatalf("write corrupt blob: %v", err)
	}

	_, err = v.Load(ctx, "tamper")
	if err == nil {
		t.Fatal("load corrupted blob: expected error, got nil")
	}
}

func TestStoreEmptyValue(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "empty", ""); err != nil {
		t.Fatalf("store empty: %v", err)
	}
	got, err := v.Load(ctx, "empty")
	if err != nil {
		t.Fatalf("load empty: %v", err)
	}
	if got != "" {
		t.Errorf("empty round-trip: got %q, want \"\"", got)
	}
}

func TestStoreEmptyKey(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "", "value"); err == nil {
		t.Error("store empty key: expected error, got nil")
	}
	if _, err := v.Load(ctx, ""); err == nil {
		t.Error("load empty key: expected error, got nil")
	}
	if err := v.Delete(ctx, ""); err == nil {
		t.Error("delete empty key: expected error, got nil")
	}
}

func TestStoreOverwrite(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	if err := v.Store(ctx, "key", "original"); err != nil {
		t.Fatalf("store 1: %v", err)
	}
	if err := v.Store(ctx, "key", "updated"); err != nil {
		t.Fatalf("store 2: %v", err)
	}
	got, err := v.Load(ctx, "key")
	if err != nil {
		t.Fatalf("load: %v", err)
	}
	if got != "updated" {
		t.Errorf("overwrite: got %q, want %q", got, "updated")
	}
}

func TestRotateKeyRoundTrip(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	// Store several entries before rotation.
	entries := map[string]string{
		"alice":   "hash-for-alice",
		"bob":     "hash-for-bob",
		"charlie": "hash-for-charlie",
	}
	for k, val := range entries {
		if err := v.Store(ctx, k, val); err != nil {
			t.Fatalf("store %s: %v", k, err)
		}
	}

	// Rotate the master key.
	if err := v.RotateKey(); err != nil {
		t.Fatalf("rotate: %v", err)
	}

	// Every entry must still be readable and return the original value.
	for k, want := range entries {
		got, err := v.Load(ctx, k)
		if err != nil {
			t.Errorf("load %s after rotate: %v", k, err)
			continue
		}
		if got != want {
			t.Errorf("rotate: %s: got %q, want %q", k, got, want)
		}
	}
}

func TestRotateKeyOldKeyFailsDecryption(t *testing.T) {
	ctx := context.Background()
	dir := filepath.Join(t.TempDir(), "vault")
	v, err := New(VaultConfig{DataDir: dir})
	if err != nil {
		t.Fatalf("new vault: %v", err)
	}

	const testKey = "alice"
	const testVal = "secret-for-alice"
	if err := v.Store(ctx, testKey, testVal); err != nil {
		t.Fatalf("store: %v", err)
	}

	// Snapshot the OLD master key bytes BEFORE rotation so we can prove it
	// stops working afterwards.
	oldKeyHex, err := os.ReadFile(v.cfg.MasterKeyPath)
	if err != nil {
		t.Fatalf("read old master key: %v", err)
	}
	oldKey := make([]byte, hexDecodedLen(len(oldKeyHex)))
	n, decErr := hexDecode(oldKey, oldKeyHex)
	if decErr != nil || n != 32 {
		t.Fatalf("decode old master key: n=%d err=%v", n, decErr)
	}
	oldKey = oldKey[:n]

	if err := v.RotateKey(); err != nil {
		t.Fatalf("rotate: %v", err)
	}

	// Load through the vault still works (new key is active).
	got, err := v.Load(ctx, testKey)
	if err != nil {
		t.Fatalf("load with new key: %v", err)
	}
	if got != testVal {
		t.Fatalf("new key load: got %q, want %q", got, testVal)
	}

	// Now manually try to decrypt the re-encrypted blob with the OLD key.
	// GCM authentication MUST fail — proving the entry was genuinely
	// re-encrypted with the new key.
	raw, err := os.ReadFile(entryPath(dir, testKey))
	if err != nil {
		t.Fatalf("read raw entry: %v", err)
	}
	oldBlock, err := aes.NewCipher(oldKey)
	if err != nil {
		t.Fatalf("old cipher: %v", err)
	}
	oldGCM, err := cipher.NewGCM(oldBlock)
	if err != nil {
		t.Fatalf("old gcm: %v", err)
	}
	nonceSize := oldGCM.NonceSize()
	if len(raw) < nonceSize {
		t.Fatalf("raw entry too short: %d < %d", len(raw), nonceSize)
	}
	_, err = oldGCM.Open(nil, raw[:nonceSize], raw[nonceSize:], nil)
	if err == nil {
		t.Fatal("old key decrypted re-encrypted entry: rotation did NOT happen")
	}
	t.Logf("old key correctly rejected: %v", err)
}

func TestRotateKeyEmptyVault(t *testing.T) {
	v, _ := openTestVault(t)
	ctx := context.Background()

	// Rotate on a vault that has never stored anything.
	if err := v.RotateKey(); err != nil {
		t.Fatalf("rotate empty vault: %v", err)
	}

	// The vault must still be usable: store → load must work with the new key.
	const want = "data-after-empty-rotate"
	if err := v.Store(ctx, "post", want); err != nil {
		t.Fatalf("store after rotate: %v", err)
	}
	got, err := v.Load(ctx, "post")
	if err != nil {
		t.Fatalf("load after rotate: %v", err)
	}
	if got != want {
		t.Errorf("empty-rotate: got %q, want %q", got, want)
	}
}

func hexDecodedLen(hexLen int) int { return hexLen / 2 }

func readRawBlob(t *testing.T, dataDir, key string) []byte {
	t.Helper()
	data, err := os.ReadFile(entryPath(dataDir, key))
	if err != nil {
		t.Fatalf("read raw blob %s: %v", key, err)
	}
	return data
}
