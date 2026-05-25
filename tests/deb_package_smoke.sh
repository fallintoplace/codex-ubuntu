#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
PACKAGE_PATH="${1:-${REPO_DIR}/dist/codex-ubuntu_${VERSION}_all.deb}"

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'expected %s to contain %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

[ -f "$PACKAGE_PATH" ] || {
  printf 'expected package is missing: %s\n' "$PACKAGE_PATH" >&2
  exit 1
}

contents_file="$(mktemp)"
control_file="$(mktemp)"
trap 'rm -f "$contents_file" "$control_file"' EXIT

dpkg-deb --contents "$PACKAGE_PATH" >"$contents_file"
dpkg-deb --field "$PACKAGE_PATH" >"$control_file"

assert_contains "$contents_file" "root/root"
assert_contains "$contents_file" "./usr/bin/codex-ubuntu"
assert_contains "$contents_file" "./usr/share/applications/codex-ubuntu.desktop"
assert_contains "$contents_file" "./usr/share/icons/hicolor/scalable/apps/codex-ubuntu.svg"
assert_contains "$control_file" "Package: codex-ubuntu"
assert_contains "$control_file" "Architecture: all"
assert_contains "$control_file" "Recommends: desktop-file-utils, hicolor-icon-theme, libnotify-bin"
assert_contains "$control_file" "Browser fallback preview package"
assert_contains "$control_file" "It does not install the Electron desktop path."

if command -v lintian >/dev/null 2>&1; then
  lintian --fail-on error "$PACKAGE_PATH"
fi

printf '[INFO] deb package smoke tests passed\n'
