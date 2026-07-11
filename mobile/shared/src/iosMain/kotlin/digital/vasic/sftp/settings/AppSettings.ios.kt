/**
 * iOS actual SettingsStore — NSUserDefaults for NON-SECRET values only
 * (server URL, theme mode). Credentials never pass through here
 * (§11.4.10); tokens live in the Keychain-backed TokenStorage.
 */
package digital.vasic.sftp.settings

import platform.Foundation.NSUserDefaults

actual class SettingsStore {

    private val defaults = NSUserDefaults.standardUserDefaults

    actual suspend fun load(): SettingsSnapshot = SettingsSnapshot(
        serverUrl = defaults.stringForKey(KEY_SERVER_URL) ?: "",
        themeMode = runCatching {
            ThemeMode.valueOf(defaults.stringForKey(KEY_THEME) ?: ThemeMode.SYSTEM.name)
        }.getOrDefault(ThemeMode.SYSTEM),
    )

    actual suspend fun saveServerUrl(url: String) {
        defaults.setObject(url, forKey = KEY_SERVER_URL)
    }

    actual suspend fun saveThemeMode(mode: ThemeMode) {
        defaults.setObject(mode.name, forKey = KEY_THEME)
    }

    companion object {
        private const val KEY_SERVER_URL = "server_url"
        private const val KEY_THEME = "theme_mode"
    }
}
