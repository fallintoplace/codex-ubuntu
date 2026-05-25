#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_ROOT="${1:-${SOURCE_ROOT:-${CODEX_UBUNTU_ELECTRON_APP_ROOT:-$HOME/codex-desktop-linux/codex-app}}}"
VENDOR_ROOT="${REPO_DIR}/electron/vendor/current"
MANIFEST_PATH="${REPO_DIR}/electron/manifest/current.local.json"

usage() {
  cat <<'EOF'
Usage: scripts/import-electron-payload.sh [SOURCE_ROOT]

Import the minimum local Electron payload slice into the repo's ignored vendor area.

Default source root:
  $HOME/codex-desktop-linux/codex-app
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_file() {
  local relative_path="$1"
  local absolute_path="${SOURCE_ROOT}/${relative_path}"
  if [ ! -f "$absolute_path" ]; then
    printf 'Missing required payload file: %s\n' "$absolute_path" >&2
    exit 1
  fi
}

copy_relative_file() {
  local relative_path="$1"
  local source_path="${SOURCE_ROOT}/${relative_path}"
  local target_path="${VENDOR_ROOT}/${relative_path}"
  mkdir -p "$(dirname "$target_path")"
  cp "$source_path" "$target_path"
}

if [ ! -d "$SOURCE_ROOT" ]; then
  printf 'Payload source root does not exist: %s\n' "$SOURCE_ROOT" >&2
  exit 1
fi

required_files=(
  "start.sh"
  "version"
  "resources/app.asar"
  "resources/codex-linux-build-info.json"
  ".codex-linux/codex-desktop.png"
)

optional_files=(
  ".codex-linux/build-info.json"
)

for relative_path in "${required_files[@]}"; do
  require_file "$relative_path"
done

rm -rf "$VENDOR_ROOT"
mkdir -p "$VENDOR_ROOT"

for relative_path in "${required_files[@]}"; do
  copy_relative_file "$relative_path"
done

for relative_path in "${optional_files[@]}"; do
  if [ -f "${SOURCE_ROOT}/${relative_path}" ]; then
    copy_relative_file "$relative_path"
  fi
done

python3 - "$SOURCE_ROOT" "$VENDOR_ROOT" "$MANIFEST_PATH" <<'PY'
from __future__ import annotations

import datetime as dt
import hashlib
import json
import pathlib
import sys

source_root = pathlib.Path(sys.argv[1]).resolve()
vendor_root = pathlib.Path(sys.argv[2]).resolve()
manifest_path = pathlib.Path(sys.argv[3]).resolve()

copied_files = [
    pathlib.Path("start.sh"),
    pathlib.Path("version"),
    pathlib.Path("resources/app.asar"),
    pathlib.Path("resources/codex-linux-build-info.json"),
    pathlib.Path(".codex-linux/codex-desktop.png"),
    pathlib.Path(".codex-linux/build-info.json"),
]

def sha256_of(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def load_json_if_present(path: pathlib.Path):
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"_warning": "file exists but is not valid JSON"}

files = []
for relative_path in copied_files:
    imported_path = vendor_root / relative_path
    if not imported_path.is_file():
        continue
    files.append(
        {
            "path": relative_path.as_posix(),
            "sizeBytes": imported_path.stat().st_size,
            "sha256": sha256_of(imported_path),
        }
    )

version = (vendor_root / "version").read_text(encoding="utf-8").strip()
linux_build_info = load_json_if_present(vendor_root / "resources/codex-linux-build-info.json")
local_build_info = load_json_if_present(vendor_root / ".codex-linux/build-info.json")

manifest = {
    "schemaVersion": 1,
    "importedAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "sourceRoot": str(source_root),
    "version": version,
    "files": files,
    "linuxBuildInfo": linux_build_info,
    "localBuildInfo": local_build_info,
}

manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
PY

printf 'Imported minimum Electron payload slice from %s\n' "$SOURCE_ROOT"
printf 'Copied files into %s\n' "$VENDOR_ROOT"
printf 'Wrote manifest %s\n' "$MANIFEST_PATH"
