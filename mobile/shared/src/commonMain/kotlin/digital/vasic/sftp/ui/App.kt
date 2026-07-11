/**
 * App — root composable + navigation state for the SFTP management client.
 *
 * Navigation is a small explicit state machine (sealed Screen class) driven
 * by [AppController]; no navigation library dependency. All screens render
 * through [SftpTheme] with BOTH light and dark token packs (§11.4.162) —
 * the active pack comes from the persisted ThemeMode (Settings screen) or
 * the system when ThemeMode.SYSTEM.
 */
package digital.vasic.sftp.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import digital.vasic.sftp.api.AccountResponse
import digital.vasic.sftp.api.ApiClient
import digital.vasic.sftp.api.TokenStorage
import digital.vasic.sftp.settings.SettingsSnapshot
import digital.vasic.sftp.settings.SettingsStore
import digital.vasic.sftp.settings.ThemeMode
import digital.vasic.sftp.theme.SftpTheme
import kotlinx.coroutines.launch

sealed class Screen {
    data object Login : Screen()
    data object Dashboard : Screen()
    data class AccountEditor(val existing: AccountResponse?) : Screen()
    data object Settings : Screen()
}

/**
 * Holds cross-screen state. Constructed once per process by the platform
 * entry point (androidApp MainActivity / iOS view controller).
 */
class AppController(
    val apiClient: ApiClient,
    val tokenStorage: TokenStorage,
    val settingsStore: SettingsStore,
    initialSettings: SettingsSnapshot,
) {
    var screen: Screen by mutableStateOf(Screen.Login)
    var themeMode: ThemeMode by mutableStateOf(initialSettings.themeMode)
    var serverUrl: String by mutableStateOf(initialSettings.serverUrl)
    var busy: Boolean by mutableStateOf(false)
    var error: String? by mutableStateOf(null)

    fun navigate(to: Screen) {
        error = null
        screen = to
    }
}

@Composable
fun App(controller: AppController) {
    val systemDark = isSystemInDarkTheme()
    val dark = when (controller.themeMode) {
        ThemeMode.SYSTEM -> systemDark
        ThemeMode.LIGHT -> false
        ThemeMode.DARK -> true
    }
    val scope = rememberCoroutineScope()

    SftpTheme(darkTheme = dark) {
        when (val s = controller.screen) {
            Screen.Login -> LoginScreen(
                controller = controller,
                onLoggedIn = { controller.navigate(Screen.Dashboard) },
                scope = scope,
            )

            Screen.Dashboard -> DashboardScreen(
                controller = controller,
                onEditAccount = { account -> controller.navigate(Screen.AccountEditor(account)) },
                onNewAccount = { controller.navigate(Screen.AccountEditor(null)) },
                onSettings = { controller.navigate(Screen.Settings) },
                onLoggedOut = { controller.navigate(Screen.Login) },
                scope = scope,
            )

            is Screen.AccountEditor -> AccountEditorScreen(
                controller = controller,
                existing = s.existing,
                onDone = { controller.navigate(Screen.Dashboard) },
                scope = scope,
            )

            Screen.Settings -> SettingsScreen(
                controller = controller,
                onDone = { controller.navigate(Screen.Dashboard) },
                scope = scope,
            )
        }
    }
}
