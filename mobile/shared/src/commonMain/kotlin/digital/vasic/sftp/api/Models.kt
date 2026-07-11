/**
 * Wire models for the SFTP management REST API (base <server>/api/v1).
 *
 * Field names mirror the Go JSON tags in api/internal/api/ exactly —
 * these are the authoritative contract, never invent fields (§11.4.6).
 * The AccountResponse type MUST never carry a password: the server never
 * returns one, and the client must never accept one (§11.4.10).
 */
package digital.vasic.sftp.api

import digital.vasic.sftp.i18n.StringKey
import digital.vasic.sftp.i18n.t
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

@Serializable
data class LoginRequest(
    val username: String,
    val password: String,
)

@Serializable
data class RefreshRequest(
    val refresh_token: String,
)

/**
 * Token bundle returned by POST /auth/login and POST /auth/refresh.
 * `refresh_expires_in` is optional on the wire (present in the Go struct
 * but may be omitted by older servers), so it defaults to 0.
 */
@Serializable
data class TokenResponse(
    val access_token: String,
    val refresh_token: String,
    val token_type: String = "Bearer",
    val expires_in: Long = 0,
    val refresh_expires_in: Long = 0,
)

/** GET /auth/me response. */
@Serializable
data class MeResponse(
    val username: String,
    val expires_at: String = "",
)

// ---------------------------------------------------------------------------
// Accounts
// ---------------------------------------------------------------------------

/**
 * Account write request — POST/PUT /accounts[/:username].
 *
 * Server rule (handlers_accounts.go): permission=="public" is rejected with
 * HTTP 422 + code `public_access_not_acknowledged` unless
 * public_acknowledged===true. The client guard (AccountDraftValidator)
 * mirrors this so the app can never silently default to public access.
 */
@Serializable
data class AccountRequest(
    val username: String,
    val password: String? = null,
    val permission: String,
    val public_acknowledged: Boolean = false,
    val uid: Int? = null,
    val gid: Int? = null,
    val home_dir: String? = null,
    val enabled: Boolean? = null,
)

/** Account as returned by the server — NO password field, ever. */
@Serializable
data class AccountResponse(
    val username: String,
    val permission: String,
    val uid: Int? = null,
    val gid: Int? = null,
    val home_dir: String,
    val enabled: Boolean,
    val created_at: String = "",
    val updated_at: String = "",
)

/** POST /sync response. */
@Serializable
data class SyncResponse(
    val rendered_accounts: Int,
    val path: String = "",
)

/** Single JSON error envelope every failing endpoint returns. */
@Serializable
data class ApiErrorBody(
    val code: String,
    val error: String,
)

// ---------------------------------------------------------------------------
// Client-side value types
// ---------------------------------------------------------------------------

/** Closed permission vocabulary — mirrors the server-side allowed set. */
enum class Permission(val wire: String) {
    READ_ONLY("read_only"),
    READ_WRITE("read_write"),
    PUBLIC("public");

    companion object {
        fun fromWire(value: String): Permission =
            entries.firstOrNull { it.wire == value } ?: READ_ONLY
    }
}

/**
 * UI-side editable draft of an account. Validated by
 * [AccountDraftValidator] before it is allowed to become an
 * [AccountRequest] — the public-access acknowledgement guard lives there.
 */
data class AccountDraft(
    val username: String = "",
    val password: String = "",
    val permission: Permission = Permission.READ_ONLY,
    val publicAcknowledged: Boolean = false,
    val uid: String = "",
    val gid: String = "",
    val homeDir: String = "",
    val enabled: Boolean = true,
)

object AccountDraftValidator {
    /**
     * Validate a draft. Returns null when valid, or a human-readable error
     * string (English, from the i18n table) otherwise.
     *
     * GUARD (server rule): permission PUBLIC requires explicit
     * acknowledgement; the draft can never default to public.
     */
    fun validate(draft: AccountDraft, isNew: Boolean): String? {
        if (draft.username.isBlank()) return t(StringKey.ErrorUsernameRequired)
        if (isNew && draft.password.isBlank()) return t(StringKey.ErrorPasswordRequired)
        if (draft.permission == Permission.PUBLIC && !draft.publicAcknowledged) {
            return t(StringKey.ErrorPublicAckRequired)
        }
        if (draft.uid.isNotBlank() && draft.uid.toIntOrNull() == null) return t(StringKey.ErrorUidNumeric)
        if (draft.gid.isNotBlank() && draft.gid.toIntOrNull() == null) return t(StringKey.ErrorGidNumeric)
        return null
    }

    /** Convert a validated draft into a wire request. */
    fun toRequest(draft: AccountDraft): AccountRequest = AccountRequest(
        username = draft.username.trim(),
        password = draft.password.ifBlank { null },
        permission = draft.permission.wire,
        public_acknowledged = draft.permission == Permission.PUBLIC && draft.publicAcknowledged,
        uid = draft.uid.toIntOrNull(),
        gid = draft.gid.toIntOrNull(),
        home_dir = draft.homeDir.ifBlank { null },
        enabled = draft.enabled,
    )
}
