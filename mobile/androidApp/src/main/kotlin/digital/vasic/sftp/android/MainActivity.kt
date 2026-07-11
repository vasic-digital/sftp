/**
 * MainActivity — Android entry point wiring the shared KMP UI.
 *
 * Builds TokenStorage (EncryptedSharedPreferences), SettingsStore, and
 * ApiClient (Ktor Android engine) from platform context, then renders the
 * shared Compose App. The default server URL comes from the shared
 * module's debug BuildConfig — a host:port, never a credential
 * (§11.4.10).
 */
package digital.vasic.sftp.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.remember
import androidx.lifecycle.lifecycleScope
import digital.vasic.sftp.api.ApiClient
import digital.vasic.sftp.api.TokenStorage
import digital.vasic.sftp.api.defaultHttpEngine
import digital.vasic.sftp.settings.SettingsSnapshot
import digital.vasic.sftp.settings.SettingsStore
import digital.vasic.sftp.settings.ThemeMode
import digital.vasic.sftp.ui.App
import digital.vasic.sftp.ui.AppController
import digital.vasic.sftp.ui.Screen
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val tokenStorage = TokenStorage(applicationContext)
        val settingsStore = SettingsStore(
            applicationContext,
            defaultServerUrl = digital.vasic.sftp.shared.BuildConfig.DEFAULT_SERVER_URL,
        )
        val initialSettings = runBlocking { settingsStore.load() }
        val apiClient = ApiClient(
            baseUrl = initialSettings.serverUrl.ifBlank {
                digital.vasic.sftp.shared.BuildConfig.DEFAULT_SERVER_URL
            },
            tokenStorage = tokenStorage,
            engine = defaultHttpEngine(),
        )
        val controller = AppController(
            apiClient = apiClient,
            tokenStorage = tokenStorage,
            settingsStore = settingsStore,
            initialSettings = initialSettings,
        )

        // Already logged in? Skip the login screen.
        lifecycleScope.launch {
            if (tokenStorage.load() != null) controller.navigate(Screen.Dashboard)
        }

        setContent {
            remember { controller }
            App(controller)
        }
    }
}
