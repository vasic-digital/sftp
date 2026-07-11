# mobile/ — Kotlin Multiplatform mobile clients (STREAM-5 / ATM-005)

Enterprise SFTP management clients: **Android** (buildable on this host),
**iOS** (sources complete, compiles on macOS), **HarmonyOS** and
**AuroraOS** (scaffolding + port notes; upstream Kotlin has no target).

## Layout

```
mobile/
├── settings.gradle.kts / build.gradle.kts / gradle.properties
├── shared/                      KMP library
│   ├── src/commonMain/kotlin/digital/vasic/sftp/
│   │   ├── api/                 Models, ApiClient (Ktor), TokenStorage (expect), HttpEngine (expect)
│   │   ├── i18n/                English-first string table (t())
│   │   ├── settings/            AppSettings / SettingsStore (expect)
│   │   ├── theme/               SftpTheme + Tokens (OpenDesign binding, light+dark) — pre-existing
│   │   └── ui/                  App (nav state machine) + Login/Dashboard/AccountEditor/Settings screens
│   ├── src/commonTest/...       ApiClientTest (Ktor MockEngine — 7 tests)
│   ├── src/androidMain/...      actual TokenStorage (EncryptedSharedPreferences), SettingsStore, Android engine
│   ├── src/iosMain/...          actual TokenStorage (Keychain), SettingsStore (NSUserDefaults), Darwin engine
│   ├── src/harmonyosMain/README.md   port plan (host-limited)
│   └── src/auroraosMain/README.md    port plan (host-limited)
└── androidApp/                  Android app (debug + release), MainActivity wiring
```

## API contract

Base URL `<server>/api/v1` (configurable in the Settings screen; debug
builds default from the `SFTP_DEFAULT_SERVER_URL` gradle property —
never a credential, §11.4.10). Endpoints consumed: `POST /auth/login`,
`POST /auth/refresh`, `GET /auth/me`, `GET|POST /accounts`,
`GET|PUT|DELETE /accounts/:username`, `POST /sync`. Bearer auth with
automatic **401 → refresh → single retry**. Errors decode the server's
`{code,error}` envelope into `ApiException`.

Public-access guard (mirrors the server's HTTP-422 rule):
`permission=public` is never preselected and requires an explicit
acknowledgement checkbox — the client-side `AccountDraftValidator`
blocks the save before any request; `public_acknowledged=true` is sent
only when both hold.

## Build (this host — Linux + Android SDK)

Prerequisites: JDK 17+ (host has 21), Android SDK at
`$ANDROID_HOME` (host: `/home/milosvasic/Android/Sdk`), `local.properties`
with `sdk.dir=...` (see `local.properties.template`).

```bash
cd mobile
./gradlew :shared:compileDebugKotlinAndroid   # shared lib for Android
./gradlew :shared:testDebugUnitTest           # ApiClient MockEngine unit tests
./gradlew :androidApp:assembleDebug           # debug APK
./gradlew :androidApp:assembleRelease         # release APK (unsigned)
```

## Host limitations (honest, §11.4.6 / §11.4.3 SKIP-with-reason)

- **iOS**: Kotlin/Native iOS targets register only on macOS; on this
  Linux host `iosMain` sources exist and are reviewable but are NOT
  compiled (guarded by an os.name check in `shared/build.gradle.kts`).
  Build on macOS with Xcode 15+.
- **HarmonyOS**: no upstream KMP target; needs DevEco Studio
  (Windows/macOS only) — see `shared/src/harmonyosMain/README.md`.
- **AuroraOS**: no upstream KMP target; needs the Aurora/Sailfish SDK
  with an OMP developer account — see `shared/src/auroraosMain/README.md`.
- The reusable KMP submodules (Auth/Security/Config/Storage/I18n/Network-
  KMP) are NOT part of the staged repo set — auth/http/storage/i18n are
  implemented in-project under `shared/` instead.

Owned by STREAM-5 per `docs/plans/master_implementation_plan.md`.
