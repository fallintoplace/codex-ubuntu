SHELL := /usr/bin/env bash

.PHONY: check validate-desktop test install-local install-electron-local import-electron-payload build-deb build-electron-local bootstrap-electron-local

check: validate-desktop
	bash -n electron/codex-desktop
	bash -n scripts/build-electron-local.sh
	bash -n launcher/codex-ubuntu
	bash -n scripts/import-electron-payload.sh
	bash -n scripts/install-electron-local.sh
	bash -n scripts/install-local.sh
	bash -n scripts/build-deb.sh
	bash -n tests/install_electron_local_smoke.sh
	bash -n tests/launcher_smoke.sh

validate-desktop:
	@tmpfile="$$(mktemp --suffix=.desktop)"; \
		scripts/render-desktop-file.sh "/usr/bin/codex-ubuntu" "codex-ubuntu" "$$tmpfile"; \
		if command -v desktop-file-validate >/dev/null 2>&1; then \
			desktop-file-validate "$$tmpfile"; \
		fi; \
		rm -f "$$tmpfile"; \
		tmpfile="$$(mktemp --suffix=.desktop)"; \
		scripts/render-desktop-file.sh "desktop/codex-desktop.desktop.in" "/usr/bin/codex-desktop" "codex-desktop" "$$tmpfile"; \
		if command -v desktop-file-validate >/dev/null 2>&1; then \
			desktop-file-validate "$$tmpfile"; \
		fi; \
		rm -f "$$tmpfile"

test: check
	bash tests/install_electron_local_smoke.sh
	bash tests/launcher_smoke.sh

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
