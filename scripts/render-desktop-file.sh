#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ]; then
  printf 'Usage: %s <exec> <icon> <output>\n' "$0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_DIR}/desktop/codex-ubuntu.desktop.in"
EXEC_PATH="$1"
ICON_NAME="$2"
OUTPUT_PATH="$3"

sed \
  -e "s|__EXEC__|${EXEC_PATH}|g" \
  -e "s|__ICON__|${ICON_NAME}|g" \
  "$TEMPLATE" >"$OUTPUT_PATH"
