# deploy/ — Deployment assets

Rootless-Podman compose stack (`docker-compose.yml`: sftp + postgres + api) and systemd units (`systemd/`, from STREAM-6). Run: `podman-compose -f deploy/docker-compose.yml up -d` with a filled `.env` at repo root.

Owned by STREAM-1 (ATM-001) per `docs/plans/master_implementation_plan.md`.
