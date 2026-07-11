# harmonyosMain — HarmonyOS port scaffolding (host-limited, §11.4.6 / §11.4.3 SKIP-with-reason)

## Status

**Scaffolding only — NOT compiled on this host.** Upstream Kotlin
Multiplatform (as of Kotlin 2.1.x / Compose Multiplatform 1.7.x) ships NO
HarmonyOS target backend. A HarmonyOS port is possible only via one of:

1. **Huawei's Kotlin/Native HarmonyOS toolchain** (DevEco Studio + the
   HarmonyOS NEXT Kotlin interop preview) — requires DevEco Studio, which
   is NOT available for Linux hosts (Windows/macOS only).
2. **ArkTS bridge** — reimplement the thin platform layer
   (TokenStorage actual → HarmonyOS `@ohos.security.asset` Asset Store;
   SettingsStore actual → `@ohos.data.preferences`; HTTP engine →
   `@ohos.net.http`) in ArkTS and bind it to the compiled commonMain
   artefacts.

## What the port must provide (when the toolchain is available)

- `actual class TokenStorage` — HarmonyOS Asset Store
  (`@ohos.security.asset`), which is the platform credential store
  (§11.4.10 — tokens never in plain preferences).
- `actual class SettingsStore` — `@ohos.data.preferences` for non-secret
  values only.
- `actual fun defaultHttpEngine()` — Ktor engine bound to
  `@ohos.net.http`, or a CIO engine if the HarmonyOS Kotlin/Native target
  supports posix sockets.

All business logic (models, ApiClient, i18n, theme, screens) is already
platform-neutral in commonMain and requires NO changes for the port —
only the three actuals above.

## Host limitation evidence

- This host: Linux 6.12, no DevEco Studio, no HarmonyOS SDK → the port
  cannot be built or validated here (honest SKIP-with-reason, §11.4.3).
- Action required: run the port on a Windows/macOS host with DevEco
  Studio 5.x and a HarmonyOS NEXT device/emulator.
