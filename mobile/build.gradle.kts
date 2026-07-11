/**
 * Root build script — version pins for the whole mobile tree.
 *
 * Pinned stable set (2026-07): Kotlin 2.1.20, Compose Multiplatform 1.7.3,
 * AGP 8.7.3, Ktor 2.3.12, kotlinx-serialization 1.8.0, kotlinx-coroutines
 * 1.10.1. Compose MP 1.7.x targets Material (2) widgets — matching the
 * existing theme binding (SftpTheme.kt uses androidx.compose.material).
 */
plugins {
    val kotlinVersion = "2.1.20"
    val composeVersion = "1.7.3"
    val agpVersion = "8.7.3"

    kotlin("multiplatform") version kotlinVersion apply false
    kotlin("android") version kotlinVersion apply false
    kotlin("plugin.serialization") version kotlinVersion apply false
    id("org.jetbrains.compose") version composeVersion apply false
    id("org.jetbrains.kotlin.plugin.compose") version kotlinVersion apply false
    id("com.android.library") version agpVersion apply false
    id("com.android.application") version agpVersion apply false
}

allprojects {
    // Marker so subprojects can read the root dir for shared config if needed.
    extra["mobileRoot"] = rootDir
}
