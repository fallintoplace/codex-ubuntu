#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(tr -d '[:space:]' <"${REPO_DIR}/VERSION")"
DIST_DIR="${REPO_DIR}/dist"
PKGROOT="${DIST_DIR}/pkgroot-electron"
DEBIAN_DIR="${PKGROOT}/DEBIAN"
PACKAGE_PATH="${DIST_DIR}/codex-desktop_${VERSION}_all.deb"
LIBEXEC_DIR="${PKGROOT}/usr/lib/codex-desktop"
DOC_DIR="${PKGROOT}/usr/share/doc/codex-desktop"
MAN_DIR="${PKGROOT}/usr/share/man/man1"

command -v dpkg-deb >/dev/null 2>&1 || {
  printf 'dpkg-deb is required to build the Electron Debian package.\n' >&2
  exit 1
}

rm -rf "$PKGROOT"
mkdir -p \
  "$DEBIAN_DIR" \
  "${PKGROOT}/usr/bin" \
  "${LIBEXEC_DIR}/desktop" \
  "${LIBEXEC_DIR}/electron" \
  "${LIBEXEC_DIR}/electron/manifest" \
  "${LIBEXEC_DIR}/scripts" \
  "${PKGROOT}/usr/share/applications" \
  "${PKGROOT}/usr/share/icons/hicolor/scalable/apps" \
  "$DOC_DIR" \
  "$MAN_DIR"

install -m 755 "${REPO_DIR}/electron/codex-desktop" "${LIBEXEC_DIR}/electron/codex-desktop"
install -m 755 "${REPO_DIR}/scripts/build-electron-local.sh" "${LIBEXEC_DIR}/scripts/build-electron-local.sh"
install -m 755 "${REPO_DIR}/scripts/install-electron-local.sh" "${LIBEXEC_DIR}/scripts/install-electron-local.sh"
install -m 755 "${REPO_DIR}/scripts/codex-desktop-rollback.sh" "${LIBEXEC_DIR}/scripts/codex-desktop-rollback.sh"
install -m 755 "${REPO_DIR}/scripts/verify-electron-build-manifest.sh" "${LIBEXEC_DIR}/scripts/verify-electron-build-manifest.sh"
install -m 755 "${REPO_DIR}/scripts/render-desktop-file.sh" "${LIBEXEC_DIR}/scripts/render-desktop-file.sh"
install -m 755 "${REPO_DIR}/scripts/codex-desktop-bootstrap.sh" "${LIBEXEC_DIR}/scripts/codex-desktop-bootstrap.sh"
install -m 644 "${REPO_DIR}/desktop/codex-desktop.desktop.in" "${LIBEXEC_DIR}/desktop/codex-desktop.desktop.in"
install -m 644 "${REPO_DIR}/electron/manifest/policy.json" "${LIBEXEC_DIR}/electron/manifest/policy.json"
install -m 644 "${REPO_DIR}/electron/manifest/policy.example.json" "${LIBEXEC_DIR}/electron/manifest/policy.example.json"
install -m 644 "${REPO_DIR}/desktop/codex-ubuntu.svg" "${PKGROOT}/usr/share/icons/hicolor/scalable/apps/codex-desktop.svg"

cat >"${PKGROOT}/usr/bin/codex-desktop" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/lib/codex-desktop/electron/codex-desktop "$@"
EOF
chmod 755 "${PKGROOT}/usr/bin/codex-desktop"

cat >"${PKGROOT}/usr/bin/codex-desktop-bootstrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /usr/lib/codex-desktop/scripts/codex-desktop-bootstrap.sh "$@"
EOF
chmod 755 "${PKGROOT}/usr/bin/codex-desktop-bootstrap"

cat >"${PKGROOT}/usr/bin/codex-desktop-rollback" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
CODEX_UBUNTU_ELECTRON_INSTALL_MODE=system-package \
exec /usr/lib/codex-desktop/scripts/codex-desktop-rollback.sh "$@"
EOF
chmod 755 "${PKGROOT}/usr/bin/codex-desktop-rollback"

"${REPO_DIR}/scripts/render-desktop-file.sh" \
  "${REPO_DIR}/desktop/codex-desktop.desktop.in" \
  "/usr/bin/codex-desktop" \
  "codex-desktop" \
  "${PKGROOT}/usr/share/applications/codex-desktop.desktop"

install -m 644 "${REPO_DIR}/packaging/electron-deb/copyright" "${DOC_DIR}/copyright"
gzip -n -9 -c "${REPO_DIR}/packaging/electron-deb/changelog" >"${DOC_DIR}/changelog.gz"
gzip -n -9 -c "${REPO_DIR}/packaging/electron-deb/codex-desktop.1" >"${MAN_DIR}/codex-desktop.1.gz"
gzip -n -9 -c "${REPO_DIR}/packaging/electron-deb/codex-desktop-bootstrap.1" >"${MAN_DIR}/codex-desktop-bootstrap.1.gz"
gzip -n -9 -c "${REPO_DIR}/packaging/electron-deb/codex-desktop-rollback.1" >"${MAN_DIR}/codex-desktop-rollback.1.gz"

sed "s|__VERSION__|${VERSION}|g" "${REPO_DIR}/packaging/electron-deb/control.in" >"${DEBIAN_DIR}/control"
install -m 755 "${REPO_DIR}/packaging/electron-deb/postinst" "${DEBIAN_DIR}/postinst"
install -m 755 "${REPO_DIR}/packaging/electron-deb/postrm" "${DEBIAN_DIR}/postrm"

mkdir -p "$DIST_DIR"
dpkg-deb --root-owner-group --build "$PKGROOT" "$PACKAGE_PATH" >/dev/null

printf 'Built %s\n' "$PACKAGE_PATH"
printf 'Package note: this Electron-primary .deb installs the launcher and bootstrap tooling, not the desktop payload itself.\n'
