#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENDER_SCRIPT="${REPO_DIR}/scripts/render-desktop-file.sh"
TEST_TMPDIRS=()

register_tmpdir() {
  TEST_TMPDIRS+=("$1")
}

cleanup_test_artifacts() {
  local tmpdir=""
  for tmpdir in "${TEST_TMPDIRS[@]}"; do
    rm -rf "$tmpdir"
  done
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'expected %s to contain %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

test_renderer_quotes_exec_field_safely() {
  local tmpdir fallback_desktop electron_desktop exec_path

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  fallback_desktop="${tmpdir}/fallback.desktop"
  electron_desktop="${tmpdir}/electron.desktop"
  exec_path="/tmp/Desktop Preview 100%/bin/run-app"

  "$RENDER_SCRIPT" "$exec_path" "codex-ubuntu" "$fallback_desktop"
  "$RENDER_SCRIPT" "${REPO_DIR}/desktop/codex-desktop.desktop.in" "$exec_path" "codex-desktop" "$electron_desktop"

  assert_contains "$fallback_desktop" 'Exec="/tmp/Desktop Preview 100%%/bin/run-app"'
  assert_contains "$electron_desktop" 'Exec="/tmp/Desktop Preview 100%%/bin/run-app" %u'
  assert_contains "$fallback_desktop" "Name=Codex Ubuntu Fallback"

  desktop-file-validate "$fallback_desktop"
  desktop-file-validate "$electron_desktop"
}

trap cleanup_test_artifacts EXIT

test_renderer_quotes_exec_field_safely

printf '[INFO] render-desktop-file smoke tests passed\n'
