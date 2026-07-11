# ============================================================================
# SFTP Enterprise — management API image (rootless-Podman compatible)
# ----------------------------------------------------------------------------
# Build context MUST be the REPOSITORY ROOT, not api/, because api/go.mod
# resolves the 19 owned Go submodules via `replace digital.vasic.* => ../<dir>`.
# Build (from repo root):
#   podman build -f api/Dockerfile -t sftp-api:dev .
# Run:
#   podman run --rm -p 127.0.0.1:7722:7722 \
#     -e JWT_SECRET=<32+ chars> -e SUPERADMIN_PASSWORD=<secret> sftp-api:dev
#
# The store uses modernc.org/sqlite (pure Go) — CGO is DISABLED, so the final
# image needs no libc-linked sqlite and no gcc in the builder.
# ============================================================================

# --- Stage 1: build ---------------------------------------------------------
FROM golang:1.26-bookworm AS builder

WORKDIR /src

# Copy the 19 owned submodules the go.mod replace directives point at, plus
# the api module itself. Copy go.mod/go.sum first for layer caching.
COPY auth/        ./auth/
COPY cache/       ./cache/
COPY challenges/  ./challenges/
COPY concurrency/ ./concurrency/
COPY config/      ./config/
COPY containers/  ./containers/
COPY database/    ./database/
COPY discovery/   ./discovery/
COPY docs_chain/  ./docs_chain/
COPY filesystem/  ./filesystem/
COPY formatters/  ./formatters/
COPY helixqa/     ./helixqa/
COPY http3/       ./http3/
COPY i18n/        ./i18n/
COPY mdns/        ./mdns/
COPY middleware/  ./middleware/
COPY observability/ ./observability/
COPY ratelimiter/ ./ratelimiter/
COPY recovery/    ./recovery/
COPY security/    ./security/
COPY storage/     ./storage/
COPY streaming/   ./streaming/
COPY watcher/     ./watcher/

COPY api/go.mod api/go.sum ./api/
WORKDIR /src/api
RUN go mod download

COPY api/ ./

# Pure-Go static build (modernc.org/sqlite → no CGO).
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o /out/sftp-api ./cmd/sftp-api

# --- Stage 2: runtime -------------------------------------------------------
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Non-root runtime user (rootless-friendly; no privilege required).
RUN useradd --system --uid 1001 --home-dir /app --shell /usr/sbin/nologin sftpapi

WORKDIR /app
COPY --from=builder /out/sftp-api /usr/local/bin/sftp-api

# Runtime data dir (SQLite + rendered users.conf) — mounted as a volume.
RUN mkdir -p /app/data && chown -R sftpapi:sftpapi /app

USER sftpapi

ENV API_BIND=0.0.0.0 \
    API_PORT=7722 \
    DB_PATH=/app/data/sftp.db \
    USERS_CONF_PATH=/app/data/users.conf

EXPOSE 7722

VOLUME ["/app/data"]

ENTRYPOINT ["/usr/local/bin/sftp-api"]
