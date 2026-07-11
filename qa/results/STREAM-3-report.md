# STREAM-3 Report — ATM-003: user-facing config source of truth + permission model + users.conf example

**(T1/main - sftp) STREAM-3** · Date: 2026-07-11 · Status: **DONE**

---

## 1. Layout decision (conductor, 2026-07-11) — documented trail

Initial dispatch assigned `config/…`, but `config/` is a git submodule — the shared
`vasic-digital/config` Go library (`.gitmodules` L16-18; `git check-ignore config/accounts.yaml`
→ `fatal: Pathspec ... is in submodule 'config'`). Writing project-specific files into it would
violate §11.4.28(B) decoupling. Conductor decision (option A): **user-facing configuration lives
in `config_schemas/`** — snake_case (§11.4.29), unambiguous for STREAM-2/STREAM-9. The Go
`config` submodule remains untouched for ATM-002's module-level config loading.

## 2. Files created

| File | Purpose |
|---|---|
| `config_schemas/accounts.yaml` | Canonical example: 2 enabled accounts (`sftp_writer` read_write, `sftp_reader` read_only) + a commented-out public example showing `public_acknowledged: true`. `version: 1` top level. |
| `config_schemas/accounts.json` | Same accounts, JSON form, identical schema. |
| `config_schemas/schema/accounts.schema.json` | JSON Schema draft 2020-12: username regex, permission enum, `allOf`/`if`/`then` rule `permission==public ⇒ public_acknowledged===true`, `additionalProperties: false` (strict), uid/gid 0–65535, home regex `^/sftp_data/<username>$`. |
| `config_schemas/schema/fixtures/bad-unknown-permission.yaml` | Negative fixture (`permission: execute`) — MUST FAIL. |
| `config_schemas/schema/fixtures/bad-public-without-ack.yaml` | Negative fixture (public, ack false) — MUST FAIL. |
| `config_schemas/schema/fixtures/bad-username.yaml` | Negative fixture (`"Bad User!"`) — MUST FAIL. |
| `config_schemas/schema/fixtures/bad-missing-username.yaml` | Negative fixture (no username) — MUST FAIL. |
| `config_schemas/schema/fixtures/good-example.yaml` | Positive fixture incl. a legally-acknowledged public account — MUST PASS. |
| `config_schemas/server.yaml` | Server config example: ports (7721/7722), paths, host-keys dir placeholder, log level, `allow_public_default: false`. Placeholders only. |
| `config_schemas/README.md` | Full schema docs: every field + defaults + validation rules, permission model in atmoz terms (evidence-cited), API consumption + users.conf render pipeline, `config_schemas/` decision trail. §11.4.44 revision header present. |
| `users.conf.example` | Atmoz-format reference render of the example accounts (3 lines: read_write, read_only, commented-out public), `$6$example$CHANGE_ME_*` placeholders, "EXAMPLE ONLY — generated, never hand-edit" header. Created in round 1, kept per conductor. |
| `scripts/validate_config.sh` | POSIX-sh validator (executable): default validates both example files; `--selftest` proves all 4 rejection classes; `--dir` override; documented structural fallback when `jsonschema` is absent. §11.4.18 in-source doc block. |
| `docs/scripts/validate_config.md` | §11.4.18 external user guide (overview, prerequisites, usage, edge cases, internals, related docs, last-verified). §11.4.44 revision header present. |
| `qa/results/STREAM-3-report.md` | This report. |

No git operations performed (conductor owns git). No submodule touched. No real credentials — placeholders only (`CHANGE_ME`, `<set-in-.env>`, `$6$example$...`); placeholder audit found 9 intentional placeholder markers and zero secrets.

## 3. Schema decisions

- `version: 1` (const) + `accounts` list; per account: `username` (required, `^[a-z_][a-z0-9_-]{0,31}$`), `permission` (required enum `read_only|read_write|public` — **no default offered anywhere**; `public` is never default), `public_acknowledged` (default false; forced `true` for public via allOf/if/then), `uid`/`gid` (default 1001, 0–65535), `home` (default `/sftp_data/<username>`, regex-anchored to the bind-mount root), `enabled` (default true), `comment` (≤256 chars). Strict: unknown properties rejected at both levels (ATM-003 "unknown field = error").
- Defaults documented in `config_schemas/README.md` §2 table.
- Permission semantics (README §3), evidence-cited: read_only = chrooted + write-masked home (download only); read_write = chrooted + uid:gid-owned home (upload+download); public = anonymous-style, never default, acknowledgement-gated at schema/API/UI layers.
- atmoz grammar mirrored strictly from MVP.md evidence (`user:password:uid:gid:home_directory[:options]`, L64) — no undocumented `[,dir2]` syntax asserted (conductor directive, §11.4.6).

## 4. atmoz-format evidence (in-repo)

- `docs/research/mvp/MVP.md` L64: `Format: user:password:uid:gid:home_directory[:options]`, one user per line.
- MVP.md L69-70: example lines `alice:MyS3cur3P@ss!:1000:1000:/sftp_data/alice` …
- MVP.md L73: home is a path INSIDE the container; `./data` → `/sftp_data`.
- MVP.md L117-132: host dir must be owned by the numeric uid:gid from users.conf.
- MVP.md L221: passwords stored in plain text in the live file (security note) — hence placeholders in git.
- MVP.md L204-208: container re-reads users.conf on restart.
- `deploy/docker-compose.yml` L23-29: `${SFTP_PORT:-7721}:22`, users.conf bind `:ro` at `/etc/sftp/users.conf`, `SFTP_USERS_FILE`.
- Sources footer in README: in-repo evidence only, verified 2026-07-11; no web fetch (conductor directive).

## 5. Validator outputs (captured evidence, §11.4.5)

```
=== 1. bash -n ===
clean
=== 2. sh -n ===
clean
=== 3. schema parses as JSON ===
schema JSON OK, 9 top-level keys, draft: https://json-schema.org/draft/2020-12/schema
=== 4. accounts.yaml parses (yaml) ===
YAML OK — version 1 , 2 accounts: ['sftp_writer', 'sftp_reader']
=== 5. accounts.json parses (json) ===
JSON OK — version 1 , 2 accounts: ['sftp_writer', 'sftp_reader']
=== 6. server.yaml parses (yaml) ===
server.yaml OK — ['version', 'server', 'paths', 'logging', 'security']
=== 7. fixtures parse ===
parse OK: (all 5 fixture files)
=== 8. validator default run ===
# validator backend: jsonschema (offline)
VALID config_schemas/accounts.yaml
VALID config_schemas/accounts.json
VALIDATION PASS: accounts.yaml + accounts.json conform to accounts.schema.json
exit=0
=== 9. validator --selftest ===
selftest OK (rejected): config_schemas/schema/fixtures/bad-missing-username.yaml
selftest OK (rejected): config_schemas/schema/fixtures/bad-public-without-ack.yaml
selftest OK (rejected): config_schemas/schema/fixtures/bad-unknown-permission.yaml
selftest OK (rejected): config_schemas/schema/fixtures/bad-username.yaml
selftest OK (accepted): config_schemas/schema/fixtures/good-example.yaml
SELFTEST PASS: 5 fixtures behaved as named (bad-* rejected, good-* accepted)
exit=0
=== 10. schema meta-validation ===
schema is a valid Draft 2020-12 schema
=== fallback backend (jsonschema import forced to fail via PYTHONPATH shadow) ===
# validator backend: structural-fallback (offline)
SELFTEST PASS: 5 fixtures behaved as named (bad-* rejected, good-* accepted)   exit=0
VALID config_schemas/accounts.yaml
VALID config_schemas/accounts.json
VALIDATION PASS ...                                                            exit=0
```

Fallback was forced by shadowing `jsonschema` with an ImportError-raising module on `PYTHONPATH` — both modes exit 0 with identical verdicts, proving the documented offline fallback (anti-stall clause) is real, not aspirational.

## 6. Concerns

1. **STREAM-2/STREAM-9 path dependency**: both should reference `config_schemas/` (not `config/`) for the user-facing config; the Go `config` submodule remains the API's module-level config loader. Documented in README §"Why config_schemas/".
2. **`qa/results/` vs git-ignored `qa-results/`**: this report path per dispatch contract is trackable — conductor's commit should include it intentionally.
3. **Out of scope per brief (tracked, not done here)**: strict Go YAML↔JSON loader, users.conf renderer, directory provisioner, users.conf import/migration, golden-file tests, and the live container round-trip (RO upload denied / RW allowed) belong to ATM-002's API sync layer + ATM-009's integration suite; this stream delivered the schema/config/validator foundation they consume. The README §4 pipeline documents the contract the renderer must honor.
