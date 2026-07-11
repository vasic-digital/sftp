/** iOS actual: Ktor Darwin engine (NSURLSession-backed). */
package digital.vasic.sftp.api

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.darwin.Darwin

actual fun defaultHttpEngine(): HttpClientEngine = Darwin.create()
