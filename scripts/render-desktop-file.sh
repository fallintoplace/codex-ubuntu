#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 3 ] && [ "$#" -ne 4 ]; then
  printf 'Usage: %s [template] <exec> <icon> <output>\n' "$0" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "$#" -eq 4 ]; then
  TEMPLATE="$1"
  EXEC_PATH="$2"
  ICON_NAME="$3"
  OUTPUT_PATH="$4"
else
  TEMPLATE="${REPO_DIR}/desktop/codex-ubuntu.desktop.in"
  EXEC_PATH="$1"
  ICON_NAME="$2"
  OUTPUT_PATH="$3"
fi

python3 - "$TEMPLATE" "$EXEC_PATH" "$ICON_NAME" "$OUTPUT_PATH" <<'PY'
from pathlib import Path
import sys

template_path = Path(sys.argv[1])
exec_path = sys.argv[2]
icon_name = sys.argv[3]
output_path = Path(sys.argv[4])

contents = template_path.read_text(encoding="utf-8")
contents = contents.replace("__EXEC__", exec_path)
contents = contents.replace("__ICON__", icon_name)
output_path.write_text(contents, encoding="utf-8")
PY
