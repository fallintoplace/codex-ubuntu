#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
DIST_DIR="${REPO_DIR}/dist"
PKGROOT="${DIST_DIR}/pkgroot"
DEBIAN_DIR="${PKGROOT}/DEBIAN"
PACKAGE_PATH="${DIST_DIR}/codex-ubuntu_${VERSION}_all.deb"

command -v dpkg-deb >/dev/null 2>&1 || {
  printf 'dpkg-deb is required to build the Debian package.\n' >&2
  exit 1
}

rm -rf "$PKGROOT"
mkdir -p \
  "$DEBIAN_DIR" \
  "${PKGROOT}/usr/bin" \
  "${PKGROOT}/usr/share/applications" \
  "${PKGROOT}/usr/share/icons/hicolor/scalable/apps"

install -m 755 "${REPO_DIR}/launcher/codex-ubuntu" "${PKGROOT}/usr/bin/codex-ubuntu"
install -m 644 "${REPO_DIR}/desktop/codex-ubuntu.svg" "${PKGROOT}/usr/share/icons/hicolor/scalable/apps/codex-ubuntu.svg"
"${REPO_DIR}/scripts/render-desktop-file.sh" "/usr/bin/codex-ubuntu" "codex-ubuntu" "${PKGROOT}/usr/share/applications/codex-ubuntu.desktop"

sed "s|__VERSION__|${VERSION}|g" "${REPO_DIR}/packaging/deb/control.in" >"${DEBIAN_DIR}/control"
install -m 755 "${REPO_DIR}/packaging/deb/postinst" "${DEBIAN_DIR}/postinst"
install -m 755 "${REPO_DIR}/packaging/deb/postrm" "${DEBIAN_DIR}/postrm"

mkdir -p "$DIST_DIR"
dpkg-deb --build "$PKGROOT" "$PACKAGE_PATH" >/dev/null

printf 'Built %s\n' "$PACKAGE_PATH"
