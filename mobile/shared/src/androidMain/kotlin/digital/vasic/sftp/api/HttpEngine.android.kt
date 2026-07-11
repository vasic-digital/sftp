/** Android actual: Ktor Android engine (HttpURLConnection-backed). */
package digital.vasic.sftp.api

import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.engine.android.Android

actual fun defaultHttpEngine(): HttpClientEngine = Android.create()
