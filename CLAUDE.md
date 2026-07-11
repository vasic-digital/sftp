## INHERITED FROM constitution/CLAUDE.md

All rules in `constitution/CLAUDE.md` (and the `constitution/Constitution.md` it references) apply unconditionally.
Project-specific rules below extend them — they do NOT weaken any universal clause. When this file disagrees with the constitution submodule, the constitution wins.

@constitution/CLAUDE.md

---

## SFTP Service — Project-Specific Rules

- This project deploys an SFTP server using `atmoz/sftp` via Podman/Docker Compose.
- All user configuration lives in `users.conf` and `.env` at the project root.
- The SSH daemon port is mapped from the host port defined in `.env` (default 7721).
- This is a containerized deployment — no Go/Rust/Python application code lives here.
