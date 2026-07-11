# PHASE4-FTP017: KMP Mobile Android Build Verification

| Field | Value |
|---|---|
| **Revision** | 1 |
| **Last modified** | 2026-07-12T00:05:00Z |
| **Task** | Verify KMP mobile Android build produces a valid APK |
| **Scope** | `mobile/` only |
| **Verdict** | **PASS** |
| **Evidence** | This report |

---

## 1. Toolchain Check

| Check | Result |
|---|---|
| `java -version` | OpenJDK 21.0.10 (Red_Hat-21.0.10.0.7-alt1) |
| `ANDROID_HOME` | `/home/milosvasic/Android/Sdk` — present, populated |
| SDK components | `build-tools/`, `platforms/`, `platform-tools/`, `ndk/`, `cmdline-tools/` — all present |
| Gradle wrapper | `mobile/gradlew` — version 8.11.1 |
| Kotlin | 2.1.20 |
| AGP | 8.7.3 |
| Compose Multiplatform | 1.7.3 |

**Verdict:** Toolchain fully available. No host-gating required.

---

## 2. Unit Tests (`:shared:testDebugUnitTest`)

**Command:** `./gradlew :shared:testDebugUnitTest --no-daemon`

**Result:** `BUILD SUCCESSFUL in 8s` — 17 actionable tasks, all up-to-date.

All shared-module unit tests (ApiClientTest with MockEngine, etc.) pass.

**Verdict:** PASS

---

## 3. Debug APK Build (`:androidApp:assembleDebug`)

**Command:** `./gradlew :androidApp:assembleDebug --no-daemon`

**Result:** `BUILD SUCCESSFUL in 19s` — 57 actionable tasks (8 executed, 49 up-to-date).

### Build issues encountered and fixed

| Issue | Fix |
|---|---|
| Missing `@mipmap/ic_launcher` resource | Created `res/drawable/ic_launcher_foreground.xml` (vector), `res/mipmap-anydpi-v26/ic_launcher.xml` (adaptive-icon), `res/values/colors.xml` (background color). All three are build-enabling placeholders — a proper branded adaptive icon per OpenDesign tokens (§11.4.162) should replace them before release. |
| `Cannot access class 'HttpClientEngine'` in `:androidApp:compileDebugKotlin` | Added `io.ktor:ktor-client-core:2.3.12` to androidApp dependencies. The shared module exposes `HttpClientEngine` in `ApiClient`'s public constructor, but `ktor-client-core` was declared `implementation` (not transitive). The androidApp needs the type on its compile classpath to call `ApiClient(engine = defaultHttpEngine())`. |

**Verdict:** PASS (after fixes above)

---

## 4. APK Verification

### Location
```
mobile/androidApp/build/outputs/apk/debug/androidApp-debug.apk
```

### Size
| Metric | Value |
|---|---|
| Compressed (on disk) | **11 MB** |
| Uncompressed (ZIP sum) | **27.6 MB** (407 files) |

### Validity
- **ZIP integrity:** `unzip -l` succeeds — APK is a valid ZIP archive.
- **Signature:** Signed with Android Debug keystore (`C=US, O=Android, CN=Android Debug`), SHA-256 `8c8658869a58abfb78dc399f3f7cbffd666354c1c29110cfb569f4b7c97278f5`.
- **`apksigner verify`:** PASS.

### APK metadata (aapt)
| Field | Value |
|---|---|
| Package | `digital.vasic.sftp.android.debug` |
| Version code | 1 |
| Version name | `0.1.0-dev-debug` |
| compileSdk | 34 (Android 14) |
| minSdk | 26 (Android 8.0) |
| targetSdk | 34 |
| Permissions | `android.permission.INTERNET` |
| App label | `SFTP Manager` |

### Content breakdown
| Category | Count/Size |
|---|---|
| DEX (compiled Kotlin) | 9 files, 25.7 MB uncompressed |
| Native libs (.so) | 4 files (arm64-v8a, armeabi-v7a, x86, x86_64), 37 KB — all `libandroidx.graphics.path.so` |
| Resources (res/) | ~380 items — animations, drawables, layouts, colors, strings, mipmap |
| Manifest | `AndroidManifest.xml` — parsed correctly by aapt |
| Kotlin metadata | `kotlin/kotlin.kotlin_builtins`, `kotlin/ranges/`, `kotlin/reflect/` |
| Total files | 407 |

---

## 5. Summary

| Step | Verdict | Evidence |
|---|---|---|
| 1. Toolchain | PASS | Java 21 + Android SDK present |
| 2. Unit tests | PASS | `:shared:testDebugUnitTest` — BUILD SUCCESSFUL |
| 3. APK build | PASS | `:androidApp:assembleDebug` — BUILD SUCCESSFUL |
| 4. APK valid | PASS | Valid ZIP, debug-signed, aapt parses correctly |
| 5. APK content | PASS | 407 files, DEX + native libs + resources + manifest |

**Overall verdict: PASS** — The KMP mobile Android project compiles, its unit tests pass, and it produces a valid, signed, correctly-structured debug APK.

### Honest notes (§11.4.6)
1. The launcher icon is a build-enabling placeholder (simple vector shapes). A proper branded adaptive icon per OpenDesign (§11.4.162) is needed before release.
2. iOS / HarmonyOS / AuroraOS targets are declared but not compilable on this Linux host (no Xcode, no DevEco Studio, no Aurora SDK) — honest host limitation, §11.4.3 SKIP-with-reason.
3. The APK has NOT been deployed to a device or emulator (out of scope for this phase — just verifying the build produces a valid artifact).

### Fixes applied (NOT committed, per task constraint)
1. `androidApp/src/main/res/drawable/ic_launcher_foreground.xml` — NEW FILE
2. `androidApp/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — NEW FILE
3. `androidApp/src/main/res/values/colors.xml` — NEW FILE
4. `androidApp/build.gradle.kts` — added `ktor-client-core` dependency

These files remain in the working tree as uncommitted changes. The project's `.gitignore` does not cover them, so they would be tracked on the next commit.
