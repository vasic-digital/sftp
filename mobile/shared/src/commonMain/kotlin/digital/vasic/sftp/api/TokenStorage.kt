/**
 * Secure token storage — expect/actual per platform.
 *
 * Android: EncryptedSharedPreferences (AES-256, AndroidKeyStore-backed).
 * iOS:     Keychain (kSecClassGenericPassword).
 * HarmonyOS / AuroraOS: scaffolding notes in their source sets.
 *
 * Tokens are credentials (§11.4.10): they live ONLY in platform secure
 * storage, never in logs, never in plain SharedPreferences/NSUserDefaults.
 */
package digital.vasic.sftp.api

/** In-memory snapshot of the stored token pair. */
data class StoredTokens(
    val accessToken: String,
    val refreshToken: String,
)

/**
 * Platform-agnostic token persistence contract.
 *
 * Extracted so tests can supply a simple in-memory fake without needing
 * to subclass a final platform actual (Android requires Context, iOS is
 * also final). The expect/actual classes implement this interface.
 */
interface TokenStore {
    /** Persist both tokens atomically. Null clears both. */
    suspend fun save(tokens: StoredTokens?)

    /** Current tokens, or null when logged out. */
    suspend fun load(): StoredTokens?
}

expect class TokenStorage : TokenStore {
    override suspend fun save(tokens: StoredTokens?)

    override suspend fun load(): StoredTokens?
}
