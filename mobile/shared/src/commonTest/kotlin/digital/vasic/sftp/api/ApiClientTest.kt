/**
 * ApiClient unit tests — Ktor MockEngine (fakes permitted ONLY in unit
 * tests per §11.4.27; integration coverage runs against the real server).
 *
 * Covered (anti-bluff: each test asserts observable behaviour):
 *  1. login persists tokens and parses the wire TokenResponse shape.
 *  2. 401 on an authed call triggers exactly one refresh + retry, and the
 *     retry uses the NEW access token.
 *  3. public-permission request WITHOUT acknowledgement serialises
 *     public_acknowledged=false (server would 422 it); the client-side
 *     draft validator blocks it before any request is made.
 *  4. public-permission request WITH acknowledgement serialises
 *     public_acknowledged=true and the request reaches the server.
 *  5. error envelope {code,error} decodes into ApiException.
 *  6. base URL normalisation appends /api/v1 exactly once.
 */
package digital.vasic.sftp.api

import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** In-memory TokenStore for unit tests (fake — unit-test scope only). */
private class FakeTokenStorage : TokenStore {
    private var tokens: StoredTokens? = null
    override suspend fun save(tokens: StoredTokens?) {
        this.tokens = tokens
    }

    override suspend fun load(): StoredTokens? = tokens
}

private fun jsonHeaders() = headersOf(HttpHeaders.ContentType, "application/json")

class ApiClientTest {

    @Test
    fun loginParsesTokensAndPersistsThem() = runTest {
        val storage = FakeTokenStorage()
        val engine = MockEngine { request ->
            assertEquals("/api/v1/auth/login", request.url.encodedPath)
            respond(
                """{"access_token":"A1","refresh_token":"R1","token_type":"Bearer","expires_in":900}""",
                HttpStatusCode.OK,
                jsonHeaders(),
            )
        }
        val client = ApiClient("http://server:7722", storage, engine)

        val tokens = client.login("admin", "s3cret")

        assertEquals("A1", tokens.access_token)
        assertEquals("R1", tokens.refresh_token)
        assertEquals(900, tokens.expires_in)
        assertEquals(StoredTokens("A1", "R1"), storage.load())
    }

    @Test
    fun authedCallRefreshesOnceOn401AndRetriesWithNewToken() = runTest {
        val storage = FakeTokenStorage()
        storage.save(StoredTokens("OLD_ACCESS", "REFRESH_1"))
        val seenAuthHeaders = mutableListOf<String>()
        var refreshCalls = 0
        val engine = MockEngine { request ->
            when (request.url.encodedPath) {
                "/api/v1/auth/refresh" -> {
                    refreshCalls++
                    respond(
                        """{"access_token":"NEW_ACCESS","refresh_token":"REFRESH_2","token_type":"Bearer","expires_in":900}""",
                        HttpStatusCode.OK,
                        jsonHeaders(),
                    )
                }

                "/api/v1/accounts" -> {
                    seenAuthHeaders += request.headers[HttpHeaders.Authorization] ?: ""
                    if (request.headers[HttpHeaders.Authorization] == "Bearer OLD_ACCESS") {
                        respond(
                            """{"code":"unauthorized","error":"token expired"}""",
                            HttpStatusCode.Unauthorized,
                            jsonHeaders(),
                        )
                    } else {
                        respond("[]", HttpStatusCode.OK, jsonHeaders())
                    }
                }

                else -> error("unexpected path ${request.url.encodedPath}")
            }
        }
        val client = ApiClient("http://server:7722/api/v1", storage, engine)

        val accounts = client.listAccounts()

        assertEquals(0, accounts.size)
        assertEquals(1, refreshCalls)
        assertEquals(listOf("Bearer OLD_ACCESS", "Bearer NEW_ACCESS"), seenAuthHeaders)
        assertEquals(StoredTokens("NEW_ACCESS", "REFRESH_2"), storage.load())
    }

    @Test
    fun publicPermissionWithoutAckIsBlockedByClientGuard() = runTest {
        val draft = AccountDraft(
            username = "pubuser",
            password = "pw123456",
            permission = Permission.PUBLIC,
            publicAcknowledged = false,
        )
        val error = AccountDraftValidator.validate(draft, isNew = true)
        assertNotNull(error)
        assertTrue(error.contains("acknowledgement", ignoreCase = true))

        // And the request object the guard would emit never claims an ack.
        val request = AccountDraftValidator.toRequest(draft)
        assertEquals(false, request.public_acknowledged)
        assertEquals("public", request.permission)
    }

    @Test
    fun publicPermissionWithAckSerializesAckTrueAndReachesServer() = runTest {
        var capturedBody = ""
        val storage = FakeTokenStorage()
        storage.save(StoredTokens("A", "R"))
        val engine = MockEngine { request ->
            capturedBody = (request.body as OutgoingContent.ByteArrayContent).bytes().decodeToString()
            respond(
                """{"username":"pubuser","permission":"public","home_dir":"/home/pubuser","enabled":true,"created_at":"2026-07-11T00:00:00Z","updated_at":"2026-07-11T00:00:00Z"}""",
                HttpStatusCode.OK,
                jsonHeaders(),
            )
        }
        val client = ApiClient("http://server:7722", storage, engine)

        val draft = AccountDraft(
            username = "pubuser",
            password = "pw123456",
            permission = Permission.PUBLIC,
            publicAcknowledged = true,
            homeDir = "/home/pubuser",
        )
        assertNull(AccountDraftValidator.validate(draft, isNew = true))
        val created = client.createAccount(AccountDraftValidator.toRequest(draft))

        assertEquals("pubuser", created.username)
        assertEquals("public", created.permission)
        val parsed = Json.parseToJsonElement(capturedBody)
        assertTrue(capturedBody.contains("\"public_acknowledged\":true"))
        assertTrue(parsed.toString().contains("pubuser"))
    }

    @Test
    fun errorEnvelopeDecodesIntoApiException() = runTest {
        val storage = FakeTokenStorage()
        storage.save(StoredTokens("A", "R"))
        val engine = MockEngine {
            respond(
                """{"code":"public_access_not_acknowledged","error":"public access requires acknowledgement"}""",
                HttpStatusCode.UnprocessableEntity,
                jsonHeaders(),
            )
        }
        val client = ApiClient("http://server:7722", storage, engine)

        val ex = assertFailsWith<ApiException> {
            client.createAccount(
                AccountRequest(username = "u", password = "p", permission = "public"),
            )
        }
        assertEquals(422, ex.statusCode)
        assertEquals("public_access_not_acknowledged", ex.code)
    }

    @Test
    fun baseUrlNormalizationAppendsApiV1ExactlyOnce() = runTest {
        val seenPaths = mutableListOf<String>()
        val engine = MockEngine { request ->
            seenPaths += request.url.encodedPath
            respond(
                """{"access_token":"A","refresh_token":"R","token_type":"Bearer","expires_in":1}""",
                HttpStatusCode.OK,
                jsonHeaders(),
            )
        }
        // with trailing slash and without /api/v1
        ApiClient("http://server:7722/", FakeTokenStorage(), engine).login("u", "p")
        // already including /api/v1
        ApiClient("http://server:7722/api/v1", FakeTokenStorage(), engine).login("u", "p")

        assertEquals(
            listOf("/api/v1/auth/login", "/api/v1/auth/login"),
            seenPaths,
        )
    }

    @Test
    fun responseParsingHandlesOptionalFields() = runTest {
        val storage = FakeTokenStorage()
        storage.save(StoredTokens("A", "R"))
        val engine = MockEngine {
            respond(
                """[{"username":"u1","permission":"read_only","uid":1001,"gid":1001,"home_dir":"/home/u1","enabled":true,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z"},{"username":"u2","permission":"read_write","home_dir":"/srv/u2","enabled":false,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z"}]""",
                HttpStatusCode.OK,
                jsonHeaders(),
            )
        }
        val client = ApiClient("http://server:7722", storage, engine)

        val accounts = client.listAccounts()

        assertEquals(2, accounts.size)
        assertEquals(1001, accounts[0].uid)
        assertEquals(null, accounts[1].uid)
        assertEquals(false, accounts[1].enabled)
        assertEquals("read_write", accounts[1].permission)
    }
}
