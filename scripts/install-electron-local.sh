#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${HOME}/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="${DATA_HOME}/applications"
ICON_DIR="${DATA_HOME}/icons/hicolor/256x256/apps"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-ubuntu"
LOCAL_OPT_ROOT="${HOME}/.local/opt/codex-ubuntu"
TARGET_APP_ROOT="${LOCAL_OPT_ROOT}/current/codex-app"
ACTIVE_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy"
LEGACY_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy-legacy"
PRIMARY_DESKTOP="${APP_DIR}/codex-desktop.desktop"
LEGACY_DESKTOP="${APP_DIR}/codex-desktop-legacy.desktop"
PRIMARY_ICON="${ICON_DIR}/codex-desktop.png"
REPO_WRAPPER="${REPO_DIR}/electron/codex-desktop"
CONFIG_FILE="${CONFIG_DIR}/electron.env"
DEFAULT_STAGE_APP_ROOT="${REPO_DIR}/dist/electron-build/current/codex-app"
SOURCE_APP_ROOT="${1:-${SOURCE_APP_ROOT:-${CODEX_UBUNTU_ELECTRON_APP_ROOT:-}}}"

usage() {
  cat <<EOF
Usage: scripts/install-electron-local.sh [SOURCE_APP_ROOT]

Install the repo-owned Electron launcher and a local Codex Desktop app root.

Source resolution order:
  1. SOURCE_APP_ROOT positional argument
  2. SOURCE_APP_ROOT environment variable
  3. CODEX_UBUNTU_ELECTRON_APP_ROOT environment variable
  4. ${DEFAULT_STAGE_APP_ROOT}
  5. A detected legacy launcher app root
  6. \$HOME/codex-desktop-linux/codex-app
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR" "$CONFIG_DIR" "$(dirname "$TARGET_APP_ROOT")"

detect_config_value() {
  local wrapper_path="$1"
  local field="$2"

  python3 - "$wrapper_path" "$field" <<'PY'
from pathlib import Path
import re
import sys

wrapper = Path(sys.argv[1])
field = sys.argv[2]
contents = wrapper.read_text(encoding="utf-8")

patterns = {
    "app_root": r'APP_ROOT="([^"]+)"',
    "node_bin_dir": r'([A-Za-z0-9_/\.\-\$]+/\.nvm/versions/node/[^:"]+/bin)',
}

match = re.search(patterns[field], contents)
if not match:
    raise SystemExit(1)

value = match.group(1).replace("$HOME", str(Path.home()))
print(value)
PY
}

wrapper_already_points_to_repo() {
  [ -f "$ACTIVE_WRAPPER" ] || return 1
  grep -Fq "$REPO_WRAPPER" "$ACTIVE_WRAPPER" 2>/dev/null
}

resolve_source_app_root() {
  local candidate=""

  if [ -n "$SOURCE_APP_ROOT" ]; then
    candidate="$SOURCE_APP_ROOT"
    [ -x "${candidate}/start.sh" ] || {
      printf 'Provided Electron app root is invalid: %s\n' "$candidate" >&2
      exit 1
    }
    printf '%s\n' "$candidate"
    return 0
  fi

  for candidate in \
    "$DEFAULT_STAGE_APP_ROOT" \
    "$(detect_config_value "$LEGACY_WRAPPER" app_root 2>/dev/null || true)" \
    "${HOME}/codex-desktop-linux/codex-app"
  do
    [ -n "$candidate" ] || continue
    if [ -x "${candidate}/start.sh" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  printf 'Could not find a usable Electron app root to install.\n' >&2
  exit 1
}

resolve_node_bin_dir() {
  local source_root="$1"
  local detected=""

  if [ -x "${source_root}/resources/node-runtime/bin/node" ]; then
    return 0
  fi

  detected="$(detect_config_value "$LEGACY_WRAPPER" node_bin_dir 2>/dev/null || true)"
  if [ -n "$detected" ] && [ -x "${detected}/node" ]; then
    printf '%s\n' "$detected"
  fi
}

copy_app_root_into_local_opt() {
  local source_root="$1"
  local temp_target="${TARGET_APP_ROOT}.tmp.$$"

  if [ "$(realpath "$source_root")" = "$(realpath -m "$TARGET_APP_ROOT")" ]; then
    return 0
  fi

  rm -rf "$temp_target"
  mkdir -p "$(dirname "$temp_target")"
  cp -a "$source_root" "$temp_target"
  rm -rf "$TARGET_APP_ROOT"
  mv "$temp_target" "$TARGET_APP_ROOT"
}

write_config_file() {
  local app_root="$1"
  local node_bin_dir="$2"

  {
    printf 'CODEX_UBUNTU_ELECTRON_APP_ROOT=%q\n' "$app_root"
    if [ -n "$node_bin_dir" ]; then
      printf 'CODEX_UBUNTU_NODE_BIN_DIR=%q\n' "$node_bin_dir"
    fi
  } >"$CONFIG_FILE"
}

write_primary_wrapper() {
  cat >"$ACTIVE_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$(printf '%q' "$REPO_WRAPPER")" "\$@"
EOF
  chmod 755 "$ACTIVE_WRAPPER"
}

write_primary_desktop_entry() {
  "${REPO_DIR}/scripts/render-desktop-file.sh" \
    "${REPO_DIR}/desktop/codex-desktop.desktop.in" \
    "$ACTIVE_WRAPPER" \
    "codex-desktop" \
    "$PRIMARY_DESKTOP"
}

write_legacy_desktop_entry() {
  cat >"$LEGACY_DESKTOP" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Codex Desktop (Legacy)
Comment=Launch the previous Codex Desktop launcher
Exec=$(printf '%q' "$LEGACY_WRAPPER") %u
Terminal=false
Categories=Development;IDE;
StartupNotify=true
StartupWMClass=codex-desktop
X-GNOME-WMClass=codex-desktop
Icon=codex-desktop
Keywords=Desktop;Legacy;Rollback;
EOF
}

install_primary_icon() {
  local source_icon="$1/.codex-linux/codex-desktop.png"

  if [ ! -f "$source_icon" ]; then
    printf 'Missing required icon in Electron app root: %s\n' "$source_icon" >&2
    exit 1
  fi

  cp "$source_icon" "$PRIMARY_ICON"
}

main() {
  local source_root=""
  local node_bin_dir=""

  if [ -f "$ACTIVE_WRAPPER" ] && [ ! -f "$LEGACY_WRAPPER" ] && ! wrapper_already_points_to_repo; then
    mv "$ACTIVE_WRAPPER" "$LEGACY_WRAPPER"
  fi

  source_root="$(resolve_source_app_root)"
  node_bin_dir="$(resolve_node_bin_dir "$source_root" || true)"

  copy_app_root_into_local_opt "$source_root"
  install_primary_icon "$TARGET_APP_ROOT"
  write_config_file "$TARGET_APP_ROOT" "${node_bin_dir:-}"
  write_primary_wrapper
  write_primary_desktop_entry

  if [ -f "$LEGACY_WRAPPER" ]; then
    write_legacy_desktop_entry
  else
    rm -f "$LEGACY_DESKTOP"
  fi

  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  gtk-update-icon-cache -f -t "${DATA_HOME}/icons/hicolor" >/dev/null 2>&1 || true

  printf 'Installed repo-owned Electron launcher to %s\n' "$ACTIVE_WRAPPER"
  printf 'Configured Electron app root as %s\n' "$TARGET_APP_ROOT"
  if [ -f "$LEGACY_WRAPPER" ]; then
    printf 'Legacy rollback launcher preserved at %s\n' "$LEGACY_WRAPPER"
  fi
}

main "$@"
