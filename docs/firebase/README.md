# Firebase integration (API subsystem)

**Revision:** 1
**Last modified:** 2026-07-11T00:00:00Z
**Scope:** optional Firebase Admin SDK subsystem of the SFTP Enterprise
management API (`api/internal/firebase`, ATM-007) + the web-app SDK config
helper (`scripts/firebase_config.sh`, STREAM-6).

## What this is

The management API can optionally initialize the **Firebase Admin SDK for
Go** (`firebase.google.com/go/v4`) at startup. It is **OFF by default** and
the API runs fully without it:

| `FIREBASE_ENABLED` | Behaviour |
|---|---|
| `false` (default) | API logs `firebase: disabled` and continues normally. |
| `true`, misconfigured | API **fails fast** with a clear error (missing project id, missing/unreadable/invalid service-account file) — no silent half-enabled state (§11.4.6). |
| `true`, configured | Admin SDK initializes from the service-account JSON; the API logs `firebase: enabled (project <id>)`. |

Crashlytics / Analytics / Performance hooks exist as **no-op-safe stubs**:
the Go Admin SDK has no ingestion API for those surfaces (they are
client-side mobile/web SDK surfaces), so the hooks log honestly instead of
pretending to record telemetry. `Client.Verify` performs a real
connectivity + credentials round-trip (Identity Toolkit `GetUserByEmail`
probe; an authenticated "user not found" answer is positive evidence of
connectivity) — it requires the **Identity Toolkit API** enabled on the
project, so it is not run automatically at startup.

## Setup

> Sources verified 2026-07-11 against current Firebase documentation:
> - <https://firebase.google.com/docs/admin/setup> (service account generation + Go init)
> - <https://firebase.google.com/docs/projects/learn-more> (project id location)

1. **Create / pick the Firebase project.** In the
   [Firebase console](https://console.firebase.google.com/) create a project
   (or use an existing one). Note the **Project ID** from
   *Project settings → General*.
2. **Enable the surfaces you need** (per-product tabs in the console):
   - **Crashlytics**: *Run → Crashlytics* — connect an app that reports
     crashes (mobile/web clients own this; the API does not ingest).
   - **Analytics**: enabled automatically when you add an app with Google
     Analytics.
   - **Performance Monitoring**: *Run → Performance*.
   - **Identity Toolkit** (only if you intend to call `Client.Verify` /
     the health probe): enable the *Identity Platform / Identity Toolkit
     API* in the Google Cloud console for the project.
3. **Generate the service-account key.** *Project settings → Service
   accounts → Generate new private key → Generate key*. This downloads a
   JSON file. Treat it as a high-value secret (Firebase's own guidance).
4. **Store the key outside git.** Move it to the git-ignored location:

   ```bash
   mkdir -p secrets && chmod 700 secrets
   mv ~/Downloads/<project>-firebase-adminsdk-*.json secrets/firebase-service-account.json
   chmod 600 secrets/firebase-service-account.json
   ```

   `service-account*.json` / `firebase-service-account*.json` and
   `secrets/` are git-ignored (§11.4.10/.30). **NEVER commit a real
   service account.**
5. **Set env (in the git-ignored `.env`, template: `.env.example`):**

   ```bash
   FIREBASE_ENABLED=true
   FIREBASE_PROJECT_ID=<your-project-id>
   FIREBASE_SERVICE_ACCOUNT_PATH=./secrets/firebase-service-account.json
   FIREBASE_WEB_APP_ID=<1:PROJECT_NUMBER:web:HASH>   # only for step 6
   ```

6. **(Optional) Fetch the web SDK config** for the admin SPA:

   ```bash
   firebase login            # once
   firebase apps:list        # find the WEB app id if unsure
   scripts/firebase_config.sh --check   # or plain run to (re)fetch
   ```

   This writes `web/src/firebase-config.json` (git-ignored, never printed —
   see `docs/scripts/firebase_config.md`).
7. **Start the API.** With `FIREBASE_ENABLED=true` the log line
   `firebase: enabled (project <id>)` confirms initialization; with
   `false`, `firebase: disabled` confirms the subsystem is inert.

## Tests

```bash
cd api && go test ./internal/firebase/...
```

Covers: disabled path is inert + logs `firebase: disabled`; each
misconfigured-enabled path (no project id, no key path, missing file,
directory instead of file, malformed JSON, undecryptable private key)
fails fast with a clear error. The tests exercise the real Admin-SDK init
logic (`firebase.NewApp` + `option.WithCredentialsFile`) — no tautologies.

## Cross-references

- `api/internal/firebase/firebase.go` — subsystem source (contract in the
  package doc comment).
- `config_schemas/firebase.yaml` — field schema + JSON Schema.
- `scripts/firebase_config.sh` + `docs/scripts/firebase_config.md` —
  web SDK config fetch.
- `.env.example` — env template; constitution §11.4.10 (credentials),
  §11.4.30 (git-ignore discipline), §11.4.99 (latest-source verification).
