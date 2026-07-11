# STREAM-5: Mobile KMP Client Verification Report

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-11T21:15:00Z |
| **Stream** | STREAM-5 — Mobile KMP client verification |
| **Scope** | `mobile/` directory only |
| **Host** | Linux 6.12, JDK 21 (OpenJDK), Android SDK at `/home/milosvasic/Android/Sdk` |
| **Verdict** | **BUILD PASS, TESTS FAIL (code defect)** |

---

## 1. Toolchain Check

| Check | Result |
|---|---|
| `java -version` | `openjdk version "21.0.10" 2026-01-20` — PASS |
| `which gradle` | `/usr/bin/gradle` — system gradle available (wrapper used instead) |
| `$ANDROID_HOME` | `/home/milosvasic/Android/Sdk` (platforms, build-tools, ndk present) |
| `local.properties` | Present with `sdk.dir=/home/milosvasic/Android/Sdk` |
| `mobile/gradlew` | Already executable (`-rwxr-xr-x`, 8733 bytes) |

**No host-gating on toolchain** — JDK, Android SDK, and Gradle wrapper all available.

---

## 2. Build Result

### Command

```
cd mobile && ./gradlew :shared:compileDebugKotlinAndroid
```

### Exit code: **0**

### Captured output (excerpt)

```
BUILD SUCCESSFUL in 977ms
7 actionable tasks: 7 up-to-date
```

All source-compilation tasks completed without error. The KMP shared module compiles successfully for the Android target.

### Verification task target

`compileDebugKotlinAndroid` was used (the original task name `compileKotlinAndroid` is ambiguous — Gradle listed 5 candidates). This is the correct debug-variant compilation target per `mobile/README.md`.

---

## 3. Test Result

### Command

```
cd mobile && ./gradlew :shared:testDebugUnitTest
```

### Exit code: **1** — BUILD FAILED (compilation error in test source, not a runtime test failure)

### Captured error output

```
> Task :shared:compileDebugUnitTestKotlinAndroid FAILED
e: file:///.../shared/src/commonTest/kotlin/digital/vasic/sftp/api/ApiClientTest.kt:35:34 This type is final, so it cannot be extended.
e: file:///.../shared/src/commonTest/kotlin/digital/vasic/sftp/api/ApiClientTest.kt:35:46 No value passed for parameter 'context'.
e: file:///.../shared/src/commonTest/kotlin/digital/vasic/sftp/api/ApiClientTest.kt:37:5 'save' in 'TokenStorage' is final and cannot be overridden.
e: file:///.../shared/src/commonTest/kotlin/digital/vasic/sftp/api/ApiClientTest.kt:41:5 'load' in 'TokenStorage' is final and cannot be overridden.
```

### Root cause

The test file `ApiClientTest.kt` (line 35) declares:

```kotlin
private class FakeTokenStorage : TokenStorage() {
    override suspend fun save(tokens: StoredTokens?) { ... }
    override suspend fun load(): StoredTokens? = tokens
}
```

`TokenStorage` is declared as `expect class` in `commonMain` and resolved as:

```kotlin
actual class TokenStorage(context: Context) {    // androidMain
    actual suspend fun save(tokens: StoredTokens?) { ... }
    actual suspend fun load(): StoredTokens? { ... }
}
```

The Android `actual class TokenStorage` is **final** (no `open` modifier), has a **required `Context` constructor parameter**, and its `save`/`load` methods are **final** (`actual` methods in a non-open class are not overridable). The test's `FakeTokenStorage : TokenStorage()` cannot extend it and cannot pass the missing `context` argument.

**This is a genuine code defect** — the test was written against a design where `TokenStorage` was an interface or open class, but the Android actual implementation makes it final. The fix would require either:
- Making the `expect class TokenStorage` declaration `open` and adding a no-arg constructor, or
- Refactoring `TokenStorage` to an `interface` (so fakes can implement it in tests), or
- Restructuring the test to use a different mocking/faking strategy that does not require subclassing.

The test does not reach runtime — it fails at Kotlin compilation, so no test assertions were executed.

---

## 4. Source Set Inventory

| Source Set | .kt files | Status |
|---|---|---|
| `commonMain` | 13 | Full implementation (models, ApiClient, i18n, settings, theme, screens) |
| `androidMain` | 3 | Full actuals (TokenStorage, HttpEngine, SettingsStore) |
| `iosMain` | 3 | Full actuals (TokenStorage, HttpEngine, SettingsStore) — macOS-only compile |
| `harmonyosMain` | 0 | Scaffolding only — README.md documents host limitation |
| `auroraosMain` | 0 | Scaffolding only — README.md documents host limitation |
| `commonTest` | 1 | `ApiClientTest.kt` — 7 test methods (fails to compile, see above) |
| **Total** | **20** | |

---

## 5. Host-Limited Targets — Honest SKIP (§11.4.6 / §11.4.3)

### harmonyosMain

- **0 .kt files** — scaffolding only.
- `shared/src/harmonyosMain/README.md` documents: no upstream KMP target for HarmonyOS; DevEco Studio required (Windows/macOS only); port plan via ArkTS bridge or Huawei Kotlin/Native toolchain.
- **HONEST SKIP** — this host (Linux) cannot build or validate a HarmonyOS target.

### auroraosMain

- **0 .kt files** — scaffolding only.
- `shared/src/auroraosMain/README.md` documents: no upstream KMP target for AuroraOS; Aurora/Sailfish SDK required with OMP developer account; port plan via Qt/QML + native bridge.
- **HONEST SKIP** — this host lacks the Aurora SDK and OMP account.

### iosMain

- **3 .kt files** — sources complete and reviewable.
- `mobile/README.md` documents: iOS targets register only on macOS; guarded by `os.name` check in `shared/build.gradle.kts`.
- **HONEST SKIP** — this host (Linux) cannot compile Kotlin/Native iOS targets.

---

## 6. Summary

| Gate | Result | Notes |
|---|---|---|
| Toolchain (JDK + SDK + Gradle) | PASS | JDK 21, Android SDK, gradlew ready |
| Build (`compileDebugKotlinAndroid`) | **PASS** | All Kotlin sources compile for Android |
| Tests (`testDebugUnitTest`) | **FAIL** | `ApiClientTest.kt` fails Kotlin compilation — `TokenStorage` is final, test cannot subclass it |
| Source sets (4 targets) | PASS | All 4 present with README docs for host-limited targets |
| Host-limited docs | PASS | harmonyosMain, auroraosMain, and iosMain host limitations documented honestly |
| .kt file count | 20 total | 13 commonMain, 3 androidMain, 3 iosMain, 0 harmonyosMain, 0 auroraosMain, 1 commonTest |

### Overall Verdict: **FAIL**

The KMP scaffold **builds** successfully for Android, and all 4 target source sets exist with honest host-limitation documentation. However, the unit test compilation fails due to a **code defect**: `ApiClientTest.kt` attempts to subclass the Android `actual class TokenStorage`, which is a final class with a required `Context` constructor parameter. The test never reaches runtime — the failure is at the Kotlin compilation stage. This is a real defect that needs a source fix (either making `TokenStorage` open/interface-based, or restructuring the test's faking strategy).
