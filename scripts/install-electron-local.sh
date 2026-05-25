#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BIN_DIR="${HOME}/.local/bin"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/codex-ubuntu"
ACTIVE_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy"
LEGACY_WRAPPER="${BIN_DIR}/codex-desktop-linux-heavy-legacy"
LEGACY_DESKTOP="${APP_DIR}/codex-desktop-legacy.desktop"
REPO_WRAPPER="${REPO_DIR}/electron/codex-desktop"
CONFIG_FILE="${CONFIG_DIR}/electron.env"

mkdir -p "$BIN_DIR" "$APP_DIR" "$CONFIG_DIR"

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

if [ -f "$ACTIVE_WRAPPER" ] && [ ! -f "$LEGACY_WRAPPER" ]; then
  mv "$ACTIVE_WRAPPER" "$LEGACY_WRAPPER"
fi

if [ ! -f "$LEGACY_WRAPPER" ]; then
  printf 'No legacy launcher found at %s\n' "$LEGACY_WRAPPER" >&2
  exit 1
fi

app_root="$(detect_config_value "$LEGACY_WRAPPER" app_root 2>/dev/null || true)"
node_bin_dir="$(detect_config_value "$LEGACY_WRAPPER" node_bin_dir 2>/dev/null || true)"

if [ -z "${app_root:-}" ]; then
  app_root="${HOME}/codex-desktop-linux/codex-app"
fi

if [ ! -x "${app_root}/start.sh" ]; then
  printf 'Detected Electron app root is invalid: %s\n' "$app_root" >&2
  exit 1
fi

write_config_file "$app_root" "${node_bin_dir:-}"

cat >"$ACTIVE_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$(printf '%q' "$REPO_WRAPPER")" "\$@"
EOF
chmod 755 "$ACTIVE_WRAPPER"

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
Keywords=Codex;Desktop;Legacy;Rollback;
EOF

update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true

printf 'Installed repo-owned Electron launcher to %s\n' "$ACTIVE_WRAPPER"
printf 'Legacy rollback launcher preserved at %s\n' "$LEGACY_WRAPPER"
printf 'Electron app root configured as %s\n' "$app_root"
