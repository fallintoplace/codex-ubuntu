#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEFAULT_REFERENCE_URL="https://github.com/ilysenko/codex-desktop-linux.git"
DEFAULT_REFERENCE_REF="19d3ca11ac74916ac6df068fce85abfd6f20069c"
DEFAULT_POLICY_PATH="${REPO_DIR}/electron/manifest/policy.json"
REFERENCE_BUILDER_DIR="${CODEX_UBUNTU_REFERENCE_BUILDER_DIR:-${REPO_DIR}/upstream/work/reference-builder}"
REFERENCE_BUILDER_URL="${CODEX_UBUNTU_REFERENCE_BUILDER_URL:-$DEFAULT_REFERENCE_URL}"
REFERENCE_BUILDER_REF="${CODEX_UBUNTU_REFERENCE_BUILDER_REF:-$DEFAULT_REFERENCE_REF}"
STAGE_ROOT="${CODEX_UBUNTU_ELECTRON_BUILD_ROOT:-${REPO_DIR}/dist/electron-build/current}"
STAGE_APP_ROOT="${CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT:-${STAGE_ROOT}/codex-app}"
BUILD_MANIFEST_PATH="${STAGE_ROOT}/builder-source.json"
IMPORT_AFTER_BUILD="${CODEX_UBUNTU_IMPORT_AFTER_BUILD:-1}"
SUPPRESS_NEXT_STEPS="${CODEX_UBUNTU_SUPPRESS_BUILD_NEXT_STEPS:-0}"
VERIFY_SCRIPT="${CODEX_UBUNTU_VERIFY_ELECTRON_BUILD_SCRIPT:-${REPO_DIR}/scripts/verify-electron-build-manifest.sh}"
POLICY_PATH="${CODEX_UBUNTU_ELECTRON_POLICY_PATH:-$DEFAULT_POLICY_PATH}"
REQUIRED_DMG_SHA256="${CODEX_UBUNTU_REQUIRED_DMG_SHA256:-}"

SOURCE_DMG_PATH=""
FRESH_BUILD=0
DOWNLOAD_UPSTREAM=0
MANAGED_REFERENCE_DIR=1

log() {
  printf '[build-electron-local] %s\n' "$*"
}

usage() {
  cat <<EOF
Usage: scripts/build-electron-local.sh [OPTIONS] [path/to/Codex.dmg]

Build a self-contained local Electron app root in a repo-managed staging area.

Options:
  --download-upstream   Download the upstream DMG if no local DMG path is provided
  --fresh               Rebuild from a clean staging area and ask the bridge builder for a fresh install
  --policy PATH         Verify the build manifest against a specific policy file
  --require-dmg-sha256 HASH
                        Require a specific SHA-256 digest for a provided source DMG
  -h, --help            Show this help message and exit

Environment:
  CODEX_UBUNTU_REFERENCE_BUILDER_DIR   Existing bridge-builder checkout to use
  CODEX_UBUNTU_REFERENCE_BUILDER_URL   Remote used when cloning the bridge builder
  CODEX_UBUNTU_REFERENCE_BUILDER_REF   Commit, tag, or branch to build with
  CODEX_UBUNTU_ELECTRON_BUILD_ROOT     Stage root (default: dist/electron-build/current)
  CODEX_UBUNTU_ELECTRON_BUILD_APP_ROOT Stage app root (default: <stage>/codex-app)
  CODEX_UBUNTU_IMPORT_AFTER_BUILD      Import the minimum payload slice after build (default: 1)
  CODEX_UBUNTU_ELECTRON_POLICY_PATH    Policy file used for build verification
  CODEX_UBUNTU_REQUIRED_DMG_SHA256     Optional fail-closed digest for a provided source DMG

If neither a DMG path nor --download-upstream is provided, the bridge builder will
reuse its cached upstream DMG if present and otherwise download a fresh copy.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --download-upstream)
        DOWNLOAD_UPSTREAM=1
        ;;
      --fresh)
        FRESH_BUILD=1
        ;;
      --policy)
        [ "$#" -ge 2 ] || {
          printf '--policy requires a path.\n' >&2
          exit 1
        }
        POLICY_PATH="$2"
        shift
        ;;
      --require-dmg-sha256)
        [ "$#" -ge 2 ] || {
          printf '--require-dmg-sha256 requires a SHA-256 digest.\n' >&2
          exit 1
        }
        REQUIRED_DMG_SHA256="$2"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
      *)
        if [ -n "$SOURCE_DMG_PATH" ]; then
          printf 'Only one DMG path may be provided.\n' >&2
          exit 1
        fi
        SOURCE_DMG_PATH="$1"
        ;;
    esac
    shift
  done
}

ensure_reference_builder_checkout() {
  if [ -n "${CODEX_UBUNTU_REFERENCE_BUILDER_DIR:-}" ]; then
    MANAGED_REFERENCE_DIR=0
  fi

  if [ -x "${REFERENCE_BUILDER_DIR}/install.sh" ]; then
    return 0
  fi

  require_command git
  mkdir -p "$(dirname "$REFERENCE_BUILDER_DIR")"

  if [ -e "$REFERENCE_BUILDER_DIR" ] && [ ! -d "$REFERENCE_BUILDER_DIR/.git" ]; then
    printf 'Reference builder path exists but is not a git checkout: %s\n' "$REFERENCE_BUILDER_DIR" >&2
    exit 1
  fi

  if [ ! -d "$REFERENCE_BUILDER_DIR/.git" ]; then
    log "Cloning bridge builder into ${REFERENCE_BUILDER_DIR}"
    git clone "$REFERENCE_BUILDER_URL" "$REFERENCE_BUILDER_DIR" >/dev/null
  fi
}

sync_reference_builder_ref() {
  local current_remote=""

  [ -d "${REFERENCE_BUILDER_DIR}/.git" ] || return 1

  current_remote="$(git -C "$REFERENCE_BUILDER_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -n "$current_remote" ] && [ "$current_remote" != "$REFERENCE_BUILDER_URL" ]; then
    printf 'Reference builder remote mismatch: expected %s but found %s\n' "$REFERENCE_BUILDER_URL" "$current_remote" >&2
    exit 1
  fi

  if [ "$MANAGED_REFERENCE_DIR" = "1" ]; then
    git -C "$REFERENCE_BUILDER_DIR" fetch --tags origin >/dev/null
  fi

  git -C "$REFERENCE_BUILDER_DIR" checkout --detach "$REFERENCE_BUILDER_REF" >/dev/null
}

verify_stage_output() {
  local required_path=""

  for required_path in \
    "${STAGE_APP_ROOT}/start.sh" \
    "${STAGE_APP_ROOT}/electron" \
    "${STAGE_APP_ROOT}/resources/app.asar" \
    "${STAGE_APP_ROOT}/resources/codex-linux-build-info.json" \
    "${STAGE_APP_ROOT}/.codex-linux/codex-desktop.png"
  do
    if [ ! -e "$required_path" ]; then
      printf 'Expected staged output is missing: %s\n' "$required_path" >&2
      exit 1
    fi
  done
}

write_build_manifest() {
  local reference_commit=""
  local bridge_mode=""

  reference_commit="$(git -C "$REFERENCE_BUILDER_DIR" rev-parse HEAD)"
  if [ -n "$SOURCE_DMG_PATH" ]; then
    bridge_mode="provided-dmg"
  elif [ "$DOWNLOAD_UPSTREAM" = "1" ]; then
    bridge_mode="downloaded-dmg"
  else
    bridge_mode="auto-download-or-cache"
  fi

  mkdir -p "$(dirname "$BUILD_MANIFEST_PATH")"
  python3 - "$BUILD_MANIFEST_PATH" "$REFERENCE_BUILDER_URL" "$REFERENCE_BUILDER_REF" "$reference_commit" "$bridge_mode" "$STAGE_APP_ROOT" "${SOURCE_DMG_PATH:-}" <<'PY'
from __future__ import annotations

import datetime as dt
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
reference_url = sys.argv[2]
reference_ref = sys.argv[3]
reference_commit = sys.argv[4]
bridge_mode = sys.argv[5]
stage_app_root = sys.argv[6]
source_dmg = sys.argv[7]

payload = {
    "schemaVersion": 1,
    "builtAt": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
    "builderMode": "bridge-builder",
    "bridgeMode": bridge_mode,
    "referenceBuilder": {
        "url": reference_url,
        "ref": reference_ref,
        "commit": reference_commit,
    },
    "stageAppRoot": stage_app_root,
}

if source_dmg:
    payload["sourceDmg"] = str(pathlib.Path(source_dmg).resolve())
    digest = hashlib.sha256()
    with pathlib.Path(source_dmg).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    payload["sourceDmgSha256"] = digest.hexdigest()

manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

run_reference_builder() {
  local -a builder_args=()

  if [ -n "$SOURCE_DMG_PATH" ]; then
    [ -f "$SOURCE_DMG_PATH" ] || {
      printf 'Provided DMG not found: %s\n' "$SOURCE_DMG_PATH" >&2
      exit 1
    }
    builder_args+=("$(realpath "$SOURCE_DMG_PATH")")
  fi

  rm -rf "$STAGE_ROOT"
  mkdir -p "$STAGE_ROOT"

  if [ "$FRESH_BUILD" = "1" ]; then
    builder_args=(--fresh "${builder_args[@]}")
  fi

  log "Building staged Electron app at ${STAGE_APP_ROOT}"
  CODEX_INSTALL_ROOT="$STAGE_ROOT" \
  CODEX_INSTALL_DIR="$STAGE_APP_ROOT" \
  CODEX_INSTALL_ALLOW_RUNNING=1 \
  "${REFERENCE_BUILDER_DIR}/install.sh" "${builder_args[@]}"
}

verify_build_manifest() {
  [ -x "$VERIFY_SCRIPT" ] || {
    printf 'Missing build verification helper: %s\n' "$VERIFY_SCRIPT" >&2
    exit 1
  }

  CODEX_UBUNTU_REQUIRED_DMG_SHA256="$REQUIRED_DMG_SHA256" \
  "$VERIFY_SCRIPT" "$BUILD_MANIFEST_PATH" "$POLICY_PATH"
}

main() {
  parse_args "$@"
  require_command python3

  ensure_reference_builder_checkout
  sync_reference_builder_ref
  run_reference_builder
  verify_stage_output
  write_build_manifest
  verify_build_manifest

  if [ "$IMPORT_AFTER_BUILD" = "1" ]; then
    "${REPO_DIR}/scripts/import-electron-payload.sh" "$STAGE_APP_ROOT"
  fi

  log "Built staged Electron app root at ${STAGE_APP_ROOT}"
  log "Wrote build manifest ${BUILD_MANIFEST_PATH}"
  if [ "$SUPPRESS_NEXT_STEPS" != "1" ]; then
    printf '\nNext steps:\n'
    printf '  1. make install-electron-local SOURCE_APP_ROOT=%q\n' "$STAGE_APP_ROOT"
    printf '  2. Launch Codex Desktop from the app grid\n'
  fi
}

main "$@"
