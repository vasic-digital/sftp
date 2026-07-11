/**
 * LoginScreen — server URL + username/password sign-in.
 *
 * The server URL defaults from the debug BuildConfig value (never a
 * credential, §11.4.10) and is editable; credentials go straight to
 * POST /auth/login and the returned tokens into secure TokenStorage.
 */
package digital.vasic.sftp.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.Button
import androidx.compose.material.CircularProgressIndicator
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import digital.vasic.sftp.api.ApiException
import digital.vasic.sftp.i18n.StringKey
import digital.vasic.sftp.i18n.t
import digital.vasic.sftp.theme.AppSpacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@Composable
fun LoginScreen(
    controller: AppController,
    onLoggedIn: () -> Unit,
    scope: CoroutineScope,
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var serverUrl by remember { mutableStateOf(controller.serverUrl) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AppSpacing.s6),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(t(StringKey.LoginTitle), style = MaterialTheme.typography.h4)
        Spacer(Modifier.height(AppSpacing.s6))

        OutlinedTextField(
            value = serverUrl,
            onValueChange = { serverUrl = it },
            label = { Text(t(StringKey.LoginServerUrl)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s3))

        OutlinedTextField(
            value = username,
            onValueChange = { username = it },
            label = { Text(t(StringKey.LoginUsername)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s3))

        OutlinedTextField(
            value = password,
            onValueChange = { password = it },
            label = { Text(t(StringKey.LoginPassword)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s5))

        controller.error?.let { msg ->
            Text(msg, color = MaterialTheme.colors.error, style = MaterialTheme.typography.body2)
            Spacer(Modifier.height(AppSpacing.s3))
        }

        Button(
            enabled = !controller.busy && username.isNotBlank() && password.isNotBlank(),
            onClick = {
                controller.busy = true
                controller.error = null
                scope.launch {
                    try {
                        controller.serverUrl = serverUrl.trim()
                        controller.settingsStore.saveServerUrl(controller.serverUrl)
                        controller.apiClient.login(username.trim(), password)
                        onLoggedIn()
                    } catch (e: ApiException) {
                        controller.error = when (e.code) {
                            "invalid_credentials" -> t(StringKey.LoginErrorInvalid)
                            else -> e.message ?: t(StringKey.LoginErrorNetwork)
                        }
                    } catch (e: Exception) {
                        controller.error = t(StringKey.LoginErrorNetwork)
                    } finally {
                        controller.busy = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (controller.busy) {
                CircularProgressIndicator(
                    color = MaterialTheme.colors.onPrimary,
                    strokeWidth = AppSpacing.s0_5,
                )
            } else {
                Text(t(StringKey.LoginButton))
            }
        }
    }
}
