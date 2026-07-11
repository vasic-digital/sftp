# Frequently Asked Questions

**Revision:** 1
**Last modified:** 2026-07-11T15:23:48Z

Quick answers about the enterprise SFTP management system. Deeper coverage: [guides](../guides/) · [tutorials](../tutorials/) · [architecture](../architecture/). Answers referencing not-yet-built components cite their ATM item.

## Table of contents

1. [What is this project?](#1-what-is-this-project)
2. [What do I need to install it?](#2-what-do-i-need-to-install-it)
3. [Do I need root or sudo?](#3-do-i-need-root-or-sudo)
4. [Which ports does it use?](#4-which-ports-does-it-use)
5. [How do I create the first administrator?](#5-how-do-i-create-the-first-administrator)
6. [How do I add an SFTP user?](#6-how-do-i-add-an-sftp-user)
7. [What do read_only and read_write mean?](#7-what-do-read_only-and-read_write-mean)
8. [Can a user be public / anonymous?](#8-can-a-user-be-public--anonymous)
9. [Why can't a user write into their home directory top level?](#9-why-cant-a-user-write-into-their-home-directory-top-level)
10. [Where is user data stored, and how do I back it up?](#10-where-is-user-data-stored-and-how-do-i-back-it-up)
11. [Are passwords stored in plaintext?](#11-are-passwords-stored-in-plaintext)
12. [Can I use SSH keys instead of passwords?](#12-can-i-use-ssh-keys-instead-of-passwords)
13. [Is there a web interface? A mobile app?](#13-is-there-a-web-interface-a-mobile-app)
14. [Is Firebase required?](#14-is-firebase-required)
15. [What languages is the UI available in?](#15-what-languages-is-the-ui-available-in)
16. [How do I upgrade safely?](#16-how-do-i-upgrade-safely)
17. [How do I get support / report a bug?](#17-how-do-i-get-support--report-a-bug)

## 1. What is this project?

An enterprise-grade SFTP management system: an `atmoz/sftp` server in rootless Podman, wrapped by a Go REST API (port 7722), a React web admin console, and KMP mobile clients (Android/iOS/HarmonyOS/AuroraOS). It manages accounts, permissions, audit logging, backups, and config — so you never hand-edit `users.conf` again.

## 2. What do I need to install it?

A Linux host with Podman ≥ 3.4 (host reference 5.7.1) and `podman-compose` (`pip3 install --user podman-compose`), plus an sftp client for testing. No Docker daemon, no Kubernetes. Full steps: [deployment guide](../guides/deployment_guide.md) or the 10-minute [quickstart](../tutorials/quickstart.md).

## 3. Do I need root or sudo?

No. The entire stack runs in **rootless Podman** under an unprivileged user, with `systemctl --user` units (§11.4.161). The only optional host-admin touchpoints are opening a firewall port and `loginctl enable-linger` (survive logout) — see [troubleshooting](../guides/troubleshooting_guide.md) §7–§8.

## 4. Which ports does it use?

- **7721/tcp** — SFTP (maps to container sshd port 22; configurable via `SFTP_PORT`).
- **7722/tcp** — REST API (configurable via `API_PORT`; bind to loopback or put behind TLS — see [security guide](../guides/security_guide.md) §8).

## 5. How do I create the first administrator?

Run `bash scripts/setup.sh` (ATM-006): it prompts for the super-admin username/password (never echoed, §11.4.10) and calls the single-shot bootstrap endpoint. A second bootstrap attempt returns `409` — by design.

## 6. How do I add an SFTP user?

Three ways, all equivalent: REST API (`POST /api/v1/accounts`), web console (Accounts → New), mobile app (Accounts → +). See [user management guide](../guides/user_management_guide.md) and [API quickstart](../tutorials/api_quickstart.md). Direct `users.conf` edits are not supported — the API re-renders that file from the DB.

## 7. What do read_only and read_write mean?

`read_only` — list and download only; uploads/renames/deletes are rejected (verified by a live container round-trip in ATM-003). `read_write` — full access inside the user's own home subtree. These are the only two permission values; the model is detailed in [permissions_model.md](../architecture/permissions_model.md).

## 8. Can a user be public / anonymous?

Only deliberately. `public` defaults to `false` everywhere; enabling it requires an explicit acknowledgement in the request/console, forces `read_only`, and is audit-logged. It is never on by default (operator mandate, ATM-002).

## 9. Why can't a user write into their home directory top level?

Because OpenSSH chroot requires the chroot directory to be root-owned and non-user-writable — this is what makes the confinement trustworthy. Each user gets a writable subdirectory (e.g. `upload/`) for their files; the provisioner creates it automatically. Details: [troubleshooting §4](../guides/troubleshooting_guide.md).

## 10. Where is user data stored, and how do I back it up?

All user homes live under the host data directory (`./data` by default, `SFTP_DATA_DIR`), mapped into the container. `bash scripts/backup.sh` (ATM-006) snapshots the DB + data + `users.conf`; `backup.sh restore <id>` restores. Delete-account retains data unless `purge_data=true`.

## 11. Are passwords stored in plaintext?

No. The API DB stores Argon2id hashes, and `users.conf` carries `crypt` hashes with the `:e` marker that atmoz/sftp supports. Plaintext never appears in logs, audit entries, or API responses (§11.4.10).

## 12. Can I use SSH keys instead of passwords?

Yes — recommended for production. Attach a public key to an account (`POST /api/v1/accounts/<user>/keys`, ATM-002); the container appends it to `authorized_keys` via the `.ssh/keys/` mount. A key-only account has an empty password field. Global `PasswordAuthentication no` is the production end-state.

## 13. Is there a web interface? A mobile app?

- **Web:** React/TypeScript SPA with OpenDesign light/dark themes (ATM-004).
- **Mobile:** KMP + Compose Multiplatform clients for Android, iOS, HarmonyOS, AuroraOS (ATM-005).

Both consume the same REST API and enforce the same guards (e.g. the public-flag acknowledgement).

## 14. Is Firebase required?

No — it is opt-in (ATM-007). Analytics/Performance/Crashlytics initialize only behind env flags, and App Distribution is used for mobile builds. Config files are fetched by `scripts/firebase_config.sh` into git-ignored paths; no Firebase credentials are ever committed.

## 15. What languages is the UI available in?

English first (`en`), via the i18n client stack on web and the in-project KMP i18n on mobile (ATM-004/005). The architecture keeps localization data-driven so additional languages drop in without code changes.

## 16. How do I upgrade safely?

Fetch + ff-merge, snapshot with `backup.sh`, pull new images, restart, and re-run the verification steps — migrations apply automatically on API start. Rollback = restore snapshot + pin previous image. Full procedure: [deployment guide §7–§8](../guides/deployment_guide.md).

## 17. How do I get support / report a bug?

Open an issue on the project repository. For deployment problems, first run the [troubleshooting guide](../guides/troubleshooting_guide.md) playbooks and include `podman logs` output and the failing verification step in your report.

---

## Sources verified (2026-07-11)

- Internal: `docs/Issues.md` ATM-001..ATM-011 · `docs/research/mvp/MVP.md` · `docs/CONTINUATION.md` · sibling docs in `docs/guides/`, `docs/tutorials/`, `docs/architecture/`.
- External fetched this revision: `https://github.com/atmoz/sftp` · `https://github.com/containers/podman-compose` · `https://docs.podman.io/en/latest/` (facts as cited in the guides).
