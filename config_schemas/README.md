# SFTP configuration schemas — accounts + server

**Revision:** 1
**Last modified:** 2026-07-11T16:30:36Z
**Scope:** `config_schemas/` — the user-facing configuration source of truth for the SFTP Enterprise system.
**Validator:** `scripts/validate_config.sh` (guide: `docs/scripts/validate_config.md`).

> **Why `config_schemas/` and not `config/`?** The `config/` path in this repo is a git
> submodule — the shared `vasic-digital/config` Go library (`.gitmodules`); writing
> project-specific files into it would violate submodule decoupling (§11.4.28(B)).
> Conductor decision 2026-07-11 (STREAM-3 report `qa/results/STREAM-3-report.md`):
> the user-facing configuration lives in `config_schemas/`.

---

## 1. Files

| File | Role |
|---|---|
| `accounts.yaml` | Canonical account list (YAML). Edited by operators / rendered by the API. |
| `accounts.json` | Same accounts in JSON form — identical schema. |
| `schema/accounts.schema.json` | JSON Schema draft 2020-12 validating both files. |
| `schema/fixtures/` | Anti-bluff fixtures: 4 `bad-*` (MUST fail) + 1 `good-*` (MUST pass); driven by `validate_config.sh --selftest`. |
| `server.yaml` | Server runtime config example (ports, paths, host keys, log level) — placeholders only. |
| `../users.conf.example` | Reference atmoz user list rendered FROM `accounts.yaml` (tracked template; the live `users.conf` is git-ignored, §11.4.10). |

---

## 2. accounts.yaml / accounts.json — field reference

Top level:

| Field | Type | Required | Default | Rule |
|---|---|---|---|---|
| `version` | integer | yes | — | Must be `1` (schema `const`). |
| `accounts` | list | yes | — | List of account objects (may be empty). |

Per account:

| Field | Type | Required | Default | Rule |
|---|---|---|---|---|
| `username` | string | yes | — | Regex `^[a-z_][a-z0-9_-]{0,31}$` — POSIX-style login, lowercase, ≤ 32 chars. |
| `permission` | enum | yes | — | One of `read_only` \| `read_write` \| `public`. No default is offered — every account must state its permission explicitly, and `public` is NEVER used as a default anywhere in this system. |
| `public_acknowledged` | boolean | no | `false` | MUST be `true` when `permission: public` — enforced by the schema's `allOf`/`if`/`then` rule. This is the explicit operator acknowledgement that public access is intended. |
| `uid` | integer | no | `1001` | 0–65535. Numeric UID inside the container; the host home directory MUST be owned by this UID (evidence: `docs/research/mvp/MVP.md` lines 117-132). |
| `gid` | integer | no | `1001` | 0–65535. Same ownership contract as `uid`. |
| `home` | string | no | `/sftp_data/<username>` | Regex `^/sftp_data/[a-z_][a-z0-9_-]{0,31}$`. Path INSIDE the container; `./data` is bind-mounted at `/sftp_data` (MVP.md line 73, `deploy/docker-compose.yml` L25). |
| `enabled` | boolean | no | `true` | Disabled accounts stay in config but are NOT rendered to `users.conf`. |
| `comment` | string | no | — | Free-text operator note, ≤ 256 chars. |

Strictness: unknown properties are rejected (`additionalProperties: false`, both levels) — a typo'd field is a validation error, not silently ignored. This mirrors ATM-003's "unknown field = error" requirement.

---

## 3. Permission model — what each value means in atmoz terms

Evidence source: `docs/research/mvp/MVP.md` (the in-repo atmoz/sftp deployment doc); compose wiring in `deploy/docker-compose.yml`.

| Permission | atmoz / sshd semantics | Capability |
|---|---|---|
| `read_only` | User chrooted into its home (`ChrootDirectory %h` per the MVP sshd_config example, lines 87-96); home directory write-masked (owned by the account's uid:gid with write removed from the rendered provisioning step). | Download (get) only; upload (put) denied. |
| `read_write` | Same chroot; home owned by the account's uid:gid with full owner write (MVP.md lines 117-132: host dir `chown <uid>:<gid>`). | Upload + download. |
| `public` | Anonymous-style shared access. **NEVER default.** Exists only when the operator explicitly sets `public_acknowledged: true`; API + UI guard this with an acknowledgement step (ATM-002). Disabled example only — see `accounts.yaml`. | Per deployment policy; gated at every layer. |

The atmoz line grammar these permissions render to
(`user:password:uid:gid:home_directory[:options]`, one per line) is evidenced in
MVP.md lines 62-71; only that evidenced grammar is mirrored — no undocumented
syntax is asserted (§11.4.6).

---

## 4. How the API consumes it / render pipeline

1. **Source of truth:** operators edit `accounts.yaml` (or drive the same model through the REST API / admin UI). `accounts.json` is the JSON form of the identical schema for API-side tooling.
2. **Validation:** every change is validated by `scripts/validate_config.sh` (offline; JSON Schema draft 2020-12 via python3 `jsonschema`, with a documented structural fallback). CI/pre-build runs it; `--selftest` proves the validator rejects all four defect classes (unknown permission, public-without-ack, bad username, missing username).
3. **Render:** the API sync layer (ATM-002) reads the validated accounts, and for each `enabled: true` account emits one atmoz line `username:password:uid:gid:home` into the live `./users.conf` (atomically: tmp + rename), and provisions `<data_dir>/<username>` owned `uid:gid` with the permission's write mask. The live `users.conf` is bind-mounted read-only at `/etc/sftp/users.conf` (`deploy/docker-compose.yml` L27) and consumed by atmoz via `SFTP_USERS_FILE` (L29).
4. **Reference render:** `../users.conf.example` is the tracked template showing exactly what the render of this example's accounts looks like (passwords are `$6$example$...` placeholders — real credentials never live in git, §11.4.10; atmoz stores passwords in plain text in the live file, MVP.md L221).
5. **Reload:** the container re-reads `users.conf` on restart (`docker-compose restart`, MVP.md lines 204-208); the sync layer triggers this through the `containers` submodule (§11.4.76) — never ad-hoc podman/docker.

---

## 5. server.yaml

Server runtime settings: `server.port` (7721, `.env` `SFTP_PORT` overrides — compose L23), `server.api_port`/`api_bind` (7722 / 127.0.0.1), `paths.data_dir` (`./data` → `/sftp_data`), `paths.users_conf` (`./users.conf`), `paths.host_keys_dir` (`<set-in-.env>` placeholder — real value in the git-ignored `.env`), `logging.level` (info), and `security.allow_public_default: false` (public is never default, duplicated here as a server-level guard).

---

## 6. Anti-bluff posture

- The schema rejects all four defect classes; `validate_config.sh --selftest` proves it on every run using the fixtures (a validator that passes its bad fixtures is a §11.4 bluff).
- No real credentials anywhere — `CHANGE_ME` / `<set-in-.env>` placeholders only (§11.4.10).
- Every behavioral claim above cites its evidence (MVP.md line numbers, compose line numbers) — no guessing (§11.4.6).

---

## Sources verified

Sources verified 2026-07-11: in-repo evidence only, per conductor directive — `docs/research/mvp/MVP.md` (atmoz/sftp line grammar L62-71, ownership L117-132, plain-text passwords L221, sshd_config example L80-97, compose example L36-53), `deploy/docker-compose.yml` (L23-29). No web fetch performed (conductor: mirror only MVP-evidenced grammar).
