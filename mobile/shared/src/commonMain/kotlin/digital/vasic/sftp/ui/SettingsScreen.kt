/**
 * SettingsScreen — server URL + theme mode (System/Light/Dark).
 *
 * Both light and dark token packs ship with the app (§11.4.162); the
 * selection persists via SettingsStore and applies immediately through
 * AppController.themeMode.
 */
package digital.vasic.sftp.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.Button
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedButton
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.RadioButton
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import digital.vasic.sftp.i18n.StringKey
import digital.vasic.sftp.i18n.t
import digital.vasic.sftp.settings.ThemeMode
import digital.vasic.sftp.theme.AppSpacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(
    controller: AppController,
    onDone: () -> Unit,
    scope: CoroutineScope,
) {
    var serverUrl by remember { mutableStateOf(controller.serverUrl) }
    var themeMode by remember { mutableStateOf(controller.themeMode) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AppSpacing.s6),
    ) {
        Text(t(StringKey.SettingsTitle), style = MaterialTheme.typography.h5)
        Spacer(Modifier.height(AppSpacing.s5))

        OutlinedTextField(
            value = serverUrl,
            onValueChange = { serverUrl = it },
            label = { Text(t(StringKey.SettingsServerUrl)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s6))

        Text(t(StringKey.SettingsTheme), style = MaterialTheme.typography.subtitle2)
        Spacer(Modifier.height(AppSpacing.s2))
        listOf(
            ThemeMode.SYSTEM to t(StringKey.SettingsThemeSystem),
            ThemeMode.LIGHT to t(StringKey.SettingsThemeLight),
            ThemeMode.DARK to t(StringKey.SettingsThemeDark),
        ).forEach { (mode, label) ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .selectable(selected = themeMode == mode, onClick = { themeMode = mode })
                    .padding(vertical = AppSpacing.s1),
            ) {
                RadioButton(selected = themeMode == mode, onClick = { themeMode = mode })
                Text(label, style = MaterialTheme.typography.body1)
            }
        }
        Spacer(Modifier.height(AppSpacing.s6))

        Row {
            Button(
                enabled = serverUrl.isNotBlank(),
                onClick = {
                    scope.launch {
                        controller.serverUrl = serverUrl.trim()
                        controller.themeMode = themeMode
                        controller.settingsStore.saveServerUrl(controller.serverUrl)
                        controller.settingsStore.saveThemeMode(themeMode)
                        onDone()
                    }
                },
            ) { Text(t(StringKey.SettingsSave)) }
            Spacer(Modifier.padding(AppSpacing.s2))
            OutlinedButton(onClick = onDone) { Text("Cancel") }
        }
    }
}
