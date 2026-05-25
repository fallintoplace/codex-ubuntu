#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERIFY_SCRIPT="${REPO_DIR}/scripts/verify-electron-build-manifest.sh"
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

create_fake_stage_root() {
  local root="$1"
  mkdir -p "$root/resources" "$root/.codex-linux"
  printf '#!/usr/bin/env bash\nexit 0\n' >"${root}/start.sh"
  chmod 755 "${root}/start.sh"
  printf 'fake electron binary\n' >"${root}/electron"
  printf 'fake asar\n' >"${root}/resources/app.asar"
  printf '{}\n' >"${root}/resources/codex-linux-build-info.json"
  printf 'fake icon\n' >"${root}/.codex-linux/codex-desktop.png"
}

create_manifest() {
  local manifest_path="$1"
  local stage_root="$2"
  local builder_ref="$3"
  local builder_commit="$4"
  local source_dmg="${5:-}"
  local source_dmg_sha="${6:-}"

  python3 - "$manifest_path" "$stage_root" "$builder_ref" "$builder_commit" "$source_dmg" "$source_dmg_sha" <<'PY'
from __future__ import annotations

import json
from pathlib import Path
import sys

manifest_path = Path(sys.argv[1])
stage_root = Path(sys.argv[2]).resolve()
builder_ref = sys.argv[3]
builder_commit = sys.argv[4]
source_dmg = sys.argv[5]
source_dmg_sha = sys.argv[6]

payload = {
    "schemaVersion": 1,
    "builderMode": "bridge-builder",
    "bridgeMode": "provided-dmg",
    "referenceBuilder": {
        "url": "https://github.com/ilysenko/codex-desktop-linux.git",
        "ref": builder_ref,
        "commit": builder_commit,
    },
    "stageAppRoot": str(stage_root),
}

if source_dmg:
    payload["sourceDmg"] = str(Path(source_dmg).resolve())
if source_dmg_sha:
    payload["sourceDmgSha256"] = source_dmg_sha

manifest_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY
}

test_manifest_verification_passes_for_matching_policy() {
  local tmpdir stage_root manifest_path policy_path dmg_path dmg_sha

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stage_root="${tmpdir}/stage/codex-app"
  manifest_path="${tmpdir}/builder-source.json"
  policy_path="${tmpdir}/policy.json"
  dmg_path="${tmpdir}/Codex.dmg"

  create_fake_stage_root "$stage_root"
  printf 'fake dmg bytes\n' >"$dmg_path"
  dmg_sha="$(sha256sum "$dmg_path" | awk '{print $1}')"
  create_manifest "$manifest_path" "$stage_root" "19d3ca11ac74916ac6df068fce85abfd6f20069c" "19d3ca11ac74916ac6df068fce85abfd6f20069c" "$dmg_path" "$dmg_sha"

  cat >"$policy_path" <<EOF
{
  "schemaVersion": 1,
  "expectedReferenceBuilder": {
    "url": "https://github.com/ilysenko/codex-desktop-linux.git",
    "ref": "19d3ca11ac74916ac6df068fce85abfd6f20069c",
    "requireCommitMatchRefWhenRefIsCommit": true
  },
  "allowedBridgeModes": ["provided-dmg"],
  "requiredStageFiles": [
    "start.sh",
    "electron",
    "resources/app.asar",
    "resources/codex-linux-build-info.json",
    ".codex-linux/codex-desktop.png"
  ],
  "requiredSourceDmgSha256": "${dmg_sha}"
}
EOF

  "$VERIFY_SCRIPT" "$manifest_path" "$policy_path" >/dev/null
}

test_manifest_verification_fails_for_wrong_builder_ref() {
  local tmpdir stage_root manifest_path policy_path stderr_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stage_root="${tmpdir}/stage/codex-app"
  manifest_path="${tmpdir}/builder-source.json"
  policy_path="${tmpdir}/policy.json"
  stderr_file="${tmpdir}/verify.err"

  create_fake_stage_root "$stage_root"
  create_manifest "$manifest_path" "$stage_root" "wrong-ref" "wrong-ref"
  cp "${REPO_DIR}/electron/manifest/policy.json" "$policy_path"

  if "$VERIFY_SCRIPT" "$manifest_path" "$policy_path" >/dev/null 2>"$stderr_file"; then
    printf 'verification unexpectedly passed for a wrong builder ref\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Reference builder ref mismatch"
}

test_manifest_verification_fails_for_missing_required_stage_file() {
  local tmpdir stage_root manifest_path policy_path stderr_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stage_root="${tmpdir}/stage/codex-app"
  manifest_path="${tmpdir}/builder-source.json"
  policy_path="${tmpdir}/policy.json"
  stderr_file="${tmpdir}/verify.err"

  create_fake_stage_root "$stage_root"
  rm -f "${stage_root}/resources/app.asar"
  create_manifest "$manifest_path" "$stage_root" "19d3ca11ac74916ac6df068fce85abfd6f20069c" "19d3ca11ac74916ac6df068fce85abfd6f20069c"
  cp "${REPO_DIR}/electron/manifest/policy.json" "$policy_path"

  if "$VERIFY_SCRIPT" "$manifest_path" "$policy_path" >/dev/null 2>"$stderr_file"; then
    printf 'verification unexpectedly passed for a missing required file\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Required staged file is missing"
}

trap cleanup_test_artifacts EXIT

test_manifest_verification_passes_for_matching_policy
test_manifest_verification_fails_for_wrong_builder_ref
test_manifest_verification_fails_for_missing_required_stage_file

printf '[INFO] electron provenance smoke tests passed\n'
