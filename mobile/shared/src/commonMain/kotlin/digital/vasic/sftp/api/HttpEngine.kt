/**
 * Platform HTTP engine factory — Android uses the Ktor Android engine
 * (HttpURLConnection), iOS uses Darwin (NSURLSession). Tests inject
 * MockEngine directly into ApiClient instead.
 */
package digital.vasic.sftp.api

import io.ktor.client.engine.HttpClientEngine

expect fun defaultHttpEngine(): HttpClientEngine
