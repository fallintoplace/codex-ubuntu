SHELL := /usr/bin/env bash

.PHONY: check validate-desktop test install-local build-deb

check: validate-desktop
	bash -n launcher/codex-ubuntu
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

build-deb:
	scripts/build-deb.sh
