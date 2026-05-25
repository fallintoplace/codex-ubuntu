#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
WRAPPER="${REPO_DIR}/electron/codex-desktop"
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

wait_for_file() {
  local path="$1"
  local message="$2"

  for _ in $(seq 1 40); do
    [ -f "$path" ] && return 0
    sleep 0.1
  done

  printf '%s\n' "$message" >&2
  exit 1
}

create_fake_app_root() {
  local root="$1"

  mkdir -p "$root"
  cat >"$root/start.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${CODEX_UBUNTU_ELECTRON_APP_ROOT:-}" >"${HOME}/electron-app-root.txt"
printf '%s\n' "${PATH}" >"${HOME}/electron-path.txt"
exit 0
EOF
  chmod 755 "$root/start.sh"
}

create_fake_node_bin_dir() {
  local node_bin_dir="$1"

  mkdir -p "$node_bin_dir"
  cat >"${node_bin_dir}/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod 755 "${node_bin_dir}/node"
}

test_wrapper_reads_allowlisted_config_file() {
  local tmpdir home_dir config_home cache_home app_root node_bin_dir config_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  config_home="${tmpdir}/config"
  cache_home="${tmpdir}/cache"
  app_root="${tmpdir}/Desktop Payload/codex-app"
  node_bin_dir="${tmpdir}/node runtime/bin"
  config_file="${config_home}/codex-ubuntu/electron.env"

  mkdir -p "$home_dir" "${config_home}/codex-ubuntu" "$cache_home"
  create_fake_app_root "$app_root"
  create_fake_node_bin_dir "$node_bin_dir"

  {
    printf 'CODEX_UBUNTU_ELECTRON_APP_ROOT=%q\n' "$app_root"
    printf 'CODEX_UBUNTU_NODE_BIN_DIR=%q\n' "$node_bin_dir"
  } >"$config_file"
  chmod 644 "$config_file"

  HOME="$home_dir" \
  XDG_CONFIG_HOME="$config_home" \
  XDG_CACHE_HOME="$cache_home" \
  "$WRAPPER"

  wait_for_file "${home_dir}/electron-app-root.txt" "wrapper did not launch fake start.sh"
  assert_contains "${home_dir}/electron-app-root.txt" "$app_root"
  assert_contains "${home_dir}/electron-path.txt" "$node_bin_dir"
  assert_file_mode 600 "$config_file"
}

test_wrapper_does_not_execute_shell_config() {
  local tmpdir home_dir config_home cache_home config_file stderr_file marker_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  home_dir="${tmpdir}/home"
  config_home="${tmpdir}/config"
  cache_home="${tmpdir}/cache"
  config_file="${config_home}/codex-ubuntu/electron.env"
  stderr_file="${tmpdir}/wrapper.err"
  marker_file="${home_dir}/config-should-not-run"

  mkdir -p "$home_dir" "${config_home}/codex-ubuntu" "$cache_home"
  printf 'CODEX_UBUNTU_ELECTRON_APP_ROOT=$(touch %q)\n' "$marker_file" >"$config_file"

  if HOME="$home_dir" \
    XDG_CONFIG_HOME="$config_home" \
    XDG_CACHE_HOME="$cache_home" \
    "$WRAPPER" >/dev/null 2>"$stderr_file"; then
    printf 'wrapper unexpectedly accepted unsafe config input\n' >&2
    exit 1
  fi

  if [ -e "$marker_file" ]; then
    printf 'unsafe config executed shell content\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Invalid shell-like value for CODEX_UBUNTU_ELECTRON_APP_ROOT"
}

trap cleanup_test_artifacts EXIT

test_wrapper_reads_allowlisted_config_file
test_wrapper_does_not_execute_shell_config

printf '[INFO] electron wrapper smoke tests passed\n'
