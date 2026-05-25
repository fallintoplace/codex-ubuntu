#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
DIST_DIR="${REPO_DIR}/dist"
PKGROOT="${DIST_DIR}/pkgroot"
DEBIAN_DIR="${PKGROOT}/DEBIAN"
PACKAGE_PATH="${DIST_DIR}/codex-ubuntu_${VERSION}_all.deb"
DOC_DIR="${PKGROOT}/usr/share/doc/codex-ubuntu"
MAN_DIR="${PKGROOT}/usr/share/man/man1"

command -v dpkg-deb >/dev/null 2>&1 || {
  printf 'dpkg-deb is required to build the Debian package.\n' >&2
  exit 1
}

rm -rf "$PKGROOT"
mkdir -p \
  "$DEBIAN_DIR" \
  "${PKGROOT}/usr/bin" \
  "${PKGROOT}/usr/share/applications" \
  "${PKGROOT}/usr/share/icons/hicolor/scalable/apps" \
  "$DOC_DIR" \
  "$MAN_DIR"

install -m 755 "${REPO_DIR}/launcher/codex-ubuntu" "${PKGROOT}/usr/bin/codex-ubuntu"
install -m 644 "${REPO_DIR}/desktop/codex-ubuntu.svg" "${PKGROOT}/usr/share/icons/hicolor/scalable/apps/codex-ubuntu.svg"
"${REPO_DIR}/scripts/render-desktop-file.sh" "/usr/bin/codex-ubuntu" "codex-ubuntu" "${PKGROOT}/usr/share/applications/codex-ubuntu.desktop"
install -m 644 "${REPO_DIR}/packaging/deb/copyright" "${DOC_DIR}/copyright"
gzip -n -9 -c "${REPO_DIR}/packaging/deb/changelog" >"${DOC_DIR}/changelog.gz"
gzip -n -9 -c "${REPO_DIR}/packaging/deb/codex-ubuntu.1" >"${MAN_DIR}/codex-ubuntu.1.gz"

sed "s|__VERSION__|${VERSION}|g" "${REPO_DIR}/packaging/deb/control.in" >"${DEBIAN_DIR}/control"
install -m 755 "${REPO_DIR}/packaging/deb/postinst" "${DEBIAN_DIR}/postinst"
install -m 755 "${REPO_DIR}/packaging/deb/postrm" "${DEBIAN_DIR}/postrm"

mkdir -p "$DIST_DIR"
dpkg-deb --root-owner-group --build "$PKGROOT" "$PACKAGE_PATH" >/dev/null

printf 'Built %s\n' "$PACKAGE_PATH"
printf 'Package note: this preview .deb installs the browser fallback utility, not the Electron desktop app.\n'
