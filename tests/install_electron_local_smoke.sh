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

assert_file_mode() {
  local expected="$1"
  local path="$2"
  local actual=""

  actual="$(stat -c '%a' "$path")"
  if [ "$expected" != "$actual" ]; then
    printf 'expected %s to have mode %s, got %s\n' "$path" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_symlink_target_contains() {
  local link_path="$1"
  local needle="$2"
  local target=""

  [ -L "$link_path" ] || {
    printf 'expected symlink is missing: %s\n' "$link_path" >&2
    exit 1
  }

  target="$(readlink "$link_path")"
  case "$target" in
    *"$needle"*) ;;
    *)
      printf 'expected symlink %s to contain %s, got %s\n' "$link_path" "$needle" "$target" >&2
      exit 1
      ;;
  esac
}

create_fake_app_root() {
  local root="$1"
  local version_label="${2:-fake-version}"
  local icon_contents="${3:-fake icon}"
  mkdir -p "$root/.codex-linux" "$root/resources"
  cat >"$root/start.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 755 "$root/start.sh"
  printf '%s\n' "$version_label" >"$root/version"
  printf '%s\n' "$icon_contents" >"$root/.codex-linux/codex-desktop.png"
  printf '{}' >"$root/resources/codex-linux-build-info.json"
  printf 'fake asar\n' >"$root/resources/app.asar"
}

test_fresh_local_electron_install() {
  local tmpdir home_dir source_root active_wrapper rollback_wrapper primary_desktop config_file target_root icon_file config_dir current_link

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
  rollback_wrapper="${home_dir}/.local/bin/codex-desktop-rollback"
  primary_desktop="${tmpdir}/data/applications/codex-desktop.desktop"
  config_file="${tmpdir}/config/codex-ubuntu/electron.env"
  config_dir="$(dirname "$config_file")"
  target_root="${home_dir}/.local/opt/codex-ubuntu/current/codex-app"
  current_link="${home_dir}/.local/opt/codex-ubuntu/current"
  icon_file="${tmpdir}/data/icons/hicolor/256x256/apps/codex-desktop.png"

  assert_file "$active_wrapper"
  assert_file "$rollback_wrapper"
  assert_file "$primary_desktop"
  assert_file "$config_file"
  assert_file "$target_root/start.sh"
  assert_file "$icon_file"
  assert_contains "$active_wrapper" "${REPO_DIR}/electron/codex-desktop"
  assert_contains "$rollback_wrapper" "${REPO_DIR}/scripts/codex-desktop-rollback.sh"
  assert_contains "$config_file" "$target_root"
  assert_contains "$primary_desktop" "Name=Codex Desktop"
  assert_file_mode 700 "$config_dir"
  assert_file_mode 600 "$config_file"
  assert_symlink_target_contains "$current_link" "/releases/"
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

test_system_package_mode_only_updates_local_payload_state() {
  local tmpdir home_dir source_root config_file target_root active_wrapper primary_desktop icon_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  source_root="${tmpdir}/source/codex-app"
  create_fake_app_root "$source_root"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  CODEX_UBUNTU_ELECTRON_INSTALL_MODE=system-package \
  "$INSTALL_SCRIPT" "$source_root"

  config_file="${tmpdir}/config/codex-ubuntu/electron.env"
  target_root="${home_dir}/.local/opt/codex-ubuntu/current/codex-app"
  active_wrapper="${home_dir}/.local/bin/codex-desktop-linux-heavy"
  primary_desktop="${tmpdir}/data/applications/codex-desktop.desktop"
  icon_file="${tmpdir}/data/icons/hicolor/256x256/apps/codex-desktop.png"

  assert_file "$config_file"
  assert_file "$target_root/start.sh"
  assert_contains "$config_file" "$target_root"

  if [ -e "$active_wrapper" ] || [ -e "$primary_desktop" ] || [ -e "$icon_file" ]; then
    printf 'system-package mode unexpectedly wrote launcher desktop assets\n' >&2
    exit 1
  fi
}

test_atomic_release_install_and_rollback() {
  local tmpdir home_dir first_root second_root current_link previous_link target_root rollback_wrapper icon_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  first_root="${tmpdir}/source-one/codex-app"
  second_root="${tmpdir}/source-two/codex-app"
  create_fake_app_root "$first_root" "release-one" "first icon"
  create_fake_app_root "$second_root" "release-two" "second icon"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  "$INSTALL_SCRIPT" "$first_root"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  "$INSTALL_SCRIPT" "$second_root"

  current_link="${home_dir}/.local/opt/codex-ubuntu/current"
  previous_link="${home_dir}/.local/opt/codex-ubuntu/previous"
  target_root="${home_dir}/.local/opt/codex-ubuntu/current/codex-app"
  rollback_wrapper="${home_dir}/.local/bin/codex-desktop-rollback"
  icon_file="${tmpdir}/data/icons/hicolor/256x256/apps/codex-desktop.png"

  assert_symlink_target_contains "$current_link" "release-two"
  assert_symlink_target_contains "$previous_link" "release-one"
  assert_contains "${target_root}/version" "release-two"
  assert_contains "$icon_file" "second icon"

  HOME="$home_dir" \
  XDG_DATA_HOME="${tmpdir}/data" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  "$rollback_wrapper"

  assert_symlink_target_contains "$current_link" "release-one"
  assert_symlink_target_contains "$previous_link" "release-two"
  assert_contains "${target_root}/version" "release-one"
  assert_contains "$icon_file" "first icon"
}

trap cleanup_test_artifacts EXIT

test_fresh_local_electron_install
test_existing_wrapper_is_preserved_as_legacy
test_system_package_mode_only_updates_local_payload_state
test_atomic_release_install_and_rollback

printf '[INFO] install-electron-local smoke tests passed\n'
