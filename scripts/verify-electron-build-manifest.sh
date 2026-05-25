#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_PATH="${1:-}"
POLICY_PATH="${2:-${CODEX_UBUNTU_ELECTRON_POLICY_PATH:-${REPO_DIR}/electron/manifest/policy.json}}"
REQUIRED_DMG_SHA256="${CODEX_UBUNTU_REQUIRED_DMG_SHA256:-}"

usage() {
  cat <<EOF
Usage: scripts/verify-electron-build-manifest.sh <manifest-path> [policy-path]

Verify that a built Electron stage manifest matches the tracked policy and that
required stage output files exist.
EOF
}

if [ -z "$MANIFEST_PATH" ] || [ "${MANIFEST_PATH}" = "--help" ] || [ "${MANIFEST_PATH}" = "-h" ]; then
  usage
  if [ -z "$MANIFEST_PATH" ]; then
    exit 1
  fi
  exit 0
fi

[ -f "$MANIFEST_PATH" ] || {
  printf 'Build manifest does not exist: %s\n' "$MANIFEST_PATH" >&2
  exit 1
}

[ -f "$POLICY_PATH" ] || {
  printf 'Build policy does not exist: %s\n' "$POLICY_PATH" >&2
  exit 1
}

python3 - "$MANIFEST_PATH" "$POLICY_PATH" "$REQUIRED_DMG_SHA256" <<'PY'
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import sys

manifest_path = Path(sys.argv[1]).resolve()
policy_path = Path(sys.argv[2]).resolve()
required_dmg_sha_override = sys.argv[3].strip() or None


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


def load_json(path: Path, label: str) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON in {label} {path}: {exc}")

    if not isinstance(payload, dict):
        fail(f"{label} {path} must contain a JSON object")
    return payload


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest = load_json(manifest_path, "manifest")
policy = load_json(policy_path, "policy")

if manifest.get("schemaVersion") != 1:
    fail(f"Unsupported manifest schemaVersion in {manifest_path}")
if policy.get("schemaVersion") != 1:
    fail(f"Unsupported policy schemaVersion in {policy_path}")

stage_app_root_raw = manifest.get("stageAppRoot")
if not isinstance(stage_app_root_raw, str) or not stage_app_root_raw:
    fail(f"Missing stageAppRoot in {manifest_path}")

stage_app_root = Path(stage_app_root_raw).resolve()
if not stage_app_root.is_dir():
    fail(f"Staged app root does not exist: {stage_app_root}")

reference_builder = manifest.get("referenceBuilder")
if not isinstance(reference_builder, dict):
    fail(f"Missing referenceBuilder object in {manifest_path}")

expected_reference = policy.get("expectedReferenceBuilder")
if not isinstance(expected_reference, dict):
    fail(f"Missing expectedReferenceBuilder object in {policy_path}")

for field in ("url", "ref"):
    expected_value = expected_reference.get(field)
    actual_value = reference_builder.get(field)
    if expected_value != actual_value:
        fail(
            f"Reference builder {field} mismatch: expected {expected_value!r}, got {actual_value!r}"
        )

if expected_reference.get("requireCommitMatchRefWhenRefIsCommit"):
    expected_ref = expected_reference.get("ref", "")
    actual_commit = reference_builder.get("commit")
    if re.fullmatch(r"[0-9a-f]{40}", expected_ref or "") and actual_commit != expected_ref:
        fail(
            f"Reference builder commit mismatch: expected commit {expected_ref!r}, got {actual_commit!r}"
        )

allowed_bridge_modes = policy.get("allowedBridgeModes", [])
bridge_mode = manifest.get("bridgeMode")
if bridge_mode not in allowed_bridge_modes:
    fail(f"Unsupported bridgeMode {bridge_mode!r} for policy {policy_path}")

required_stage_files = policy.get("requiredStageFiles", [])
if not isinstance(required_stage_files, list) or not required_stage_files:
    fail(f"Policy {policy_path} must define requiredStageFiles")

for relative_path in required_stage_files:
    required_path = stage_app_root / relative_path
    if not required_path.exists():
        fail(f"Required staged file is missing: {required_path}")

required_dmg_sha = required_dmg_sha_override or policy.get("requiredSourceDmgSha256")
source_dmg_raw = manifest.get("sourceDmg")
source_dmg_sha_manifest = manifest.get("sourceDmgSha256")

if required_dmg_sha:
    if not isinstance(source_dmg_raw, str) or not source_dmg_raw:
        fail("Policy requires a source DMG checksum, but the manifest does not record sourceDmg")
    source_dmg_path = Path(source_dmg_raw).resolve()
    if not source_dmg_path.is_file():
        fail(f"Manifest recorded sourceDmg, but the file does not exist: {source_dmg_path}")
    actual_sha = sha256_of(source_dmg_path)
    if actual_sha != required_dmg_sha:
        fail(
            f"Source DMG checksum mismatch: expected {required_dmg_sha!r}, got {actual_sha!r}"
        )
    if source_dmg_sha_manifest and source_dmg_sha_manifest != actual_sha:
        fail(
            f"Manifest sourceDmgSha256 mismatch: expected actual digest {actual_sha!r}, got {source_dmg_sha_manifest!r}"
        )
elif source_dmg_raw and source_dmg_sha_manifest:
    source_dmg_path = Path(source_dmg_raw).resolve()
    if source_dmg_path.is_file():
        actual_sha = sha256_of(source_dmg_path)
        if actual_sha != source_dmg_sha_manifest:
            fail(
                f"Manifest sourceDmgSha256 mismatch: expected actual digest {actual_sha!r}, got {source_dmg_sha_manifest!r}"
            )
elif source_dmg_raw and not source_dmg_sha_manifest:
    fail("Manifest recorded sourceDmg without sourceDmgSha256")

print(f"Verified Electron build manifest {manifest_path}")
PY
