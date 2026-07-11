/**
 * AccountEditorScreen — create/edit an SFTP account.
 *
 * Public-access GUARD (server rule mirrored client-side):
 *  - permission defaults to READ_ONLY; PUBLIC is never preselected.
 *  - selecting PUBLIC shows the risk warning and requires the explicit
 *    acknowledgement checkbox; saving without it is blocked client-side
 *    AND the server rejects with HTTP 422 (defense in depth).
 */
package digital.vasic.sftp.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.Button
import androidx.compose.material.Checkbox
import androidx.compose.material.DropdownMenu
import androidx.compose.material.DropdownMenuItem
import androidx.compose.material.MaterialTheme
import androidx.compose.material.OutlinedButton
import androidx.compose.material.OutlinedTextField
import androidx.compose.material.Switch
import androidx.compose.material.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import digital.vasic.sftp.api.AccountDraft
import digital.vasic.sftp.api.AccountDraftValidator
import digital.vasic.sftp.api.AccountResponse
import digital.vasic.sftp.api.ApiException
import digital.vasic.sftp.api.Permission
import digital.vasic.sftp.i18n.StringKey
import digital.vasic.sftp.i18n.t
import digital.vasic.sftp.theme.AppSpacing
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

@Composable
fun AccountEditorScreen(
    controller: AppController,
    existing: AccountResponse?,
    onDone: () -> Unit,
    scope: CoroutineScope,
) {
    val isNew = existing == null
    var draft by remember {
        mutableStateOf(
            if (existing != null) {
                AccountDraft(
                    username = existing.username,
                    password = "",
                    permission = Permission.fromWire(existing.permission),
                    publicAcknowledged = false,
                    uid = existing.uid?.toString() ?: "",
                    gid = existing.gid?.toString() ?: "",
                    homeDir = existing.home_dir,
                    enabled = existing.enabled,
                )
            } else {
                AccountDraft()
            },
        )
    }
    var permMenuOpen by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(AppSpacing.s6),
    ) {
        Text(
            if (isNew) t(StringKey.AccountNew) else t(StringKey.AccountEdit),
            style = MaterialTheme.typography.h5,
        )
        Spacer(Modifier.height(AppSpacing.s5))

        OutlinedTextField(
            value = draft.username,
            onValueChange = { draft = draft.copy(username = it) },
            label = { Text(t(StringKey.LoginUsername)) },
            singleLine = true,
            enabled = isNew,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s3))

        OutlinedTextField(
            value = draft.password,
            onValueChange = { draft = draft.copy(password = it) },
            label = { Text(t(StringKey.LoginPassword)) },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s3))

        Text(t(StringKey.AccountPermission), style = MaterialTheme.typography.subtitle2)
        Spacer(Modifier.height(AppSpacing.s1))
        OutlinedButton(onClick = { permMenuOpen = true }) {
            Text(
                when (draft.permission) {
                    Permission.READ_ONLY -> t(StringKey.PermReadOnly)
                    Permission.READ_WRITE -> t(StringKey.PermReadWrite)
                    Permission.PUBLIC -> t(StringKey.PermPublic)
                },
            )
        }
        DropdownMenu(expanded = permMenuOpen, onDismissRequest = { permMenuOpen = false }) {
            Permission.entries.forEach { perm ->
                DropdownMenuItem(
                    onClick = {
                        draft = draft.copy(
                            permission = perm,
                            // switching away from PUBLIC clears the acknowledgement
                            publicAcknowledged = if (perm == Permission.PUBLIC) draft.publicAcknowledged else false,
                        )
                        permMenuOpen = false
                    },
                ) {
                    Text(
                        when (perm) {
                            Permission.READ_ONLY -> t(StringKey.PermReadOnly)
                            Permission.READ_WRITE -> t(StringKey.PermReadWrite)
                            Permission.PUBLIC -> t(StringKey.PermPublic)
                        },
                    )
                }
            }
        }

        if (draft.permission == Permission.PUBLIC) {
            Spacer(Modifier.height(AppSpacing.s3))
            Text(
                t(StringKey.AccountPublicWarning),
                color = MaterialTheme.colors.error,
                style = MaterialTheme.typography.body2,
            )
            Spacer(Modifier.height(AppSpacing.s2))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(
                    checked = draft.publicAcknowledged,
                    onCheckedChange = { draft = draft.copy(publicAcknowledged = it) },
                )
                Text(t(StringKey.AccountPublicAck), style = MaterialTheme.typography.body2)
            }
        }
        Spacer(Modifier.height(AppSpacing.s3))

        OutlinedTextField(
            value = draft.homeDir,
            onValueChange = { draft = draft.copy(homeDir = it) },
            label = { Text(t(StringKey.AccountHomeDir)) },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(AppSpacing.s3))

        Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.s3)) {
            OutlinedTextField(
                value = draft.uid,
                onValueChange = { draft = draft.copy(uid = it) },
                label = { Text(t(StringKey.AccountUid)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
            OutlinedTextField(
                value = draft.gid,
                onValueChange = { draft = draft.copy(gid = it) },
                label = { Text(t(StringKey.AccountGid)) },
                singleLine = true,
                modifier = Modifier.weight(1f),
            )
        }
        Spacer(Modifier.height(AppSpacing.s3))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Switch(
                checked = draft.enabled,
                onCheckedChange = { draft = draft.copy(enabled = it) },
            )
            Spacer(Modifier.padding(AppSpacing.s1))
            Text(t(StringKey.AccountEnabled))
        }
        Spacer(Modifier.height(AppSpacing.s4))

        controller.error?.let { msg ->
            Text(msg, color = MaterialTheme.colors.error, style = MaterialTheme.typography.body2)
            Spacer(Modifier.height(AppSpacing.s3))
        }

        Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.s3)) {
            Button(
                enabled = !controller.busy,
                onClick = {
                    val validationError = AccountDraftValidator.validate(draft, isNew)
                    if (validationError != null) {
                        controller.error = validationError
                        return@Button
                    }
                    controller.busy = true
                    controller.error = null
                    scope.launch {
                        try {
                            val request = AccountDraftValidator.toRequest(draft)
                            if (isNew) controller.apiClient.createAccount(request)
                            else controller.apiClient.updateAccount(existing!!.username, request)
                            onDone()
                        } catch (e: ApiException) {
                            controller.error = e.message
                        } catch (e: Exception) {
                            controller.error = e.message
                        } finally {
                            controller.busy = false
                        }
                    }
                },
            ) { Text(t(StringKey.AccountSave)) }

            OutlinedButton(onClick = onDone) { Text("Cancel") }
        }

        if (!isNew) {
            Spacer(Modifier.height(AppSpacing.s8))
            if (!confirmDelete) {
                OutlinedButton(onClick = { confirmDelete = true }) {
                    Text(t(StringKey.AccountDelete), color = MaterialTheme.colors.error)
                }
            } else {
                Text(t(StringKey.AccountDeleteConfirm), style = MaterialTheme.typography.body2)
                Spacer(Modifier.height(AppSpacing.s2))
                Row(horizontalArrangement = Arrangement.spacedBy(AppSpacing.s3)) {
                    Button(
                        onClick = {
                            controller.busy = true
                            scope.launch {
                                try {
                                    controller.apiClient.deleteAccount(existing!!.username)
                                    onDone()
                                } catch (e: ApiException) {
                                    controller.error = e.message
                                } finally {
                                    controller.busy = false
                                    confirmDelete = false
                                }
                            }
                        },
                    ) { Text(t(StringKey.AccountDelete)) }
                    OutlinedButton(onClick = { confirmDelete = false }) { Text("Cancel") }
                }
            }
        }
    }
}
