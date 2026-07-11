# STREAM-7 — ATM-007: Firebase integration (API subsystem)

**Status:** DONE
**Date:** 2026-07-11
**Scope honored:** touched only `api/`, `config_schemas/`, `docs/firebase/`,
`.env.example` (append-only), `.gitignore` (append-only), this report.
`web/`, `mobile/`, `scripts/firebase_config.sh` NOT modified (the existing
script already covers web SDK config; `.env.example` only documents its
`FIREBASE_WEB_APP_ID` input).

## Files

| File | Change |
|---|---|
| `api/internal/firebase/firebase.go` | NEW — optional Admin SDK subsystem: graceful degrade, fail-fast misconfiguration, `Verify` connectivity probe, no-op-safe Crashlytics/Analytics/Performance hooks that log honestly (Go Admin SDK has no ingestion API for those surfaces). |
| `api/internal/firebase/firebase_test.go` | NEW — 7 unit tests exercising the real init logic. |
| `api/internal/config/config.go` | +3 fields (FirebaseEnabled / FirebaseProjectID / FirebaseServiceAccountPath) + env loading. |
| `api/cmd/sftp-api/main.go` | Wired `firebase.New` after authn; disabled → continue, misconfigured-enabled → fatal with clear error. |
| `api/go.mod`, `api/go.sum` | `firebase.google.com/go/v4 v4.21.0` (+ transitive) via `go get` + `go mod tidy` — network was available; no vendoring needed. |
| `config_schemas/firebase.yaml` | NEW — field documentation + JSON Schema (conditional required-when-enabled). |
| `docs/firebase/README.md` | NEW — setup guide (§11.4.44 revision header; steps verified 2026-07-11 against firebase.google.com/docs/admin/setup per §11.4.99). |
| `.env.example` | Appended `FIREBASE_SERVICE_ACCOUNT_PATH` + `FIREBASE_WEB_APP_ID`; corrected `FIREBASE_ENABLED` comment to reference the service account (Admin SDK), not google-services.json. |
| `.gitignore` | Appended `service-account*.json`, `firebase-service-account*.json` (pre-existing: `secrets/`, `google-services.json`, `firebase-config*.json`). |

## Enable / disable contract

- `FIREBASE_ENABLED=false` (default): API logs exactly `firebase: disabled`
  and starts normally. All hooks are safe no-ops.
- `FIREBASE_ENABLED=true`: requires `FIREBASE_PROJECT_ID` + a readable,
  valid Admin SDK service-account JSON at `FIREBASE_SERVICE_ACCOUNT_PATH`
  (operator-provided, git-ignored — never committed). Any defect → the API
  refuses to start with a precise error (§11.4.6, no guessing).
- `Client.Verify(ctx)`: real connectivity round-trip via Identity Toolkit
  `GetUserByEmail` probe (authenticated 404 = positive evidence). Not run
  at startup because it needs the Identity Toolkit API enabled.

## Verification (captured evidence)

- `go build ./...` — exit 0.
- `go vet ./...` — exit 0.
- `go test ./internal/firebase/...` — `ok ... 0.007s` (7 tests: disabled
  inert + logs; missing project id; missing key path; missing file;
  directory-instead-of-file; malformed JSON; undecryptable private key —
  the last two prove the real `firebase.NewApp`/`WithCredentialsFile`
  parsing path runs).
- Full suite `go test ./...` — all packages ok.
- Runtime smoke (built binary, real startup):
  - disabled → log line `firebase: disabled`, API started and served.
  - `FIREBASE_ENABLED=true` without project id →
    `sftp-api: fatal: firebase: FIREBASE_ENABLED=true but FIREBASE_PROJECT_ID is empty`, exit 1.

## Host limitations

None. Firebase Admin SDK module fetched from the network successfully
(v4.21.0); no build-tag fallback was needed. No git operations performed.
