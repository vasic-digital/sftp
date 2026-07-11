#!/usr/bin/env bash
# ============================================================================
# sftp_ctl.sh — SFTP Enterprise stack control plane (rootless Podman)
# ----------------------------------------------------------------------------
# Purpose:
#   Lifecycle control for the SFTP Enterprise compose stack
#   (deploy/docker-compose.yml) via ROOTLESS podman-compose, plus install /
#   uninstall of the user-scoped systemd unit rendered from
#   deploy/systemd/sftp.service.template.
#
# Usage:
#   scripts/sftp_ctl.sh <command> [options]
#
#   Commands:
#     start            Start the stack (podman-compose up -d)
#     stop             Stop the stack (podman-compose down)
#     restart          stop + start
#     status           Container states + host port listeners (exit 0 always)
#     logs [service]   Follow logs (all services or one: sftp|api|postgres)
#     ps               podman-compose ps table
#     install          Render + install + enable --now the systemd --user unit
#     uninstall        disable --now + remove the systemd --user unit
#     --help           This help
#
# Inputs:
#   .env (optional) — SFTP_PORT (default 7721), API_PORT (default 7722).
#     Parsed as plain KEY=VALUE lines ONLY; the file is never `source`d.
#   deploy/docker-compose.yml (read-only).
#   deploy/systemd/sftp.service.template (for `install`).
#
# Outputs:
#   Human-readable status on stdout. `install` writes
#   ~/.config/systemd/user/sftp.service.
#
# Side-effects:
#   start/stop/restart/logs/ps mutate CONTAINER state only (rootless, per-user).
#   install/uninstall mutate the CALLING USER's ~/.config/systemd/user only.
#   NEVER touches root, sudo, or rootful docker (§11.4.161).
#
# Dependencies:
#   bash ≥ 4, podman-compose (or `podman compose`), podman, systemctl --user
#   (install/uninstall/status only), ss or netstat (status port probe — optional).
#
# Cross-references:
#   docs/scripts/sftp_ctl.md · deploy/docker-compose.yml ·
#   deploy/systemd/sftp.service.template · scripts/setup.sh ·
#   constitution §11.4.161 (rootless containers), §11.4.18 (script docs),
#   §11.4.177 (project-root from script location), §12 (host safety).
# ============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/docker-compose.yml"
TEMPLATE="$ROOT/deploy/systemd/sftp.service.template"
UNIT_NAME="sftp.service"
USER_UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="$USER_UNIT_DIR/$UNIT_NAME"

# --- safe .env parsing (KEY=VALUE lines only, never sourced) -----------------
env_get() {
    # env_get <KEY> <DEFAULT>
    local key="$1" default="$2" line value
    if [[ -f "$ROOT/.env" ]]; then
        line="$(grep -E "^${key}=" "$ROOT/.env" | tail -n 1 || true)"
        if [[ -n "$line" ]]; then
            value="${line#*=}"
            # Strip inline comment and surrounding whitespace/dquotes
            value="${value%%#*}"
            value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
            if [[ -n "$value" ]]; then
                printf '%s' "$value"
                return 0
            fi
        fi
    fi
    printf '%s' "$default"
}

SFTP_PORT="$(env_get SFTP_PORT 7721)"
API_PORT="$(env_get API_PORT 7722)"

# --- compose runner: prefer podman-compose, fall back to `podman compose` ----
compose() {
    if command -v podman-compose >/dev/null 2>&1; then
        podman-compose -f "$COMPOSE_FILE" "$@"
    elif podman compose version >/dev/null 2>&1; then
        podman compose -f "$COMPOSE_FILE" "$@"
    else
        echo "ERROR: neither podman-compose nor 'podman compose' available." >&2
        echo "Install: pip install podman-compose  (rootless podman is required, §11.4.161)" >&2
        return 127
    fi
}

port_listening() {
    # port_listening <port> → prints LISTENING/not-listening
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
            echo "LISTENING"
            return 0
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
            echo "LISTENING"
            return 0
        fi
    else
        echo "unknown (no ss/netstat)"
        return 0
    fi
    echo "not-listening"
}

usage() {
    sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

cmd_start() {
    echo "(sftp_ctl) starting stack via rootless podman-compose ..."
    compose up -d
    echo "(sftp_ctl) start requested. Verify with: scripts/sftp_ctl.sh status"
}

cmd_stop() {
    echo "(sftp_ctl) stopping stack ..."
    compose down
    echo "(sftp_ctl) stack stopped."
}

cmd_status() {
    echo "=== SFTP Enterprise stack status ==="
    echo "Project root : $ROOT"
    echo "Compose file : $COMPOSE_FILE"
    echo
    if [[ -f "$COMPOSE_FILE" ]]; then
        echo "--- containers (podman ps -a, compose project) ---"
        if compose ps 2>/dev/null; then
            true
        else
            echo "(no containers known to the compose project — stack not started?)"
        fi
    else
        echo "WARNING: compose file missing: $COMPOSE_FILE" >&2
    fi
    echo
    echo "--- host port listeners ---"
    echo "SFTP_PORT=$SFTP_PORT → $(port_listening "$SFTP_PORT")"
    echo "API_PORT=$API_PORT → $(port_listening "$API_PORT")"
    echo
    echo "--- systemd --user unit ---"
    if command -v systemctl >/dev/null 2>&1; then
        if [[ -f "$UNIT_PATH" ]]; then
            systemctl --user is-enabled "$UNIT_NAME" 2>/dev/null | sed 's/^/enabled: /' || true
            systemctl --user is-active "$UNIT_NAME" 2>/dev/null | sed 's/^/active: /' || true
        else
            echo "unit not installed (run: scripts/sftp_ctl.sh install)"
        fi
    else
        echo "systemctl not available on this host"
    fi
    echo
    echo "(status is informational — exit 0 regardless of stack state)"
    return 0
}

cmd_logs() {
    local service="${1:-}"
    if [[ -n "$service" ]]; then
        compose logs -f "$service"
    else
        compose logs -f
    fi
}

cmd_install() {
    if [[ ! -f "$TEMPLATE" ]]; then
        echo "ERROR: systemd template missing: $TEMPLATE" >&2
        return 1
    fi
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: systemctl not found — cannot install user unit." >&2
        return 1
    fi
    mkdir -p "$USER_UNIT_DIR"
    # Render @PROJECT_ROOT@ with the real root; escape & and | for sed
    local escaped_root
    escaped_root="$(printf '%s' "$ROOT" | sed -e 's/[&|]/\\&/g')"
    sed "s|@PROJECT_ROOT@|$escaped_root|g" "$TEMPLATE" > "$UNIT_PATH.tmp"
    mv "$UNIT_PATH.tmp" "$UNIT_PATH"
    echo "(sftp_ctl) unit rendered → $UNIT_PATH"
    systemctl --user daemon-reload
    systemctl --user enable --now "$UNIT_NAME"
    echo "(sftp_ctl) $UNIT_NAME installed, enabled, and started for user '$USER'."
    echo "(sftp_ctl) NOTE: for boot-time start without login, the operator may"
    echo "  choose to enable lingering: loginctl enable-linger $USER"
    echo "  (an operator decision — this script never touches it, §11.4.122)."
}

cmd_uninstall() {
    if [[ -f "$UNIT_PATH" ]]; then
        systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
        rm -f "$UNIT_PATH"
        systemctl --user daemon-reload
        echo "(sftp_ctl) $UNIT_NAME disabled and removed from $USER_UNIT_DIR."
    else
        echo "(sftp_ctl) $UNIT_NAME not installed — nothing to do (idempotent)."
    fi
    echo "(sftp_ctl) containers left untouched; stop the stack with:"
    echo "  scripts/sftp_ctl.sh stop"
}

main() {
    local cmd="${1:---help}"
    case "$cmd" in
        start)           cmd_start ;;
        stop)            cmd_stop ;;
        restart)         cmd_stop; cmd_start ;;
        status)          cmd_status ;;
        logs)            shift; cmd_logs "${1:-}" ;;
        ps)              compose ps ;;
        install)         cmd_install ;;
        uninstall)       cmd_uninstall ;;
        --help|-h|help)  usage ;;
        *)
            echo "ERROR: unknown command '$cmd'" >&2
            usage >&2
            return 2
            ;;
    esac
}

main "$@"
