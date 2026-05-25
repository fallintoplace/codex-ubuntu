#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${HOME}/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="${DATA_HOME}/applications"
ICON_DIR="${DATA_HOME}/icons/hicolor/scalable/apps"

mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

install -m 755 "${REPO_DIR}/launcher/codex-ubuntu" "${BIN_DIR}/codex-ubuntu"
install -m 644 "${REPO_DIR}/desktop/codex-ubuntu.svg" "${ICON_DIR}/codex-ubuntu.svg"
"${REPO_DIR}/scripts/render-desktop-file.sh" "${BIN_DIR}/codex-ubuntu" "codex-ubuntu" "${APP_DIR}/codex-ubuntu.desktop"

update-desktop-database "${APP_DIR}" >/dev/null 2>&1 || true
gtk-update-icon-cache -f -t "${DATA_HOME}/icons/hicolor" >/dev/null 2>&1 || true

printf 'Installed local launcher to %s\n' "${BIN_DIR}/codex-ubuntu"
