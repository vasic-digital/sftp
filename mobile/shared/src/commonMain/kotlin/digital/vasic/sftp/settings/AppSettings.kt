/**
 * AppSettings — non-secret runtime configuration (server URL, theme mode).
 *
 * expect/actual: Android uses plain SharedPreferences (non-secret values
 * only — credentials NEVER pass through here, §11.4.10); iOS actual uses
 * NSUserDefaults. HarmonyOS/AuroraOS scaffolding carries the port notes.
 */
package digital.vasic.sftp.settings

enum class ThemeMode { SYSTEM, LIGHT, DARK }

data class SettingsSnapshot(
    val serverUrl: String,
    val themeMode: ThemeMode,
)

expect class SettingsStore {
    suspend fun load(): SettingsSnapshot
    suspend fun saveServerUrl(url: String)
    suspend fun saveThemeMode(mode: ThemeMode)
}
