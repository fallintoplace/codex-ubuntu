#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SCRIPT="${REPO_DIR}/scripts/install-electron-local.sh"
TEST_TMPDIRS=()

register_tmpdir() {
  TEST_TMPDIRS+=("$1")
}

cleanup_test_artifacts() {
  local tmpdir=""
  for tmpdir in "${TEST_TMPDIRS[@]}"; do
    rm -rf "$tmpdir"
  done
}

assert_file() {
  local path="$1"
  [ -f "$path" ] || {
    printf 'expected file is missing: %s\n' "$path" >&2
    exit 1
  }
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'expected %s to contain %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

create_fake_app_root() {
  local root="$1"
  mkdir -p "$root/.codex-linux" "$root/resources"
  cat >"$root/start.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 755 "$root/start.sh"
  printf 'fake-version\n' >"$root/version"
  printf 'fake icon\n' >"$root/.codex-linux/codex-desktop.png"
  printf '{}' >"$root/resources/codex-linux-build-info.json"
  printf 'fake asar\n' >"$root/resources/app.asar"
}

test_fresh_local_electron_install() {
  local tmpdir home_dir source_root active_wrapper primary_desktop config_file target_root icon_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  source_root="${tmpdir}/source/codex-app"
  create_fake_app_root "$source_root"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  "$INSTALL_SCRIPT" "$source_root"

  active_wrapper="${home_dir}/.local/bin/codex-desktop-linux-heavy"
  primary_desktop="${tmpdir}/data/applications/codex-desktop.desktop"
  config_file="${tmpdir}/config/codex-ubuntu/electron.env"
  target_root="${home_dir}/.local/opt/codex-ubuntu/current/codex-app"
  icon_file="${tmpdir}/data/icons/hicolor/256x256/apps/codex-desktop.png"

  assert_file "$active_wrapper"
  assert_file "$primary_desktop"
  assert_file "$config_file"
  assert_file "$target_root/start.sh"
  assert_file "$icon_file"
  assert_contains "$active_wrapper" "${REPO_DIR}/electron/codex-desktop"
  assert_contains "$config_file" "$target_root"
  assert_contains "$primary_desktop" "Name=Codex Desktop"
}

test_existing_wrapper_is_preserved_as_legacy() {
  local tmpdir home_dir source_root active_wrapper legacy_wrapper legacy_desktop

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  source_root="${tmpdir}/source/codex-app"
  create_fake_app_root "$source_root"
  mkdir -p "${home_dir}/.local/bin"

  active_wrapper="${home_dir}/.local/bin/codex-desktop-linux-heavy"
  legacy_wrapper="${home_dir}/.local/bin/codex-desktop-linux-heavy-legacy"
  legacy_desktop="${tmpdir}/data/applications/codex-desktop-legacy.desktop"

  cat >"$active_wrapper" <<'EOF'
#!/usr/bin/env bash
APP_ROOT="$HOME/legacy-codex-app"
exec "$APP_ROOT/start.sh" "$@"
EOF
  chmod 755 "$active_wrapper"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  "$INSTALL_SCRIPT" "$source_root"

  assert_file "$legacy_wrapper"
  assert_file "$legacy_desktop"
  assert_contains "$legacy_desktop" "Name=Codex Desktop (Legacy)"
}

trap cleanup_test_artifacts EXIT

test_fresh_local_electron_install
test_existing_wrapper_is_preserved_as_legacy

printf '[INFO] install-electron-local smoke tests passed\n'
