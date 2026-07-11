# Troubleshooting Guide

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

Failure-mode playbooks for the enterprise SFTP stack. Each entry: **Symptom → Diagnosis → Fix → Verify**. Verification requires positive output, not absence of errors (§11.4 anti-bluff). Items referencing not-yet-built components cite their ATM item.

## Table of contents

1. [Container won't start](#1-container-wont-start)
2. [Port conflicts (7721 / 7722)](#2-port-conflicts-7721--7722)
3. [Permission denied on upload](#3-permission-denied-on-upload)
4. [Login fails immediately — the chroot write problem](#4-login-fails-immediately--the-chroot-write-problem)
5. [API authentication failures](#5-api-authentication-failures)
6. [Database migration issues](#6-database-migration-issues)
7. [systemd --user / linger issues](#7-systemd---user--linger-issues)
8. [SFTP works locally but not from the network](#8-sftp-works-locally-but-not-from-the-network)
9. [MITM / host-key warnings after container recreate](#9-mitm--host-key-warnings-after-container-recreate)
10. [Related docs](#10-related-docs)

## 1. Container won't start

**Symptom:** `podman ps` shows the sftp container exited; `podman-compose up -d` reported failure.

**Diagnosis:**
```bash
podman logs <sftp-container-name>        # last 50 lines tell the story
podman-compose -f deploy/docker-compose.yml config   # validate compose syntax
```

**Common causes + fixes:**
- **Malformed `users.conf`** — every line must match `user:pass[:e][:uid[:gid[:dir…]]]`; a stray space or missing field aborts entrypoint. Fix the line, re-render via the API (ATM-003 renderer validates before writing), restart.
- **Volume path missing** — create `data/` on the host: `mkdir -p data`.
- **Port already bound** — see §2.
- **Image pull failure** — `podman pull atmoz/sftp:<tag>` separately to see the real error.

**Verify:** `podman ps --format '{{.Names}} {{.Status}}'` shows `Up`, and `podman logs` ends with the sshd listening line (no `error` entries).

## 2. Port conflicts (7721 / 7722)

**Symptom:** compose fails with "address already in use", or connections land on the wrong service.

**Diagnosis:**
```bash
ss -tlnp | grep -E ':(7721|7722) '     # who owns the port
```

**Fix:** stop the conflicting process, or change `SFTP_PORT` / `API_PORT` in `.env` and re-run `service_ctl.sh restart` (ATM-006). Rootless Podman binds as the user — ports <1024 are out of scope by design; stay in the 77xx range.

**Verify:** `ss -tlnp` shows exactly one listener per port, owned by the expected process; `sftp -P $SFTP_PORT user@127.0.0.1` reaches the SFTP banner.

## 3. Permission denied on upload

**Symptom:** login succeeds, `put file.txt` fails with `Permission denied`.

**Diagnosis:**
```bash
ls -ln data/            # numeric UID/GID of the user's home + subdirs
podman exec <container> id <user> 2>/dev/null || true
```

**Causes + fixes:**
1. **Writing into the chroot top-level** — by design impossible; the chroot home is root-owned and non-user-writable (see §4). Upload into the writable subdirectory instead (e.g. `cd upload && put file.txt`). The provisioner (ATM-003) creates it automatically.
2. **UID/GID mismatch** — host directory must be owned by the numeric UID/GID from `users.conf`. Rootless note: in rootless Podman the container UID maps through the user namespace; the project standardizes UID/GID allocation in the renderer so host and container agree. Fix ownership with the matching numeric IDs (as the service user; no sudo in rootless layout — the data root lives under the service user's home).
3. **Account is `read_only`** — check `GET /api/v1/accounts/<user>`; `read_only` rejects uploads by design (ATM-002/003). Change permission if intended (audit-logged).

**Verify:** `put` into the writable subdirectory returns `100%` progress and `ls` shows the file with non-zero size; for `read_only`, the denial itself is the correct verified behavior.

## 4. Login fails immediately — the chroot write problem

**Symptom:** client connects, authenticates, then the session closes instantly (`Connection closed` right after password); server log shows `fatal: bad ownership or modes for chroot directory`.

**Root cause (the classic atmoz/internal-sftp trap):** OpenSSH requires the `ChrootDirectory` (the user's home, `%h`) to be **owned by root and NOT writable by the user**. If the user's home is user-writable, sshd refuses the session. atmoz/sftp documents the same constraint from the other side: users "can't create new files directly under their own home directory".

**Fix:**
1. Ensure the home top-level is root-owned, mode `755`, **not** writable by the account's UID.
2. Provide a writable subdirectory inside it (e.g. `upload/`) owned by the user's UID/GID — this is where clients upload. The ATM-003 directory provisioner does both automatically; manual provisioning must replicate it.
3. Re-render/reload (API reload signal, or `service_ctl.sh restart sftp`).

**Verify:** login succeeds; `pwd` shows `/`; `put` into `/upload` completes; attempted `put` into `/` is denied (expected).

## 5. API authentication failures

**PLANNED — STREAM-2 (ATM-002).**

**Symptom:** `401` from `/api/v1/**`, or login returns `403`.

**Diagnosis + fixes:**
- **Wrong/expired token** — tokens are short-lived; re-login via `POST /api/v1/auth/login` (see [api_quickstart.md](../tutorials/api_quickstart.md)).
- **Rate-limited** — `429` after repeated failures; back off, check the audit log for the lockout entry; limits are configurable (§6 of security guide).
- **Bootstrap already consumed** — a second `POST /api/v1/bootstrap` returns `409`; the super-admin already exists. Use login, not bootstrap.
- **Clock skew** — JWT validation fails if host clock drifts; verify `timedatectl`.

**Verify:** login returns a token JSON; an authenticated `GET /api/v1/accounts` returns `200` with a JSON array.

## 6. Database migration issues

**PLANNED — ATM-002 (embedded migrations).**

**Symptom:** API container restarts in a loop; logs show migration failure; `/readyz` returns non-200.

**Diagnosis + fixes:**
- **Partial migration after crash** — restore the pre-upgrade snapshot (`backup.sh restore <id>`, ATM-006), then re-run the upgrade; migrations are transactional per step by design.
- **SQLite file locked** — only one API instance may own the SQLite file; ensure a single replica and that the volume isn't shared with a stray dev instance.
- **Postgres unreachable** — check `podman logs <postgres>` and the API's `DB_*` env; `readyz` distinguishes DB-down from migration-failed.

**Verify:** `/readyz` returns `200`; the audit log records `migration applied: <version>` lines.

## 7. systemd --user / linger issues

**PLANNED — ATM-006 units.**

**Symptom:** `systemctl --user status sftp-stack` errors with "Failed to connect to bus", or the stack dies at logout.

**Diagnosis + fixes:**
- **No user bus** — you are in a bare SSH session without `XDG_RUNTIME_DIR`; log in via a proper session (`machinectl shell` or a real login), or run units with `systemctl --user` only after `loginctl` shows your session.
- **Stack stops at logout** — user services stop with the last session unless linger is enabled:
  ```bash
  loginctl enable-linger "$USER"
  ```
  On managed hosts this may require an administrator — it is the only step outside pure user scope. If linger is denied, document the operational constraint and use a supervised foreground run for that host.
- **Unit not found** — re-run `bash scripts/service_ctl.sh install` and `systemctl --user daemon-reload`.

**Verify:** `systemctl --user is-enabled sftp-stack` → `enabled`; after logout/login, `podman ps` still shows the containers `Up` (linger case).

## 8. SFTP works locally but not from the network

**Diagnosis + fixes (from MVP.md, carried forward):**
- **Firewall:** UFW `sudo ufw allow 7721/tcp` — NOTE: this is a host-admin firewall step, distinct from the no-sudo container runtime; on hosts where the operator holds no admin rights, request the port opening from the administrator. firewalld: `sudo firewall-cmd --permanent --add-port=7721/tcp && sudo firewall-cmd --reload`.
- **Cloud security group:** allow inbound TCP 7721 (or restrict to known client CIDRs).
- **Binding:** confirm the port mapping publishes on the right interface (`ss -tlnp`).

**Verify:** from a second host, `sftp -P 7721 user@<server-ip>` reaches authentication; local test alone is not sufficient proof.

## 9. MITM / host-key warnings after container recreate

**Symptom:** clients warn "REMOTE HOST IDENTIFICATION HAS CHANGED" after every container rebuild.

**Cause:** atmoz/sftp generates fresh host keys on first start; ephemeral container storage means new keys every recreate.

**Fix:** persist `/etc/ssh/host_keys` as a volume (see deployment guide §3 — already in the compose design). Migrate once: recreate with the volume, have clients accept the new key once, done.

**Verify:** two consecutive container recreates keep the same `ssh-keygen -lf` fingerprint; clients connect without warnings.

## 10. Related docs

- [deployment_guide.md](deployment_guide.md) — install, verify, rollback
- [user_management_guide.md](user_management_guide.md) — permissions, keys
- [security_guide.md](security_guide.md) — chroot rule context, hardening
- [../faq/faq.md](../faq/faq.md) — quick answers
- `docs/research/mvp/MVP.md` — baseline troubleshooting (container fails, permission denied, remote connect)

---

## Sources verified (2026-07-11)

- Internal: `docs/research/mvp/MVP.md` (permission-denied, container-start, remote-connect entries) · `docs/Issues.md` ATM-002/003/006 (migrations, provisioner, units).
- External fetched this revision: `https://github.com/atmoz/sftp` (chroot home-not-writable symptom, host-key persistence recommendation).
- OpenSSH `ChrootDirectory` ownership/mode rule per `sshd_config(5)` — to re-verify before each release (§11.4.99): man page + atmoz README.
