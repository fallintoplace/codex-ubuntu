#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_SCRIPT="${REPO_DIR}/scripts/codex-desktop-bootstrap.sh"
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

test_bootstrap_uses_system_package_install_mode() {
  local tmpdir fake_root build_script install_script build_log install_log output_log

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  fake_root="${tmpdir}/pkgroot"
  build_script="${fake_root}/scripts/build-electron-local.sh"
  install_script="${fake_root}/scripts/install-electron-local.sh"
  build_log="${tmpdir}/build.log"
  install_log="${tmpdir}/install.log"
  output_log="${tmpdir}/bootstrap.out"

  mkdir -p "${fake_root}/scripts"

  cat >"$build_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'BUILD_ROOT=%s\n' "${CODEX_UBUNTU_ELECTRON_BUILD_ROOT}" >"${TEST_BUILD_LOG}"
printf 'APP_ROOT=%s\n' "${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT}" >>"${TEST_BUILD_LOG}"
printf 'REFERENCE_DIR=%s\n' "${CODEX_UBUNTU_REFERENCE_BUILDER_DIR}" >>"${TEST_BUILD_LOG}"
printf 'IMPORT_AFTER_BUILD=%s\n' "${CODEX_UBUNTU_IMPORT_AFTER_BUILD}" >>"${TEST_BUILD_LOG}"
printf 'SUPPRESS_NEXT_STEPS=%s\n' "${CODEX_UBUNTU_SUPPRESS_BUILD_NEXT_STEPS}" >>"${TEST_BUILD_LOG}"
printf 'ARGS=%s\n' "$*" >>"${TEST_BUILD_LOG}"
mkdir -p "${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT}"
cat >"${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT}/start.sh" <<'INNER'
#!/usr/bin/env bash
exit 0
INNER
chmod 755 "${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT}/start.sh"
EOF
  chmod 755 "$build_script"

  cat >"$install_script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'MODE=%s\n' "${CODEX_UBUNTU_ELECTRON_INSTALL_MODE}" >"${TEST_INSTALL_LOG}"
printf 'ARG=%s\n' "$1" >>"${TEST_INSTALL_LOG}"
EOF
  chmod 755 "$install_script"

  TEST_BUILD_LOG="$build_log" \
  TEST_INSTALL_LOG="$install_log" \
  XDG_STATE_HOME="${tmpdir}/state" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  CODEX_UBUNTU_DESKTOP_BOOTSTRAP_BUILD_SCRIPT="$build_script" \
  CODEX_UBUNTU_DESKTOP_BOOTSTRAP_INSTALL_SCRIPT="$install_script" \
  "$BOOTSTRAP_SCRIPT" --download-upstream >"$output_log"

  assert_contains "$build_log" "IMPORT_AFTER_BUILD=0"
  assert_contains "$build_log" "SUPPRESS_NEXT_STEPS=1"
  assert_contains "$build_log" "ARGS=--download-upstream"
  assert_contains "$build_log" "BUILD_ROOT=${tmpdir}/state/codex-ubuntu/electron-build/current"
  assert_contains "$build_log" "REFERENCE_DIR=${tmpdir}/cache/codex-ubuntu/reference-builder"
  assert_contains "$install_log" "MODE=system-package"
  assert_contains "$install_log" "ARG=${tmpdir}/state/codex-ubuntu/electron-build/current/codex-app"
  assert_contains "$output_log" "Launch Codex Desktop from the app grid."
}

trap cleanup_test_artifacts EXIT

test_bootstrap_uses_system_package_install_mode

printf '[INFO] electron bootstrap smoke tests passed\n'
