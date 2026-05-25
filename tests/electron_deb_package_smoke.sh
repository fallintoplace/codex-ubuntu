#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
PACKAGE_PATH="${1:-${REPO_DIR}/dist/codex-desktop_${VERSION}_all.deb}"

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
assert_contains "$contents_file" "./usr/bin/codex-desktop"
assert_contains "$contents_file" "./usr/bin/codex-desktop-bootstrap"
assert_contains "$contents_file" "./usr/bin/codex-desktop-rollback"
assert_contains "$contents_file" "./usr/lib/codex-desktop/electron/codex-desktop"
assert_contains "$contents_file" "./usr/lib/codex-desktop/scripts/build-electron-local.sh"
assert_contains "$contents_file" "./usr/lib/codex-desktop/scripts/install-electron-local.sh"
assert_contains "$contents_file" "./usr/lib/codex-desktop/scripts/codex-desktop-bootstrap.sh"
assert_contains "$contents_file" "./usr/lib/codex-desktop/scripts/codex-desktop-rollback.sh"
assert_contains "$contents_file" "./usr/lib/codex-desktop/scripts/verify-electron-build-manifest.sh"
assert_contains "$contents_file" "./usr/lib/codex-desktop/desktop/codex-desktop.desktop.in"
assert_contains "$contents_file" "./usr/lib/codex-desktop/electron/manifest/policy.json"
assert_contains "$contents_file" "./usr/lib/codex-desktop/electron/manifest/policy.example.json"
assert_contains "$contents_file" "./usr/share/applications/codex-desktop.desktop"
assert_contains "$contents_file" "./usr/share/icons/hicolor/scalable/apps/codex-desktop.svg"
assert_contains "$contents_file" "./usr/share/doc/codex-desktop/changelog.gz"
assert_contains "$contents_file" "./usr/share/doc/codex-desktop/copyright"
assert_contains "$contents_file" "./usr/share/man/man1/codex-desktop.1.gz"
assert_contains "$contents_file" "./usr/share/man/man1/codex-desktop-bootstrap.1.gz"
assert_contains "$contents_file" "./usr/share/man/man1/codex-desktop-rollback.1.gz"

assert_contains "$control_file" "Package: codex-desktop"
assert_contains "$control_file" "Architecture: all"
assert_contains "$control_file" "Maintainer: Minh Vu <vuhoangminh97@gmail.com>"
assert_contains "$control_file" "Depends: curl, g++, git, make, python3, unzip, xdg-utils"
assert_contains "$control_file" "This package installs the Electron-first desktop launcher and local build"
assert_contains "$control_file" "Run codex-desktop-bootstrap after install to build and install the local"

if command -v lintian >/dev/null 2>&1; then
  lintian --fail-on error "$PACKAGE_PATH"
fi

printf '[INFO] electron deb package smoke tests passed\n'
