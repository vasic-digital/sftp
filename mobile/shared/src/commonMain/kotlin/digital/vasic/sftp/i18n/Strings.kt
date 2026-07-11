/**
 * i18n — English-first string table for the shared UI layer.
 *
 * Single accessor t(StringKey) keeps screens free of hardcoded literals.
 * English is the authoritative language; additional locales are added as
 * parallel maps and selected by [locale] — the table is intentionally a
 * plain Kotlin map so it compiles on every target without resources.
 */
package digital.vasic.sftp.i18n

enum class StringKey {
    AppName,
    LoginTitle,
    LoginUsername,
    LoginPassword,
    LoginButton,
    LoginServerUrl,
    LoginErrorInvalid,
    LoginErrorNetwork,
    DashboardTitle,
    DashboardSync,
    DashboardSyncDone,
    DashboardEmpty,
    DashboardLogout,
    AccountNew,
    AccountEdit,
    AccountPermission,
    AccountHomeDir,
    AccountUid,
    AccountGid,
    AccountEnabled,
    AccountDelete,
    AccountDeleteConfirm,
    AccountSave,
    AccountPublicAck,
    AccountPublicWarning,
    PermReadOnly,
    PermReadWrite,
    PermPublic,
    SettingsTitle,
    SettingsTheme,
    SettingsThemeSystem,
    SettingsThemeLight,
    SettingsThemeDark,
    SettingsServerUrl,
    SettingsSave,
    ErrorPublicAckRequired,
    ErrorUsernameRequired,
    ErrorPasswordRequired,
    ErrorUidNumeric,
    ErrorGidNumeric,
    CreatedAt,
    UpdatedAt,
}

private val en: Map<StringKey, String> = mapOf(
    StringKey.AppName to "SFTP Manager",
    StringKey.LoginTitle to "Sign in",
    StringKey.LoginUsername to "Username",
    StringKey.LoginPassword to "Password",
    StringKey.LoginButton to "Sign in",
    StringKey.LoginServerUrl to "Server URL",
    StringKey.LoginErrorInvalid to "Invalid credentials",
    StringKey.LoginErrorNetwork to "Could not reach the server",
    StringKey.DashboardTitle to "Accounts",
    StringKey.DashboardSync to "Sync to SFTP server",
    StringKey.DashboardSyncDone to "users.conf synced",
    StringKey.DashboardEmpty to "No accounts yet",
    StringKey.DashboardLogout to "Sign out",
    StringKey.AccountNew to "New account",
    StringKey.AccountEdit to "Edit account",
    StringKey.AccountPermission to "Permission",
    StringKey.AccountHomeDir to "Home directory",
    StringKey.AccountUid to "UID (optional)",
    StringKey.AccountGid to "GID (optional)",
    StringKey.AccountEnabled to "Account enabled",
    StringKey.AccountDelete to "Delete account",
    StringKey.AccountDeleteConfirm to "Delete this account? This cannot be undone.",
    StringKey.AccountSave to "Save",
    StringKey.AccountPublicAck to "I acknowledge the risks of public access",
    StringKey.AccountPublicWarning to
        "Public access exposes files without authentication. It is never the default and requires your explicit acknowledgement.",
    StringKey.PermReadOnly to "Read only",
    StringKey.PermReadWrite to "Read / write",
    StringKey.PermPublic to "Public (no auth)",
    StringKey.SettingsTitle to "Settings",
    StringKey.SettingsTheme to "Theme",
    StringKey.SettingsThemeSystem to "System",
    StringKey.SettingsThemeLight to "Light",
    StringKey.SettingsThemeDark to "Dark",
    StringKey.SettingsServerUrl to "Server URL",
    StringKey.SettingsSave to "Save settings",
    StringKey.ErrorPublicAckRequired to "Public access requires explicit acknowledgement",
    StringKey.ErrorUsernameRequired to "Username is required",
    StringKey.ErrorPasswordRequired to "Password is required for new accounts",
    StringKey.ErrorUidNumeric to "UID must be a number",
    StringKey.ErrorGidNumeric to "GID must be a number",
    StringKey.CreatedAt to "Created",
    StringKey.UpdatedAt to "Updated",
)

/** Currently-selected locale table. English-first; extend with more maps. */
var locale: Map<StringKey, String> = en

/** Lookup a UI string. Falls back to English, then to the key name. */
fun t(key: StringKey): String = locale[key] ?: en[key] ?: key.name
