/**
 * ApiClient — typed Ktor client for the SFTP management REST API.
 *
 * Contract (authoritative, api/internal/api/):
 *   POST /api/v1/auth/login    {username,password}      -> TokenResponse
 *   POST /api/v1/auth/refresh  {refresh_token}          -> TokenResponse
 *   GET  /api/v1/auth/me       (Bearer)                 -> MeResponse
 *   GET  /api/v1/accounts      (Bearer)                 -> AccountResponse[]
 *   POST /api/v1/accounts      (Bearer) AccountRequest  -> AccountResponse
 *   GET  /api/v1/accounts/:u   (Bearer)                 -> AccountResponse
 *   PUT  /api/v1/accounts/:u   (Bearer) AccountRequest  -> AccountResponse
 *   DELETE /api/v1/accounts/:u (Bearer)                 -> 200
 *   POST /api/v1/sync          (Bearer)                 -> SyncResponse
 *
 * Behaviour:
 *  - Bearer auth with automatic 401 -> refresh -> single retry.
 *  - Errors decoded from the single {code,error} envelope into ApiException.
 *  - The HTTP engine is injected, so tests drive the client with Ktor's
 *    MockEngine (no real network in unit tests — fakes allowed ONLY in
 *    unit tests per §11.4.27; integration runs against the real server).
 */
package digital.vasic.sftp.api

import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.delete
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.request.post
import io.ktor.client.request.put
import io.ktor.client.request.setBody
import io.ktor.client.statement.HttpResponse
import io.ktor.client.statement.bodyAsText
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.serialization.kotlinx.json.json
import kotlinx.serialization.json.Json

/** Typed API failure carrying the server's machine-readable code. */
class ApiException(
    val statusCode: Int,
    val code: String,
    message: String,
) : Exception(message)

class ApiClient(
    baseUrl: String,
    private val tokenStorage: TokenStore,
    engine: HttpClientEngine,
) {
    /** Normalised base URL: no trailing slash, includes the /api/v1 path. */
    private val base: String = baseUrl.trim().trimEnd('/').let { raw ->
        if (raw.endsWith("/api/v1")) raw else "$raw/api/v1"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }

    private val http = HttpClient(engine) {
        install(ContentNegotiation) { json(json) }
        expectSuccess = false // the {code,error} envelope is decoded manually
    }

    // ------------------------------------------------------------------
    // Public API
    // ------------------------------------------------------------------

    /** POST /auth/login — persists the returned tokens. */
    suspend fun login(username: String, password: String): TokenResponse {
        val tokens: TokenResponse = decode(
            http.post("$base/auth/login") {
                contentType(ContentType.Application.Json)
                setBody(LoginRequest(username, password))
            },
        )
        tokenStorage.save(StoredTokens(tokens.access_token, tokens.refresh_token))
        return tokens
    }

    /** POST /auth/refresh — persists rotated tokens. */
    suspend fun refresh(): TokenResponse {
        val current = tokenStorage.load()
            ?: throw ApiException(401, "unauthorized", "Not logged in")
        val tokens: TokenResponse = decode(
            http.post("$base/auth/refresh") {
                contentType(ContentType.Application.Json)
                setBody(RefreshRequest(current.refreshToken))
            },
        )
        tokenStorage.save(StoredTokens(tokens.access_token, tokens.refresh_token))
        return tokens
    }

    suspend fun logout() {
        tokenStorage.save(null)
    }

    suspend fun me(): MeResponse = authed { authHeader ->
        decode(http.get("$base/auth/me") { header(HttpHeaders.Authorization, authHeader) })
    }

    suspend fun listAccounts(): List<AccountResponse> = authed { authHeader ->
        decode(http.get("$base/accounts") { header(HttpHeaders.Authorization, authHeader) })
    }

    suspend fun createAccount(request: AccountRequest): AccountResponse = authed { authHeader ->
        decode(
            http.post("$base/accounts") {
                header(HttpHeaders.Authorization, authHeader)
                contentType(ContentType.Application.Json)
                setBody(request)
            },
        )
    }

    suspend fun getAccount(username: String): AccountResponse = authed { authHeader ->
        decode(
            http.get("$base/accounts/${encodeURIComponent(username)}") {
                header(HttpHeaders.Authorization, authHeader)
            },
        )
    }

    suspend fun updateAccount(username: String, request: AccountRequest): AccountResponse =
        authed { authHeader ->
            decode(
                http.put("$base/accounts/${encodeURIComponent(username)}") {
                    header(HttpHeaders.Authorization, authHeader)
                    contentType(ContentType.Application.Json)
                    setBody(request)
                },
            )
        }

    suspend fun deleteAccount(username: String) {
        authed<Unit> { authHeader ->
            decode<Unit>(
                http.delete("$base/accounts/${encodeURIComponent(username)}") {
                    header(HttpHeaders.Authorization, authHeader)
                },
            )
        }
    }

    suspend fun sync(): SyncResponse = authed { authHeader ->
        decode(http.post("$base/sync") { header(HttpHeaders.Authorization, authHeader) })
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    /**
     * Run [block] with a freshly-read Bearer header; on a single 401 the
     * token is refreshed and the call retried exactly once. A second 401
     * surfaces as ApiException (the refresh itself failing also surfaces).
     */
    private suspend fun <T> authed(block: suspend (authHeader: String) -> T): T {
        suspend fun currentHeader(): String {
            val t = tokenStorage.load()
                ?: throw ApiException(401, "unauthorized", "Not logged in")
            return "Bearer ${t.accessToken}"
        }
        return try {
            block(currentHeader())
        } catch (e: ApiException) {
            if (e.statusCode == 401) {
                refresh()
                block(currentHeader())
            } else {
                throw e
            }
        }
    }

    /** Decode a response body as [T] or throw ApiException from the envelope. */
    private suspend inline fun <reified T> decode(response: HttpResponse): T {
        if (response.status.value in 200..299) {
            if (T::class == Unit::class) {
                @Suppress("UNCHECKED_CAST")
                return Unit as T
            }
            return json.decodeFromString(response.bodyAsText())
        }
        val bodyText = response.bodyAsText()
        val envelope = runCatching { json.decodeFromString<ApiErrorBody>(bodyText) }.getOrNull()
        throw ApiException(
            statusCode = response.status.value,
            code = envelope?.code ?: "http_${response.status.value}",
            message = envelope?.error ?: "HTTP ${response.status.value}",
        )
    }
}

/** Minimal percent-encoding for path segments (multiplatform-safe). */
internal fun encodeURIComponent(value: String): String {
    val safe = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"
    val sb = StringBuilder()
    for (ch in value) {
        if (ch in safe) sb.append(ch)
        else sb.append('%').append(ch.code.toString(16).uppercase().padStart(2, '0'))
    }
    return sb.toString()
}
