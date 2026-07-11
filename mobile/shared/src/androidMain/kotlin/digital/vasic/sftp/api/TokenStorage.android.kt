/**
 * Android actual TokenStorage — EncryptedSharedPreferences backed by the
 * AndroidKeyStore (AES-256-GCM values, AES-256-SIV keys). Tokens never
 * touch plain SharedPreferences or logs (§11.4.10).
 */
package digital.vasic.sftp.api

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual class TokenStorage(context: Context) : TokenStore {

    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "sftp_tokens",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    actual override suspend fun save(tokens: StoredTokens?) = withContext(Dispatchers.IO) {
        val editor = prefs.edit()
        if (tokens == null) {
            editor.clear()
        } else {
            editor.putString(KEY_ACCESS, tokens.accessToken)
            editor.putString(KEY_REFRESH, tokens.refreshToken)
        }
        editor.apply()
    }

    actual override suspend fun load(): StoredTokens? = withContext(Dispatchers.IO) {
        val access = prefs.getString(KEY_ACCESS, null) ?: return@withContext null
        val refresh = prefs.getString(KEY_REFRESH, null) ?: return@withContext null
        StoredTokens(access, refresh)
    }

    companion object {
        private const val KEY_ACCESS = "access_token"
        private const val KEY_REFRESH = "refresh_token"
    }
}
