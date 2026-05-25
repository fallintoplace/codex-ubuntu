#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SCRIPT="${CODEX_UBUNTU_DESKTOP_ROLLBACK_INSTALL_SCRIPT:-${PACKAGE_ROOT}/scripts/install-electron-local.sh}"

[ -x "$INSTALL_SCRIPT" ] || {
  printf 'Missing required helper script: %s\n' "$INSTALL_SCRIPT" >&2
  exit 1
}

exec "$INSTALL_SCRIPT" --rollback
