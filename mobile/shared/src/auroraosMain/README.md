# auroraosMain — AuroraOS port scaffolding (host-limited, §11.4.6 / §11.4.3 SKIP-with-reason)

## Status

**Scaffolding only — NOT compiled on this host.** AuroraOS (Russian
Sailfish-derived mobile OS) has no Kotlin Multiplatform target in
upstream Kotlin. The realistic port path is:

1. **Aurora SDK (Sailfish SDK based)** — Qt/QML + C++ platform layer.
   The Aurora SDK is distributed for Linux but requires an OMP developer
   account and the SDK installer, which is NOT present on this host.
2. Bind commonMain business logic via one of:
   - Kotlin/Native linux target compiled against the Aurora sysroot
     (glibc mismatch risk — Aurora uses its own libc/toolchain), or
   - a thin native bridge where the QML UI calls into a small REST
     client mirroring `ApiClient`'s contract.

## What the port must provide (when the toolchain is available)

- Token storage → Sailfish/Aurora credential store (Secrets framework,
  `org.sailfishos.secrets`) — tokens never in plain config (§11.4.10).
- Settings → QSettings / dconf for non-secret values only.
- HTTP → Qt Network (QNetworkAccessManager) implementing the exact
  `/api/v1` contract from `api/Models.kt`.

The QML UI reuses the same screen structure as the Compose screens
(Login / Dashboard / AccountEditor / Settings) and the SAME OpenDesign
token values from `docs/design/tokens/` (light + dark), so visual parity
is token-driven rather than re-designed (§11.4.162).

## Host limitation evidence

- This host has no Aurora SDK / Sailfish SDK, no OMP developer account →
  the port cannot be built or validated here (honest SKIP-with-reason).
- Action required: provision the Aurora SDK on a Linux build host with
  an OMP account, then implement the QML client against this shared
  contract.
