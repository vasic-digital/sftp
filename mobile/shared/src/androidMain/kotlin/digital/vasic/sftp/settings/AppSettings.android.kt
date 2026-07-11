/**
 * Android actual SettingsStore — plain SharedPreferences for NON-SECRET
 * values only (server URL, theme mode). Credentials never pass through
 * this store (§11.4.10); tokens live in TokenStorage.
 */
package digital.vasic.sftp.settings

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual class SettingsStore(context: Context, private val defaultServerUrl: String = "") {

    private val prefs = context.getSharedPreferences("sftp_settings", Context.MODE_PRIVATE)

    actual suspend fun load(): SettingsSnapshot = withContext(Dispatchers.IO) {
        SettingsSnapshot(
            serverUrl = prefs.getString(KEY_SERVER_URL, defaultServerUrl) ?: defaultServerUrl,
            themeMode = runCatching {
                ThemeMode.valueOf(prefs.getString(KEY_THEME, ThemeMode.SYSTEM.name)!!)
            }.getOrDefault(ThemeMode.SYSTEM),
        )
    }

    actual suspend fun saveServerUrl(url: String) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_SERVER_URL, url).apply()
    }

    actual suspend fun saveThemeMode(mode: ThemeMode) = withContext(Dispatchers.IO) {
        prefs.edit().putString(KEY_THEME, mode.name).apply()
    }

    companion object {
        private const val KEY_SERVER_URL = "server_url"
        private const val KEY_THEME = "theme_mode"
    }
}
