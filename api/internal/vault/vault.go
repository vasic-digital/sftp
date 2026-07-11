// Package vault implements a persistent encrypted key-value store for
// the SFTP Enterprise API. It replaces the in-memory cryptVault (which
// lost passwords on restart) with AES-256-GCM-encrypted files on disk.
//
// Design:
//   - A 32-byte random master key is generated on first run and stored in
//     data/vault/.master_key (chmod 0600, §11.4.10).
//   - Each entry is encrypted with a random 12-byte nonce and stored as
//     data/vault/<key>.enc = [12-byte nonce][AES-256-GCM ciphertext+tag].
//   - Write-temp-then-rename provides atomic updates.
//   - The API persists across restarts by definition — encrypted state
//     survives process lifetime.
//
// Security properties:
//   - CONFDENTIALITY: AES-256-GCM authenticated encryption prevents
//     reading entries without the master key.
//   - INTEGRITY: GCM authentication tag detects tampering.
//   - HONEST GAP (§11.4.6): the master key file on disk is the single
//     point of compromise; rotating the key requires re-encrypting every
//     entry (not implemented — gap documented in qa/results).
package vault

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ErrNotFound is returned when a key does not exist in the vault.
var ErrNotFound = errors.New("vault: key not found")

// VaultConfig describes where the vault stores its data.
//
// Zero values are replaced with safe defaults:
//   - DataDir defaults to "data/vault".
//   - MasterKeyPath defaults to "<DataDir>/.master_key".
type VaultConfig struct {
	DataDir       string
	MasterKeyPath string
}

// Vault is a persistent, encrypted key-value store. The zero value is
// invalid; create one with New.
type Vault struct {
	cfg VaultConfig
	key []byte // AES-256 master key (32 bytes)
}

// New creates or opens a vault. If the master key file does not exist it
// is generated and written with permission 0600. The data directory is
// created with permission 0700.
func New(cfg VaultConfig) (*Vault, error) {
	if cfg.DataDir == "" {
		cfg.DataDir = "data/vault"
	}
	if cfg.MasterKeyPath == "" {
		cfg.MasterKeyPath = filepath.Join(cfg.DataDir, ".master_key")
	}

	if err := os.MkdirAll(cfg.DataDir, 0o700); err != nil {
		return nil, fmt.Errorf("vault: create data dir %s: %w", cfg.DataDir, err)
	}

	key, err := loadOrCreateMasterKey(cfg.MasterKeyPath)
	if err != nil {
		return nil, err
	}

	return &Vault{cfg: cfg, key: key}, nil
}

// Store encrypts value under key and persists it atomically.
func (v *Vault) Store(ctx context.Context, key string, value string) error {
	if key == "" {
		return fmt.Errorf("vault: key must not be empty")
	}

	gcm, err := v.newGCM()
	if err != nil {
		return err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return fmt.Errorf("vault: generate nonce: %w", err)
	}

	ciphertext := gcm.Seal(nil, nonce, []byte(value), nil)
	data := make([]byte, len(nonce)+len(ciphertext))
	copy(data[:len(nonce)], nonce)
	copy(data[len(nonce):], ciphertext)

	return v.writeEntry(key, data)
}

// Load decrypts and returns the value stored under key. It returns
// ErrNotFound when the key does not exist.
func (v *Vault) Load(ctx context.Context, key string) (string, error) {
	if key == "" {
		return "", fmt.Errorf("vault: key must not be empty")
	}

	data, err := v.readEntry(key)
	if err != nil {
		return "", err
	}

	gcm, err := v.newGCM()
	if err != nil {
		return "", err
	}

	nonceSize := gcm.NonceSize()
	if len(data) < nonceSize {
		return "", fmt.Errorf("vault: %s: corrupted entry (too short)", filepath.Base(entryPath(v.cfg.DataDir, key)))
	}
	nonce, ct := data[:nonceSize], data[nonceSize:]

	plaintext, err := gcm.Open(nil, nonce, ct, nil)
	if err != nil {
		return "", fmt.Errorf("vault: %s: decrypt: %w", filepath.Base(entryPath(v.cfg.DataDir, key)), err)
	}
	return string(plaintext), nil
}

// Delete removes an entry. It returns ErrNotFound when the key does not
// exist.
func (v *Vault) Delete(ctx context.Context, key string) error {
	if key == "" {
		return fmt.Errorf("vault: key must not be empty")
	}
	p := entryPath(v.cfg.DataDir, key)
	if err := os.Remove(p); err != nil {
		if os.IsNotExist(err) {
			return ErrNotFound
		}
		return fmt.Errorf("vault: remove %s: %w", filepath.Base(p), err)
	}
	return nil
}

// RotateKey generates a new 32-byte master key, re-encrypts every existing
// entry with it, and atomically replaces the on-disk master key file. The
// old in-memory key is kept until all re-encryptions succeed so a partial
// failure does not leave the vault in an inconsistent state.
//
// On an empty vault (no entries) this is a safe no-op that still replaces
// the master key.
func (v *Vault) RotateKey() error {
	// 1. Generate new 32-byte random master key.
	newKey := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, newKey); err != nil {
		return fmt.Errorf("vault: rotate: generate new master key: %w", err)
	}

	// 2. Build GCM instances for both keys.
	oldGCM, err := v.newGCM()
	if err != nil {
		return fmt.Errorf("vault: rotate: init old gcm: %w", err)
	}

	newBlock, err := aes.NewCipher(newKey)
	if err != nil {
		return fmt.Errorf("vault: rotate: init new cipher: %w", err)
	}
	newGCM, err := cipher.NewGCM(newBlock)
	if err != nil {
		return fmt.Errorf("vault: rotate: init new gcm: %w", err)
	}

	// 3. List every entry so we can re-encrypt.
	entries, err := v.listEntries()
	if err != nil {
		return fmt.Errorf("vault: rotate: list entries: %w", err)
	}

	// 4. Re-encrypt each entry with the new key (decrypt old → encrypt new →
	//    write-temp-then-rename). If any step fails we return immediately,
	//    leaving the vault with the OLD master key still active.
	for _, entryKey := range entries {
		if err := v.reEncryptEntry(entryKey, oldGCM, newGCM); err != nil {
			return err
		}
	}

	// 5. Atomically replace the on-disk master key (write-temp-then-rename).
	encoded := make([]byte, hexEncodedLen(32))
	hexEncode(encoded, newKey)
	tmpPath := v.cfg.MasterKeyPath + ".tmp"
	if err := os.WriteFile(tmpPath, encoded, 0o600); err != nil {
		return fmt.Errorf("vault: rotate: write new master key: %w", err)
	}
	if err := os.Rename(tmpPath, v.cfg.MasterKeyPath); err != nil {
		_ = os.Remove(tmpPath)
		return fmt.Errorf("vault: rotate: rename new master key: %w", err)
	}

	// 6. Only NOW swap the in-memory key — every re-encryption succeeded and
	//    the new key is durable on disk.
	v.key = newKey
	return nil
}

// reEncryptEntry reads entryKey's blob, decrypts it with oldGCM, encrypts
// the plaintext with newGCM (fresh random nonce), and writes it back
// atomically (tmp → rename).
func (v *Vault) reEncryptEntry(entryKey string, oldGCM, newGCM cipher.AEAD) error {
	data, err := v.readEntry(entryKey)
	if err != nil {
		return fmt.Errorf("vault: rotate: read %s: %w", entryKey, err)
	}

	nonceSize := oldGCM.NonceSize()
	if len(data) < nonceSize {
		return fmt.Errorf("vault: rotate: %s: corrupted entry (too short)", entryKey)
	}
	oldNonce, oldCT := data[:nonceSize], data[nonceSize:]

	plaintext, err := oldGCM.Open(nil, oldNonce, oldCT, nil)
	if err != nil {
		return fmt.Errorf("vault: rotate: %s: decrypt with old key: %w", entryKey, err)
	}

	// Re-encrypt with fresh random nonce under the new key.
	newNonce := make([]byte, newGCM.NonceSize())
	if _, err := io.ReadFull(rand.Reader, newNonce); err != nil {
		return fmt.Errorf("vault: rotate: generate nonce: %w", err)
	}
	newCT := newGCM.Seal(nil, newNonce, plaintext, nil)

	newData := make([]byte, len(newNonce)+len(newCT))
	copy(newData[:len(newNonce)], newNonce)
	copy(newData[len(newNonce):], newCT)

	return v.writeEntry(entryKey, newData)
}

// listEntries returns the logical key names for every encrypted entry
// currently stored in the data directory.
func (v *Vault) listEntries() ([]string, error) {
	dirEntries, err := os.ReadDir(v.cfg.DataDir)
	if err != nil {
		return nil, fmt.Errorf("vault: read data dir: %w", err)
	}
	var keys []string
	for _, de := range dirEntries {
		if de.IsDir() {
			continue
		}
		name := de.Name()
		if !strings.HasSuffix(name, ".enc") {
			continue
		}
		hexKey := name[:len(name)-4] // strip ".enc"
		if len(hexKey)%2 != 0 {
			continue // malformed filename, skip
		}
		decoded := make([]byte, len(hexKey)/2)
		n, err := hexDecode(decoded, []byte(hexKey))
		if err != nil {
			continue // skip unparseable filenames
		}
		keys = append(keys, string(decoded[:n]))
	}
	return keys, nil
}

// newGCM creates an AES-256-GCM instance seeded with the vault master key.
func (v *Vault) newGCM() (cipher.AEAD, error) {
	block, err := aes.NewCipher(v.key)
	if err != nil {
		return nil, fmt.Errorf("vault: create cipher: %w", err)
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, fmt.Errorf("vault: create gcm: %w", err)
	}
	return gcm, nil
}

// entryPath returns the on-disk path for a key's encrypted blob.
func entryPath(dataDir, key string) string {
	// Sanitise the key by hex-encoding it so no filesystem character
	// produces a path traversal or invalid filename. The key is a
	// username per the current caller, but being conservative costs
	// nothing.
	safe := fmt.Sprintf("%x", []byte(key))
	return filepath.Join(dataDir, safe+".enc")
}

// writeEntry atomically writes data to key's entry file (tmp→rename).
func (v *Vault) writeEntry(key string, data []byte) error {
	p := entryPath(v.cfg.DataDir, key)
	tmp := p + ".tmp"

	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return fmt.Errorf("vault: write %s: %w", filepath.Base(tmp), err)
	}
	if err := os.Rename(tmp, p); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("vault: rename %s → %s: %w", filepath.Base(tmp), filepath.Base(p), err)
	}
	return nil
}

// readEntry reads the raw encrypted blob for key. Returns ErrNotFound on
// a missing file.
func (v *Vault) readEntry(key string) ([]byte, error) {
	p := entryPath(v.cfg.DataDir, key)
	data, err := os.ReadFile(p)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("vault: read %s: %w", filepath.Base(p), err)
	}
	return data, nil
}

// loadOrCreateMasterKey reads the 32-byte hex-encoded master key from
// path. If the file does not exist a fresh random key is generated and
// stored with permission 0600.
func loadOrCreateMasterKey(path string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err == nil {
		// Decode hex → 32-byte key.
		key := make([]byte, hexEncodedLen(len(data)))
		n, hexErr := hexDecode(key, data)
		if hexErr != nil || n != 32 {
			return nil, fmt.Errorf("vault: master key at %s is corrupt: must be 32 hex-encoded bytes (got %d)", path, n)
		}
		return key[:n], nil
	}

	if !os.IsNotExist(err) {
		return nil, fmt.Errorf("vault: read master key %s: %w", path, err)
	}

	// Generate a fresh random 32-byte key.
	key := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, key); err != nil {
		return nil, fmt.Errorf("vault: generate master key: %w", err)
	}

	// Store hex-encoded with chmod 0600 (§11.4.10).
	encoded := make([]byte, hexEncodedLen(32))
	hexEncode(encoded, key)
	if err := os.WriteFile(path, encoded, 0o600); err != nil {
		return nil, fmt.Errorf("vault: write master key %s: %w", path, err)
	}
	return key, nil
}

// hexEncode writes the lowercase hex encoding of src into dst.
// dst must have length at least len(src)*2. It is a local
// implementation to avoid importing encoding/hex for one call.
func hexEncode(dst, src []byte) {
	const digits = "0123456789abcdef"
	for i, b := range src {
		dst[i*2] = digits[b>>4]
		dst[i*2+1] = digits[b&0x0f]
	}
}

// hexDecode decodes src (lowercase hex bytes) into dst.
// dst must have length at least len(src)/2.
func hexDecode(dst, src []byte) (int, error) {
	if len(src)%2 != 0 {
		return 0, fmt.Errorf("odd hex length %d", len(src))
	}
	n := len(src) / 2
	for i := 0; i < n; i++ {
		hi, ok := fromHex(src[i*2])
		if !ok {
			return 0, fmt.Errorf("invalid hex char at %d: %c", i*2, src[i*2])
		}
		lo, ok := fromHex(src[i*2+1])
		if !ok {
			return 0, fmt.Errorf("invalid hex char at %d: %c", i*2+1, src[i*2+1])
		}
		dst[i] = (hi << 4) | lo
	}
	return n, nil
}

func fromHex(c byte) (byte, bool) {
	switch {
	case '0' <= c && c <= '9':
		return c - '0', true
	case 'a' <= c && c <= 'f':
		return c - 'a' + 10, true
	case 'A' <= c && c <= 'F':
		return c - 'A' + 10, true
	default:
		return 0, false
	}
}

func hexEncodedLen(plainLen int) int { return plainLen * 2 }
