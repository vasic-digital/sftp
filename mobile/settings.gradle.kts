/**
 * SFTP enterprise management — mobile clients (Kotlin Multiplatform).
 *
 * Modules:
 *  - shared/      KMP library: data models, ApiClient (Ktor), i18n, secure
 *                 token storage (expect/actual), OpenDesign theme binding,
 *                 Compose screens (Login/Dashboard/AccountEditor/Settings).
 *  - androidApp/  Android application consuming `shared`.
 *
 * iOS / HarmonyOS / AuroraOS source-set scaffolding lives inside `shared`
 * (iosMain / harmonyosMain / auroraosMain) — see README files there for the
 * honest host-limitation notes (§11.4.6): this Linux host has no Xcode,
 * no DevEco Studio and no Aurora SDK, so only commonMain + Android compile
 * and test here.
 */
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
    }
}

rootProject.name = "sftp-mobile"

include(":shared")
include(":androidApp")
