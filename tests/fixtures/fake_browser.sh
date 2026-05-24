#!/usr/bin/env bash
set -euo pipefail

[ -n "${CODEX_UBUNTU_TEST_BROWSER_LOG:-}" ] || {
  printf 'CODEX_UBUNTU_TEST_BROWSER_LOG is required\n' >&2
  exit 1
}

printf '%s\n' "$*" >>"$CODEX_UBUNTU_TEST_BROWSER_LOG"
