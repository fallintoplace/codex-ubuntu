#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_SCRIPT="${CODEX_UBUNTU_DESKTOP_BOOTSTRAP_BUILD_SCRIPT:-${PACKAGE_ROOT}/scripts/build-electron-local.sh}"
INSTALL_SCRIPT="${CODEX_UBUNTU_DESKTOP_BOOTSTRAP_INSTALL_SCRIPT:-${PACKAGE_ROOT}/scripts/install-electron-local.sh}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
BUILD_ROOT="${CODEX_UBUNTU_ELECTRON_BUILD_ROOT:-${STATE_HOME}/codex-ubuntu/electron-build/current}"
BUILD_APP_ROOT="${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT:-${BUILD_ROOT}/codex-app}"
REFERENCE_BUILDER_DIR="${CODEX_UBUNTU_REFERENCE_BUILDER_DIR:-${CACHE_HOME}/codex-ubuntu/reference-builder}"

usage() {
  cat <<EOF
Usage: codex-desktop-bootstrap [build-electron-local options] [path/to/Codex.dmg]

Build and install the local Electron desktop payload for the current user.

Examples:
  codex-desktop-bootstrap
  codex-desktop-bootstrap --download-upstream
  codex-desktop-bootstrap /path/to/Codex.dmg
EOF
}

require_script() {
  local script_path="$1"
  [ -x "$script_path" ] || {
    printf 'Missing required helper script: %s\n' "$script_path" >&2
    exit 1
  }
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

if [ "$(id -u)" -eq 0 ]; then
  printf 'Run codex-desktop-bootstrap as your desktop user, not as root.\n' >&2
  exit 1
fi

require_script "$BUILD_SCRIPT"
require_script "$INSTALL_SCRIPT"

mkdir -p "$(dirname "$BUILD_ROOT")" "$(dirname "$REFERENCE_BUILDER_DIR")"

CODEX_UBUNTU_ELECTRON_BUILD_ROOT="$BUILD_ROOT" \
  CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT="$BUILD_APP_ROOT" \
  CODEX_UBUNTU_REFERENCE_BUILDER_DIR="$REFERENCE_BUILDER_DIR" \
  CODEX_UBUNTU_IMPORT_AFTER_BUILD=0 \
  CODEX_UBUNTU_SUPPRESS_BUILD_NEXT_STEPS=1 \
  "$BUILD_SCRIPT" "$@"

CODEX_UBUNTU_ELECTRON_INSTALL_MODE=system-package \
  "$INSTALL_SCRIPT" "$BUILD_APP_ROOT"

printf 'Built and installed the local Electron desktop payload at %s\n' "$BUILD_APP_ROOT"
printf 'Launch Codex Desktop from the app grid.\n'
