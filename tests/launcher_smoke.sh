#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAUNCHER="${REPO_DIR}/launcher/codex-ubuntu"
FAKE_RUNTIME="${REPO_DIR}/tests/fixtures/fake_codex_app_linux.py"
FAKE_BROWSER="${REPO_DIR}/tests/fixtures/fake_browser.sh"
FAKE_HEALTH_SERVER="${REPO_DIR}/tests/fixtures/fake_unverified_health_server.py"
FAKE_XDOTOOL_DIR="${REPO_DIR}/tests/fixtures"
TEST_TMPDIRS=()
TEST_PIDS=()

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [ "$expected" != "$actual" ]; then
    printf 'assert_eq failed: %s (expected=%s actual=%s)\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    printf 'assert_contains failed: %s missing %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assert_not_contains failed: %s unexpectedly contained %s\n' "$file" "$needle" >&2
    exit 1
  fi
}

assert_ne() {
  local left="$1"
  local right="$2"
  local message="$3"
  if [ "$left" = "$right" ]; then
    printf 'assert_ne failed: %s (left=%s right=%s)\n' "$message" "$left" "$right" >&2
    exit 1
  fi
}

register_tmpdir() {
  TEST_TMPDIRS+=("$1")
}

register_pid() {
  TEST_PIDS+=("$1")
}

cleanup_test_artifacts() {
  local pid=""
  local tmpdir=""

  for pid in "${TEST_PIDS[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
  done

  for tmpdir in "${TEST_TMPDIRS[@]}"; do
    if [ -d "$tmpdir" ]; then
      XDG_CONFIG_HOME="${tmpdir}/config" \
      XDG_CACHE_HOME="${tmpdir}/cache" \
      XDG_STATE_HOME="${tmpdir}/state" \
      "$LAUNCHER" --stop >/dev/null 2>&1 || true
      rm -rf "$tmpdir"
    fi
  done
}

pick_test_port() {
  python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

read_runtime_field() {
  local runtime_file="$1"
  local field="$2"

  python3 - <<'PY' "$runtime_file" "$field"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(json.load(handle)[sys.argv[2]])
PY
}

test_browser_launch_creates_verified_state() {
  local tmpdir browser_log requested_port runtime_pid runtime_port pid_file port_file runtime_file fingerprint_file

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port="$(pick_test_port)"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER"

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  fingerprint_file="${tmpdir}/state/codex-ubuntu/runtime.fingerprint.json"
  pid_file="${tmpdir}/state/codex-ubuntu/web.pid"
  port_file="${tmpdir}/state/codex-ubuntu/web.port"

  for _ in $(seq 1 40); do
    [ -f "$runtime_file" ] && break
    sleep 0.1
  done

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"
  runtime_port="$(read_runtime_field "$runtime_file" port)"

  assert_eq "$runtime_pid" "$(tr -d '[:space:]' <"$pid_file")" "runtime pid should be synced"
  assert_eq "$runtime_port" "$(tr -d '[:space:]' <"$port_file")" "port should be persisted"
  [ -f "$fingerprint_file" ] || {
    printf 'runtime fingerprint file was not created\n' >&2
    exit 1
  }
  assert_contains "$browser_log" "--class=codex-ubuntu"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/?token=fake-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop
}

test_stop_does_not_kill_unrelated_process() {
  local tmpdir sleeper

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  mkdir -p "${tmpdir}/state/codex-ubuntu" "${tmpdir}/cache" "${tmpdir}/config"
  sleep 30 &
  sleeper="$!"
  printf '%s\n' "$sleeper" >"${tmpdir}/state/codex-ubuntu/web.pid"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop

  if ! kill -0 "$sleeper" >/dev/null 2>&1; then
    printf 'stop killed unrelated process\n' >&2
    exit 1
  fi

  kill "$sleeper" >/dev/null 2>&1 || true
  wait "$sleeper" 2>/dev/null || true
}

test_stop_verified_runtime_removes_state() {
  local tmpdir requested_port runtime_file runtime_pid

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  requested_port="$(pick_test_port)"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --browser >/dev/null 2>&1 || true

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  for _ in $(seq 1 40); do
    [ -f "$runtime_file" ] && break
    sleep 0.1
  done

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop

  if kill -0 "$runtime_pid" >/dev/null 2>&1; then
    printf 'verified runtime is still alive after stop\n' >&2
    exit 1
  fi

  if [ -e "${tmpdir}/state/codex-ubuntu/token.runtime" ]; then
    printf 'runtime metadata still exists after stop\n' >&2
    exit 1
  fi
}

test_unverified_healthy_server_is_not_reused() {
  local tmpdir browser_log requested_port runtime_file runtime_port health_pid

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port="$(pick_test_port)"
  mkdir -p "${tmpdir}/state/codex-ubuntu" "${tmpdir}/cache" "${tmpdir}/config"
  printf '%s\n' "$requested_port" >"${tmpdir}/state/codex-ubuntu/web.port"
  printf 'stale-secret-token\n' >"${tmpdir}/state/codex-ubuntu/token"

  python3 "$FAKE_HEALTH_SERVER" --bind 127.0.0.1 --port "$requested_port" >/dev/null 2>&1 &
  health_pid="$!"
  register_pid "$health_pid"

  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:${requested_port}/__webstrapper/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 0.1
  done

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER"

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  for _ in $(seq 1 40); do
    [ -f "$runtime_file" ] && break
    sleep 0.1
  done

  runtime_port="$(read_runtime_field "$runtime_file" port)"

  assert_ne "$requested_port" "$runtime_port" "launcher should not reuse unverified healthy server"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/?token=fake-token"
  assert_not_contains "$browser_log" "stale-secret-token"
  assert_not_contains "$browser_log" "--app=http://127.0.0.1:${requested_port}/?token=stale-secret-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop
}

test_compatible_runtime_is_stoppable() {
  local tmpdir browser_log requested_port runtime_file runtime_pid compatible_runtime

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port="$(pick_test_port)"
  compatible_runtime="${tmpdir}/compatible_runtime.py"
  cp "$FAKE_RUNTIME" "$compatible_runtime"
  chmod +x "$compatible_runtime"

  CODEX_UBUNTU_APP_LINUX_CMD="$compatible_runtime" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER"

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  for _ in $(seq 1 40); do
    [ -f "$runtime_file" ] && break
    sleep 0.1
  done

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"

  CODEX_UBUNTU_APP_LINUX_CMD="$compatible_runtime" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop

  if kill -0 "$runtime_pid" >/dev/null 2>&1; then
    printf 'compatible runtime is still alive after stop\n' >&2
    exit 1
  fi

  if [ -e "$runtime_file" ]; then
    printf 'compatible runtime metadata still exists after stop\n' >&2
    exit 1
  fi
}

test_fresh_runtime_relaunches_even_if_window_exists() {
  local tmpdir browser_log requested_port_one requested_port_two

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port_one="$(pick_test_port)"
  requested_port_two="$(pick_test_port)"

  PATH="${FAKE_XDOTOOL_DIR}:$PATH" \
  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_XDOTOOL_WINDOW_ID="4242" \
  CODEX_UBUNTU_PORT="$requested_port_one" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop

  PATH="${FAKE_XDOTOOL_DIR}:$PATH" \
  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_XDOTOOL_WINDOW_ID="4242" \
  CODEX_UBUNTU_PORT="$requested_port_two" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER"

  assert_eq "2" "$(wc -l <"$browser_log" | tr -d '[:space:]')" "fresh runtime should relaunch browser even if a window exists"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${requested_port_one}/?token=fake-token"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${requested_port_two}/?token=fake-token"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  "$LAUNCHER" --stop
}

chmod +x "$FAKE_RUNTIME" "$FAKE_BROWSER" "$FAKE_HEALTH_SERVER" "${FAKE_XDOTOOL_DIR}/xdotool"
trap cleanup_test_artifacts EXIT

test_browser_launch_creates_verified_state
test_stop_does_not_kill_unrelated_process
test_stop_verified_runtime_removes_state
test_unverified_healthy_server_is_not_reused
test_compatible_runtime_is_stoppable
test_fresh_runtime_relaunches_even_if_window_exists

printf '[INFO] launcher smoke tests passed\n'
