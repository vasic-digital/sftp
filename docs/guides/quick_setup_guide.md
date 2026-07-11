# SFTP Enterprise — Quick Setup Guide

**Revision:** 1
**Last modified:** 2026-07-11T19:40:00Z

The fastest path from zero to a working SFTP management API + Web admin. Every command verified against the `sftp-0.1.0-dev-0.1.0` release. No sudo required — everything runs as your unprivileged user (§11.4.161).

---

## 1. Prerequisites

| Tool | Min version | Check |
|---|---|---|
| Go | 1.26 | `go version` |
| Node.js | 22 | `node --version` |
| SQLite | 3.x | `sqlite3 --version` |
| Podman (rootless) | 5.x | `podman --version` |

---

## 2. Clone

```bash
git clone git@github.com:vasic-digital/sftp.git sftp && cd sftp
git submodule update --init --recursive
```

---

## 3. Configure

```bash
# Copy the template (defaults work for local dev)
cp .env.example .env
chmod 600 .env

# The only values you MUST set:
#   SUPERADMIN_PASSWORD — your admin password (never committed, never echoed)
#   JWT_SECRET — random 32+ char string (generate: openssl rand -hex 32)
# Everything else defaults to safe local-dev values
```

---

## 4. Build the API

```bash
cd api && go build -o ../bin/sftp-api ./cmd/sftp-api/ && cd ..
# Binary lands at bin/sftp-api (git-ignored)
```

---

## 5. Start the API

```bash
# Minimal env — works for local testing
export SUPERADMIN_PASSWORD="$(grep SUPERADMIN_PASSWORD .env | cut -d= -f2)"
export JWT_SECRET="$(grep JWT_SECRET .env | cut -d= -f2)"
export FIREBASE_ENABLED=false

mkdir -p data/vault
./bin/sftp-api

# You should see:
#   sftp-api: super-admin "admin" seeded
#   firebase: disabled
#   sftp-api: listening on 127.0.0.1:7722 (version 0.1.0-dev)
```

---

## 6. Health check

```bash
curl http://127.0.0.1:7722/api/v1/health
# → {"firebase":"disabled","status":"ok","time":"...","version":"0.1.0-dev"}
```

---

## 7. Login as super-admin

```bash
curl -s -X POST http://127.0.0.1:7722/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"YOUR-SUPERADMIN-PASSWORD"}'

# → {"access_token":"eyJ...","refresh_token":"eyJ...","token_type":"Bearer","expires_in":900}
```

Save the token for subsequent calls:
```bash
TOKEN="$(curl -s ... | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")"
```

---

## 8. Create your first SFTP user

```bash
curl -s -X POST http://127.0.0.1:7722/api/v1/accounts \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"username":"alice","password":"strongpw","permission":"read_write"}'

# → {"username":"alice","permission":"read_write","home_dir":"/alice","enabled":true,...}
```

**Permission levels:**
- `read_only` — download only
- `read_write` — upload + download + delete
- `public` — requires `"public_acknowledged":true` (explicit opt-in, never default)

---

## 9. Sync to SFTP container

```bash
curl -s -X POST http://127.0.0.1:7722/api/v1/sync \
  -H "Authorization: Bearer $TOKEN"

# → {"path":"data/users.conf","rendered_accounts":1}
```

The `data/users.conf` file is now ready for the atmoz/sftp container.

---

## 10. Start the Web Admin (optional)

```bash
cd web
npm install
npm run dev
# → http://localhost:5173

# Login with admin / your-superadmin-password
# Dashboard shows all accounts, create/edit/delete from the UI
```

---

## 11. Start the SFTP container (with Podman)

```bash
# Ensure users.conf exists and data directories are ready
podman-compose -f deploy/docker-compose.yml up -d

# Check status
podman ps --format '{{.Names}} {{.Status}}'
```

---

## 12. Verify end-to-end

```bash
# Create test file
echo "hello sftp" > /tmp/test_upload.txt

# Upload (as alice, port 7721)
sftp -P 7721 alice@127.0.0.1 <<< $'put /tmp/test_upload.txt'

# Download to verify
sftp -P 7721 alice@127.0.0.1 <<< $'get test_upload.txt /tmp/test_download.txt'
diff /tmp/test_upload.txt /tmp/test_download.txt && echo "E2E VERIFIED"
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `go build` fails | `cd api && go mod tidy` |
| Port 7722 already in use | `ss -tlnp \| grep 7722` — kill the other process |
| `super-admin seeded` but login fails | Check SUPERADMIN_PASSWORD matches what you set |
| `public access is never a default` | Add `"public_acknowledged":true` to the request |
| `firebase: disabled` in logs | Normal — set `FIREBASE_ENABLED=true` + provide service account JSON |

---

## Sources verified

- atmoz/sftp Docker Hub: https://hub.docker.com/r/atmoz/sftp
- Gin framework: https://gin-gonic.com/docs/
- Firebase Admin Go SDK: https://firebase.google.com/docs/reference/admin/go
- Verified against release sftp-0.1.0-dev-0.1.0 (commit 9047b09)
