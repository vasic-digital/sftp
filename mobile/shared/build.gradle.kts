/**
 * shared/ — Kotlin Multiplatform library for the SFTP management clients.
 *
 * Source sets:
 *  - commonMain    : models, ApiClient (Ktor), i18n, theme, Compose screens,
 *                    expect TokenStorage.
 *  - androidMain   : actual TokenStorage (EncryptedSharedPreferences),
 *                    SettingsStore (SharedPreferences), Ktor Android engine.
 *  - iosMain       : actual TokenStorage (Keychain) + Darwin engine. Declared
 *                    but NOT compilable on this Linux host (no Xcode).
 *  - harmonyosMain / auroraosMain : scaffolding only (see README files) —
 *                    upstream KMP has no HarmonyOS/AuroraOS target; the source
 *                    sets carry the actual-implementation notes for the ports.
 *  - commonTest / androidUnitTest : MockEngine-based ApiClient tests.
 */
plugins {
    kotlin("multiplatform")
    kotlin("plugin.serialization")
    id("org.jetbrains.compose")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.android.library")
}

val ktorVersion = "2.3.12"
val serializationVersion = "1.8.0"
val coroutinesVersion = "1.10.1"

kotlin {
    androidTarget {
        publishLibraryVariants("release", "debug")
    }

    // iOS targets register ONLY on macOS hosts (Kotlin/Native restriction).
    // On this Linux host the iosMain source set is created manually below
    // so the sources exist and are reviewed, but nothing compiles them —
    // honest host limitation, §11.4.6 / §11.4.3 SKIP-with-reason.
    val isMacOs = System.getProperty("os.name").lowercase().contains("mac")
    if (isMacOs) {
        listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach { target ->
            target.binaries.framework {
                baseName = "shared"
                isStatic = true
            }
        }
    }

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(compose.runtime)
                implementation(compose.foundation)
                implementation(compose.material)
                implementation(compose.ui)
                implementation("io.ktor:ktor-client-core:$ktorVersion")
                implementation("io.ktor:ktor-client-content-negotiation:$ktorVersion")
                implementation("io.ktor:ktor-serialization-kotlinx-json:$ktorVersion")
                implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:$serializationVersion")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:$coroutinesVersion")
            }
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation("io.ktor:ktor-client-mock:$ktorVersion")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$coroutinesVersion")
            }
        }
        val androidMain by getting {
            dependencies {
                implementation("io.ktor:ktor-client-android:$ktorVersion")
                implementation("androidx.security:security-crypto:1.1.0-alpha06")
                implementation("androidx.core:core-ktx:1.13.1")
            }
        }
        val androidUnitTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation("io.ktor:ktor-client-mock:$ktorVersion")
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:$coroutinesVersion")
            }
        }
        if (isMacOs) {
            val iosMain by getting {
                dependencies {
                    implementation("io.ktor:ktor-client-darwin:$ktorVersion")
                }
            }
        }
        // harmonyosMain / auroraosMain: created on disk as scaffolding
        // source sets with README notes; they are intentionally NOT declared
        // as compilable KMP targets (upstream Kotlin has no HarmonyOS /
        // AuroraOS backend — honest gap, §11.4.6).
    }
}

android {
    namespace = "digital.vasic.sftp.shared"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        debug {
            val defaultUrl: String = providers.gradleProperty("SFTP_DEFAULT_SERVER_URL")
                .getOrElse("http://127.0.0.1:7722")
            buildConfigField("String", "DEFAULT_SERVER_URL", "\"$defaultUrl\"")
        }
        release {
            // Release carries no baked host: the Settings screen requires an
            // explicit server URL. Never a credential (§11.4.10).
            buildConfigField("String", "DEFAULT_SERVER_URL", "\"\"")
        }
    }
}
