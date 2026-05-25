SHELL := /usr/bin/env bash

.PHONY: check require-desktop-tools validate-desktop test package-smoke electron-package-smoke package-install-smoke install-local install-electron-local import-electron-payload build-deb build-electron-deb build-electron-local bootstrap-electron-local

require-desktop-tools:
	command -v desktop-file-validate >/dev/null 2>&1 || { printf 'desktop-file-validate is required for validation. Install desktop-file-utils.\n' >&2; exit 1; }

check: validate-desktop
	bash -n electron/codex-desktop
	bash -n scripts/codex-desktop-bootstrap.sh
	bash -n scripts/codex-desktop-rollback.sh
	bash -n scripts/verify-electron-build-manifest.sh
	bash -n scripts/build-electron-local.sh
	bash -n scripts/build-electron-deb.sh
	bash -n launcher/codex-ubuntu
	bash -n scripts/import-electron-payload.sh
	bash -n scripts/install-electron-local.sh
	bash -n scripts/install-local.sh
	bash -n scripts/build-deb.sh
	bash -n tests/render_desktop_file_smoke.sh
	bash -n tests/deb_package_smoke.sh
	bash -n tests/electron_deb_package_smoke.sh
	bash -n tests/electron_bootstrap_smoke.sh
	bash -n tests/electron_provenance_smoke.sh
	bash -n tests/deb_package_install_smoke.sh
	bash -n tests/electron_wrapper_smoke.sh
	bash -n tests/install_electron_local_smoke.sh
	bash -n tests/launcher_smoke.sh

validate-desktop: require-desktop-tools
	@tmpfile="$$(mktemp --suffix=.desktop)"; \
		scripts/render-desktop-file.sh "/usr/bin/codex-ubuntu" "codex-ubuntu" "$$tmpfile"; \
		desktop-file-validate "$$tmpfile"; \
		rm -f "$$tmpfile"; \
		tmpfile="$$(mktemp --suffix=.desktop)"; \
		scripts/render-desktop-file.sh "desktop/codex-desktop.desktop.in" "/usr/bin/codex-desktop" "codex-desktop" "$$tmpfile"; \
		desktop-file-validate "$$tmpfile"; \
		rm -f "$$tmpfile"

test: check
	bash tests/render_desktop_file_smoke.sh
	bash tests/electron_bootstrap_smoke.sh
	bash tests/electron_provenance_smoke.sh
	bash tests/electron_wrapper_smoke.sh
	bash tests/install_electron_local_smoke.sh
	bash tests/launcher_smoke.sh

package-smoke:
	bash tests/deb_package_smoke.sh

electron-package-smoke:
	bash tests/electron_deb_package_smoke.sh

package-install-smoke:
	bash tests/deb_package_install_smoke.sh

install-local:
	scripts/install-local.sh

install-electron-local:
	scripts/install-electron-local.sh $(if $(SOURCE_APP_ROOT),"$(SOURCE_APP_ROOT)")

build-electron-local:
	scripts/build-electron-local.sh $(if $(SOURCE_DMG),"$(SOURCE_DMG)")

bootstrap-electron-local: build-electron-local install-electron-local

import-electron-payload:
	scripts/import-electron-payload.sh "$(SOURCE_ROOT)"

build-deb:
	scripts/build-deb.sh

build-electron-deb:
	scripts/build-electron-deb.sh
