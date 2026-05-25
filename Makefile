SHELL := /usr/bin/env bash

.PHONY: check validate-desktop test install-local install-electron-local import-electron-payload build-deb

check: validate-desktop
	bash -n electron/codex-desktop
	bash -n launcher/codex-ubuntu
	bash -n scripts/import-electron-payload.sh
	bash -n scripts/install-electron-local.sh
	bash -n scripts/install-local.sh
	bash -n scripts/build-deb.sh
	bash -n tests/launcher_smoke.sh

validate-desktop:
	@tmpfile="$$(mktemp --suffix=.desktop)"; \
	scripts/render-desktop-file.sh "/usr/bin/codex-ubuntu" "codex-ubuntu" "$$tmpfile"; \
	if command -v desktop-file-validate >/dev/null 2>&1; then \
		desktop-file-validate "$$tmpfile"; \
	fi; \
	rm -f "$$tmpfile"

test: check
	tests/launcher_smoke.sh

install-local:
	scripts/install-local.sh

install-electron-local:
	scripts/install-electron-local.sh

import-electron-payload:
	scripts/import-electron-payload.sh "$(SOURCE_ROOT)"

build-deb:
	scripts/build-deb.sh
