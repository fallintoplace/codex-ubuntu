#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
FALLBACK_PACKAGE="${FALLBACK_PACKAGE:-${REPO_DIR}/dist/codex-ubuntu_${VERSION}_all.deb}"
ELECTRON_PACKAGE="${ELECTRON_PACKAGE:-${REPO_DIR}/dist/codex-desktop_${VERSION}_all.deb}"
TEST_HOME="$(mktemp -d)"

cleanup() {
  if command -v sudo >/dev/null 2>&1; then
    sudo dpkg -P codex-desktop codex-ubuntu >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_HOME"
}

assert_not_exists() {
  local path="$1"
  [ ! -e "$path" ] || {
    printf 'expected path to be absent: %s\n' "$path" >&2
    exit 1
  }
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

run_as_root() {
  sudo "$@"
}

if [ "${CODEX_UBUNTU_PACKAGE_INSTALL_TEST:-0}" != "1" ]; then
  printf '[INFO] skipping package install smoke tests (set CODEX_UBUNTU_PACKAGE_INSTALL_TEST=1 to enable)\n'
  exit 0
fi

command -v sudo >/dev/null 2>&1 || {
  printf 'sudo is required for package install smoke tests.\n' >&2
  exit 1
}

sudo -n true >/dev/null 2>&1 || {
  printf 'passwordless sudo is required for package install smoke tests.\n' >&2
  exit 1
}

[ -f "$FALLBACK_PACKAGE" ] || {
  printf 'fallback package is missing: %s\n' "$FALLBACK_PACKAGE" >&2
  exit 1
}
[ -f "$ELECTRON_PACKAGE" ] || {
  printf 'electron package is missing: %s\n' "$ELECTRON_PACKAGE" >&2
  exit 1
}

trap cleanup EXIT

run_as_root dpkg -P codex-desktop codex-ubuntu >/dev/null 2>&1 || true

run_as_root dpkg -i "$FALLBACK_PACKAGE" >/dev/null
assert_file /usr/bin/codex-ubuntu
assert_file /usr/share/applications/codex-ubuntu.desktop
run_as_root dpkg -P codex-ubuntu >/dev/null
assert_not_exists /usr/bin/codex-ubuntu

run_as_root dpkg -i "$ELECTRON_PACKAGE" >/dev/null
assert_file /usr/bin/codex-desktop
assert_file /usr/bin/codex-desktop-bootstrap
assert_file /usr/bin/codex-desktop-rollback
assert_file /usr/share/applications/codex-desktop.desktop

stderr_file="${TEST_HOME}/codex-desktop.err"
HOME="${TEST_HOME}/home" \
XDG_CONFIG_HOME="${TEST_HOME}/config" \
XDG_CACHE_HOME="${TEST_HOME}/cache" \
XDG_DATA_HOME="${TEST_HOME}/data" \
CODEX_UBUNTU_DISABLE_NOTIFICATIONS=1 \
/usr/bin/codex-desktop >/dev/null 2>"$stderr_file" || true
assert_contains "$stderr_file" "Run codex-desktop-bootstrap to build and install the local desktop payload."

/usr/bin/codex-desktop-bootstrap --help >/dev/null
/usr/bin/codex-desktop-rollback >/dev/null 2>"${TEST_HOME}/rollback.err" || true

run_as_root dpkg -P codex-desktop >/dev/null
assert_not_exists /usr/bin/codex-desktop
assert_not_exists /usr/bin/codex-desktop-bootstrap
assert_not_exists /usr/bin/codex-desktop-rollback

printf '[INFO] package install smoke tests passed\n'
