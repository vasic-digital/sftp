/**
 * DashboardScreen — account list + sync-to-server action.
 *
 * Loads GET /accounts on entry; POST /sync renders users.conf on the
 * server and reports the rendered-account count from SyncResponse.
 */
package digital.vasic.sftp.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.Button
import androidx.compose.material.Card
import androidx.compose.material.CircularProgressIndicator
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedButton
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import digital.vasic.sftp.api.AccountResponse
import digital.vasic.sftp.api.ApiException
import digital.vasic.sftp.api.Permission
import digital.vasic.sftp.i18n.StringKey
import digital.vasic.sftp.i18n.t
import digital.vasic.sftp.theme.AppElevation
import digital.vasic.sftp.theme.AppSpacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@Composable
fun DashboardScreen(
    controller: AppController,
    onEditAccount: (AccountResponse) -> Unit,
    onNewAccount: () -> Unit,
    onSettings: () -> Unit,
    onLoggedOut: () -> Unit,
    scope: CoroutineScope,
) {
    var accounts by remember { mutableStateOf<List<AccountResponse>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var syncMessage by remember { mutableStateOf<String?>(null) }

    fun reload() {
        loading = true
        controller.error = null
        scope.launch {
            try {
                accounts = controller.apiClient.listAccounts()
            } catch (e: ApiException) {
                if (e.statusCode == 401) {
                    controller.apiClient.logout()
                    onLoggedOut()
                    return@launch
                }
                controller.error = e.message
            } catch (e: Exception) {
                controller.error = e.message
            } finally {
                loading = false
            }
        }
    }

    LaunchedEffect(Unit) { reload() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AppSpacing.s6),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(t(StringKey.DashboardTitle), style = MaterialTheme.typography.h5)
            Row {
                OutlinedButton(onClick = onSettings) { Text(t(StringKey.SettingsTitle)) }
                Spacer(Modifier.padding(AppSpacing.s1))
                OutlinedButton(
                    onClick = {
                        scope.launch {
                            controller.apiClient.logout()
                            onLoggedOut()
                        }
                    },
                ) { Text(t(StringKey.DashboardLogout)) }
            }
        }
        Spacer(Modifier.height(AppSpacing.s4))

        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(AppSpacing.s3)) {
            Button(onClick = onNewAccount) { Text(t(StringKey.AccountNew)) }
            OutlinedButton(
                enabled = !controller.busy,
                onClick = {
                    controller.busy = true
                    controller.error = null
                    syncMessage = null
                    scope.launch {
                        try {
                            val r = controller.apiClient.sync()
                            syncMessage = "${t(StringKey.DashboardSyncDone)} (${r.rendered_accounts})"
                        } catch (e: ApiException) {
                            controller.error = e.message
                        } catch (e: Exception) {
                            controller.error = e.message
                        } finally {
                            controller.busy = false
                        }
                    }
                },
            ) { Text(t(StringKey.DashboardSync)) }
        }
        Spacer(Modifier.height(AppSpacing.s4))

        controller.error?.let { msg ->
            Text(msg, color = MaterialTheme.colors.error, style = MaterialTheme.typography.body2)
            Spacer(Modifier.height(AppSpacing.s3))
        }
        syncMessage?.let { msg ->
            Text(msg, color = MaterialTheme.colors.primary, style = MaterialTheme.typography.body2)
            Spacer(Modifier.height(AppSpacing.s3))
        }

        if (loading) {
            CircularProgressIndicator()
        } else if (accounts.isEmpty()) {
            Text(t(StringKey.DashboardEmpty), style = MaterialTheme.typography.body1)
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(AppSpacing.s3)) {
                items(accounts, key = { it.username }) { account ->
                    AccountCard(account, onClick = { onEditAccount(account) })
                }
            }
        }
    }
}

@Composable
private fun AccountCard(account: AccountResponse, onClick: () -> Unit) {
    Card(
        elevation = AppElevation.cardResting,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Column(Modifier.padding(AppSpacing.s5)) {
            Text(account.username, style = MaterialTheme.typography.h6)
            Spacer(Modifier.height(AppSpacing.s1))
            val permLabel = when (Permission.fromWire(account.permission)) {
                Permission.READ_ONLY -> t(StringKey.PermReadOnly)
                Permission.READ_WRITE -> t(StringKey.PermReadWrite)
                Permission.PUBLIC -> t(StringKey.PermPublic)
            }
            Text(
                "$permLabel · ${if (account.enabled) "enabled" else "disabled"} · ${account.home_dir}",
                style = MaterialTheme.typography.body2,
                color = MaterialTheme.colors.onSurface.copy(alpha = 0.7f),
            )
        }
    }
}
