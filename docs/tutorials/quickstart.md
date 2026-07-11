# Quickstart — 10 Minutes to a Working SFTP Service

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

The fastest honest path from clone to a verified SFTP upload. Steps marked **PLANNED — lands with STREAM-x** are the committed design but not yet executable (see `docs/Issues.md`); today they read as the specification the streams build to. All commands run as an unprivileged user — no sudo (§11.4.161).

## Table of contents

1. [Clone](#1-clone)
2. [Configure](#2-configure)
3. [Bootstrap](#3-bootstrap)
4. [Sign in to the web admin](#4-sign-in-to-the-web-admin)
5. [Create the first user](#5-create-the-first-user)
6. [Upload + download test](#6-upload--download-test)
7. [What next](#7-what-next)

## 1. Clone

```bash
git clone <repo-url> sftp && cd sftp
git submodule update --init --recursive
```

## 2. Configure

```bash
cp .env.example .env        # PLANNED — lands with STREAM-1 (ATM-001)
chmod 600 .env
```

Defaults work out of the box: `SFTP_PORT=7721`, `API_PORT=7722`, `DB_DRIVER=sqlite`. Edit only if a port is busy (`ss -tlnp | grep -E ':(7721|7722) '`).

## 3. Bootstrap

```bash
# PLANNED — STREAM-1 compose (ATM-001) + STREAM-6 setup script (ATM-006)
bash scripts/setup.sh
```

`setup.sh` validates `.env`, brings the stack up with `podman-compose`, prompts for the super-admin credentials (never echoed), and runs a smoke probe. Expect a final line like `SETUP OK — sftp:7721 api:7722 admin console ready`.

Manual equivalent if you want to see the pieces:

```bash
podman-compose -f deploy/docker-compose.yml up -d      # PLANNED — ATM-001
podman ps --format '{{.Names}} {{.Status}}'            # all Up
```

## 4. Sign in to the web admin

**PLANNED — STREAM-4 (ATM-004):** open `http://<server>:7722/` (loopback or behind TLS per [security guide §8](../guides/security_guide.md)), sign in with the super-admin from §3. Dashboard loads with light/dark theme toggle (OpenDesign).

## 5. Create the first user

**Web console (PLANNED — ATM-004):** Accounts → **New account** → username `alice`, password per policy, permission `read_write`, leave **Public** off → Save.

**Or via API (PLANNED — ATM-002):** see [api_quickstart.md](api_quickstart.md) for the exact curl sequence (login → token → `POST /api/v1/accounts`).

Behind the scenes the API writes the DB row, re-renders `users.conf` atomically, provisions `data/alice/` (root-owned top + writable subdirectory), reloads the container, and audit-logs the action.

## 6. Upload + download test

```bash
cd /tmp && echo "hello-sftp" > quickstart_probe.txt
sftp -P 7721 alice@127.0.0.1 <<'EOF'
cd upload
put quickstart_probe.txt
get quickstart_probe.txt downloaded.txt
ls -la
bye
EOF
```

**PASS criteria (all required — positive evidence, §11.4):**
1. `put` reports `100%` with non-zero bytes.
2. `ls -la` lists `quickstart_probe.txt`.
3. `downloaded.txt` exists locally and `cmp quickstart_probe.txt downloaded.txt` exits 0.

Then clean up the probe files. If anything fails, run the matching playbook in [troubleshooting_guide.md](../guides/troubleshooting_guide.md).

## 7. What next

- [user_management_guide.md](../guides/user_management_guide.md) — permissions, keys, public-guard
- [security_guide.md](../guides/security_guide.md) — production hardening checklist
- [deployment_guide.md](../guides/deployment_guide.md) — systemd install, upgrades, rollback
- [api_quickstart.md](api_quickstart.md) — automate everything with curl

---

## Sources verified (2026-07-11)

- Internal: `docs/Issues.md` ATM-001/002/004/006 · `docs/research/mvp/MVP.md` (sftp client round-trip pattern) · `docs/guides/deployment_guide.md`.
- External: none fetched for this file specifically — stack facts verified via the guides' fetches (`atmoz/sftp`, `podman-compose`, `docs.podman.io`) on 2026-07-11.
