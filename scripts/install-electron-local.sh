#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${HOME}/.local/bin"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="${DATA_HOME}/applications"
ICON_DIR="${DATA_HOME}/icons/hicolor/256x256/apps"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-ubuntu"
LOCAL_OPT_ROOT="${HOME}/.local/opt/codex-ubuntu"
RELEASES_DIR="${LOCAL_OPT_ROOT}/releases"
CURRENT_RELEASE_LINK="${LOCAL_OPT_ROOT}/current"
PREVIOUS_RELEASE_LINK="${LOCAL_OPT_ROOT}/previous"
TARGET_APP_ROOT="${LOCAL_OPT_ROOT}/current/codex-app"
ACTIVE_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy"
LEGACY_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy-legacy"
ROLLBACK_WRAPPER="${BIN_DIR}/codex-desktop-rollback"
PRIMARY_DESKTOP="${APP_DIR}/codex-desktop.desktop"
LEGACY_DESKTOP="${APP_DIR}/codex-desktop-legacy.desktop"
PRIMARY_ICON="${ICON_DIR}/codex-desktop.png"
REPO_WRAPPER="${REPO_DIR}/electron/codex-desktop"
REPO_ROLLBACK_SCRIPT="${REPO_DIR}/scripts/codex-desktop-rollback.sh"
CONFIG_FILE="${CONFIG_DIR}/electron.env"
DEFAULT_STAGE_APP_ROOT="${REPO_DIR}/dist/electron-build/current/codex-app"
SOURCE_APP_ROOT="${1:-${SOURCE_APP_ROOT:-${CODEX_UBUNTU_ELECTRON_APP_ROOT:-}}}"
INSTALL_MODE="${CODEX_UBUNTU_ELECTRON_INSTALL_MODE:-local-launcher}"
ROLLBACK_ONLY=0

usage() {
  cat <<EOF
Usage: scripts/install-electron-local.sh [SOURCE_APP_ROOT]

Install the repo-owned Electron launcher and a local Codex Desktop app root.

Install modes:
  local-launcher  Install local wrappers, desktop entries, and icon state (default)
  system-package  Only update the local app root and config for a system package

Source resolution order:
  1. SOURCE_APP_ROOT positional argument
  2. SOURCE_APP_ROOT environment variable
  3. CODEX_UBUNTU_ELECTRON_APP_ROOT environment variable
  4. ${DEFAULT_STAGE_APP_ROOT}
  5. A detected legacy launcher app root
  6. \$HOME/codex-desktop-linux/codex-app

Options:
  --rollback        Swap the current and previous installed releases
EOF
}

parse_args() {
  local positional_count=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --help | -h)
        usage
        exit 0
        ;;
      --rollback)
        ROLLBACK_ONLY=1
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
      *)
        positional_count=$((positional_count + 1))
        if [ "$positional_count" -gt 1 ]; then
          printf 'Only one SOURCE_APP_ROOT may be provided.\n' >&2
          exit 1
        fi
        SOURCE_APP_ROOT="$1"
        ;;
    esac
    shift
  done
}

validate_install_mode() {
  case "$INSTALL_MODE" in
    local-launcher | system-package) ;;
    *)
      printf 'Unsupported CODEX_UBUNTU_ELECTRON_INSTALL_MODE: %s\n' "$INSTALL_MODE" >&2
      exit 1
      ;;
  esac
}

prepare_directories() {
  mkdir -p "$CONFIG_DIR" "$RELEASES_DIR"
  if [ "$INSTALL_MODE" = "local-launcher" ]; then
    mkdir -p "$BIN_DIR" "$APP_DIR" "$ICON_DIR"
  fi
}

parse_args "$@"
validate_install_mode
prepare_directories
chmod 700 "$CONFIG_DIR" >/dev/null 2>&1 || true

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

read_config_value() {
  local field="$1"

  [ -f "$CONFIG_FILE" ] || return 1

  python3 - "$CONFIG_FILE" "$field" <<'PY'
from pathlib import Path
import shlex
import sys

config_path = Path(sys.argv[1])
field = sys.argv[2]

allowed_keys = {
    "CODEX_UBUNTU_ELECTRON_APP_ROOT",
    "CODEX_UBUNTU_NODE_BIN_DIR",
}

for raw_line in config_path.read_text(encoding="utf-8").splitlines():
    stripped = raw_line.strip()
    if not stripped or stripped.startswith("#") or "=" not in raw_line:
        continue
    key, raw_value = raw_line.split("=", 1)
    key = key.strip()
    if key not in allowed_keys or key != field:
        continue

    raw_value = raw_value.strip()
    if not raw_value:
        print("")
        raise SystemExit(0)

    tokens = shlex.split(raw_value, posix=True)
    if len(tokens) != 1:
        raise SystemExit(1)
    print(tokens[0])
    raise SystemExit(0)

raise SystemExit(1)
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
    "${HOME}/codex-desktop-linux/codex-app"; do
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

  detected="$(read_config_value CODEX_UBUNTU_NODE_BIN_DIR 2>/dev/null || true)"
  if [ -n "$detected" ] && [ -x "${detected}/node" ]; then
    printf '%s\n' "$detected"
    return 0
  fi

  detected="$(detect_config_value "$LEGACY_WRAPPER" node_bin_dir 2>/dev/null || true)"
  if [ -n "$detected" ] && [ -x "${detected}/node" ]; then
    printf '%s\n' "$detected"
  fi
}

write_config_file() {
  local app_root="$1"
  local node_bin_dir="$2"
  local temp_config="${CONFIG_FILE}.tmp.$$"

  {
    printf 'CODEX_UBUNTU_ELECTRON_APP_ROOT=%q\n' "$app_root"
    if [ -n "$node_bin_dir" ]; then
      printf 'CODEX_UBUNTU_NODE_BIN_DIR=%q\n' "$node_bin_dir"
    fi
  } >"$temp_config"

  chmod 600 "$temp_config"
  mv "$temp_config" "$CONFIG_FILE"
}

sanitize_release_component() {
  python3 - "$1" <<'PY'
import re
import sys

value = sys.argv[1].strip()
if not value:
    print("snapshot")
    raise SystemExit(0)

sanitized = re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-.")
print(sanitized or "snapshot")
PY
}

read_source_release_version() {
  local source_root="$1"
  local version_file="${source_root}/version"

  if [ -f "$version_file" ]; then
    head -n 1 "$version_file"
    return 0
  fi

  printf 'snapshot\n'
}

generate_release_id() {
  local source_root="$1"
  local source_version=""
  local sanitized_version=""
  local timestamp=""

  source_version="$(read_source_release_version "$source_root")"
  sanitized_version="$(sanitize_release_component "$source_version")"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s-%s\n' "$timestamp" "$sanitized_version"
}

validate_app_root() {
  local app_root="$1"
  local required_path=""

  for required_path in \
    "${app_root}/start.sh" \
    "${app_root}/version" \
    "${app_root}/resources/app.asar" \
    "${app_root}/resources/codex-linux-build-info.json" \
    "${app_root}/.codex-linux/codex-desktop.png"; do
    [ -e "$required_path" ] || {
      printf 'Expected app root file is missing: %s\n' "$required_path" >&2
      exit 1
    }
  done
}

resolve_link_target() {
  local link_path="$1"

  [ -L "$link_path" ] || return 1
  [ -e "$link_path" ] || return 1
  realpath "$link_path"
}

update_symlink_atomically() {
  local target_path="$1"
  local link_path="$2"
  local temp_link="${link_path}.tmp.$$"

  rm -f "$temp_link"
  ln -s "$target_path" "$temp_link"
  mv -Tf "$temp_link" "$link_path"
}

remove_symlink_if_present() {
  local link_path="$1"

  if [ -L "$link_path" ] || [ -e "$link_path" ]; then
    rm -f "$link_path"
  fi
}

cleanup_stale_releases() {
  local keep_current=""
  local keep_previous=""
  local release_dir=""

  keep_current="$(resolve_link_target "$CURRENT_RELEASE_LINK" 2>/dev/null || true)"
  keep_previous="$(resolve_link_target "$PREVIOUS_RELEASE_LINK" 2>/dev/null || true)"

  [ -d "$RELEASES_DIR" ] || return 0

  while IFS= read -r release_dir; do
    [ -n "$release_dir" ] || continue
    if [ "$release_dir" = "$keep_current" ] || [ "$release_dir" = "$keep_previous" ]; then
      continue
    fi
    rm -rf "$release_dir"
  done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
}

install_release_into_local_opt() {
  local source_root="$1"
  local release_id=""
  local temp_release_dir=""
  local final_release_dir=""
  local current_target=""

  if [ -e "$TARGET_APP_ROOT" ] && [ "$(realpath "$source_root")" = "$(realpath "$TARGET_APP_ROOT")" ]; then
    return 0
  fi

  release_id="$(generate_release_id "$source_root")"
  temp_release_dir="${RELEASES_DIR}/.${release_id}.tmp.$$"
  final_release_dir="${RELEASES_DIR}/${release_id}"

  rm -rf "$temp_release_dir"
  mkdir -p "$temp_release_dir"
  cp -a "$source_root" "${temp_release_dir}/codex-app"
  validate_app_root "${temp_release_dir}/codex-app"
  mv "$temp_release_dir" "$final_release_dir"

  current_target="$(resolve_link_target "$CURRENT_RELEASE_LINK" 2>/dev/null || true)"
  if [ -n "$current_target" ] && [ "$current_target" != "$final_release_dir" ]; then
    update_symlink_atomically "$current_target" "$PREVIOUS_RELEASE_LINK"
  fi
  update_symlink_atomically "$final_release_dir" "$CURRENT_RELEASE_LINK"
  cleanup_stale_releases
}

write_primary_wrapper() {
  cat >"$ACTIVE_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$(printf '%q' "$REPO_WRAPPER")" "\$@"
EOF
  chmod 755 "$ACTIVE_WRAPPER"
}

write_rollback_wrapper() {
  cat >"$ROLLBACK_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$(printf '%q' "$REPO_ROLLBACK_SCRIPT")" "\$@"
EOF
  chmod 755 "$ROLLBACK_WRAPPER"
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

refresh_local_desktop_state() {
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
  gtk-update-icon-cache -f -t "${DATA_HOME}/icons/hicolor" >/dev/null 2>&1 || true
}

rollback_to_previous_release() {
  local current_target=""
  local previous_target=""
  local node_bin_dir=""

  current_target="$(resolve_link_target "$CURRENT_RELEASE_LINK" 2>/dev/null || true)"
  previous_target="$(resolve_link_target "$PREVIOUS_RELEASE_LINK" 2>/dev/null || true)"

  [ -n "$previous_target" ] || {
    printf 'No previous Electron release is available to roll back to.\n' >&2
    exit 1
  }

  update_symlink_atomically "$previous_target" "$CURRENT_RELEASE_LINK"
  if [ -n "$current_target" ]; then
    update_symlink_atomically "$current_target" "$PREVIOUS_RELEASE_LINK"
  else
    remove_symlink_if_present "$PREVIOUS_RELEASE_LINK"
  fi

  node_bin_dir="$(read_config_value CODEX_UBUNTU_NODE_BIN_DIR 2>/dev/null || true)"
  write_config_file "$TARGET_APP_ROOT" "${node_bin_dir:-}"

  if [ "$INSTALL_MODE" = "local-launcher" ] && [ -f "${TARGET_APP_ROOT}/.codex-linux/codex-desktop.png" ]; then
    install_primary_icon "$TARGET_APP_ROOT"
    refresh_local_desktop_state
  fi

  printf 'Rolled back Codex Desktop to %s\n' "$TARGET_APP_ROOT"
}

main() {
  local source_root=""
  local node_bin_dir=""

  if [ "$ROLLBACK_ONLY" = "1" ]; then
    rollback_to_previous_release
    return 0
  fi

  if [ "$INSTALL_MODE" = "local-launcher" ] && [ -f "$ACTIVE_WRAPPER" ] && [ ! -f "$LEGACY_WRAPPER" ] && ! wrapper_already_points_to_repo; then
    mv "$ACTIVE_WRAPPER" "$LEGACY_WRAPPER"
  fi

  source_root="$(resolve_source_app_root)"
  node_bin_dir="$(resolve_node_bin_dir "$source_root" || true)"

  install_release_into_local_opt "$source_root"
  write_config_file "$TARGET_APP_ROOT" "${node_bin_dir:-}"

  if [ "$INSTALL_MODE" = "local-launcher" ]; then
    install_primary_icon "$TARGET_APP_ROOT"
    write_primary_wrapper
    write_rollback_wrapper
    write_primary_desktop_entry

    if [ -f "$LEGACY_WRAPPER" ]; then
      write_legacy_desktop_entry
    else
      rm -f "$LEGACY_DESKTOP"
    fi

    refresh_local_desktop_state

    printf 'Installed repo-owned Electron launcher to %s\n' "$ACTIVE_WRAPPER"
    printf 'Installed rollback helper to %s\n' "$ROLLBACK_WRAPPER"
    if [ -f "$LEGACY_WRAPPER" ]; then
      printf 'Legacy rollback launcher preserved at %s\n' "$LEGACY_WRAPPER"
    fi
  else
    printf 'Updated local Electron desktop payload for the system package path.\n'
  fi

  printf 'Configured Electron app root as %s\n' "$TARGET_APP_ROOT"
}

main
