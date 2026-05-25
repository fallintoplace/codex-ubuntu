#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LAUNCHER="${REPO_DIR}/launcher/codex-ubuntu"
FAKE_RUNTIME="${REPO_DIR}/tests/fixtures/fake_codex_app_linux.py"
FAKE_BROWSER="${REPO_DIR}/tests/fixtures/fake_browser.sh"
FAKE_HEALTH_SERVER="${REPO_DIR}/tests/fixtures/fake_unverified_health_server.py"
FAKE_HANGING_HEALTH_SERVER="${REPO_DIR}/tests/fixtures/fake_hanging_health_server.py"
FAKE_XDOTOOL_DIR="${REPO_DIR}/tests/fixtures"
PATH="${FAKE_XDOTOOL_DIR}:$PATH"
TEST_TMPDIRS=()
TEST_PIDS=()
TEST_TIMEOUT_SECONDS="${CODEX_UBUNTU_TEST_TIMEOUT_SECONDS:-20}"

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
      run_launcher --stop >/dev/null 2>&1 || true
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

wait_for_file() {
  local path="$1"
  local message="$2"

  for _ in $(seq 1 40); do
    [ -f "$path" ] && return 0
    sleep 0.1
  done

  printf '%s\n' "$message" >&2
  exit 1
}

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]
try:
    completed = subprocess.run(cmd, timeout=timeout)
except subprocess.TimeoutExpired:
    print(
        f"command timed out after {timeout} seconds: {' '.join(cmd)}",
        file=sys.stderr,
    )
    raise SystemExit(124)
raise SystemExit(completed.returncode)
PY
}

run_launcher() {
  run_with_timeout "$TEST_TIMEOUT_SECONDS" "$LAUNCHER" "$@"
}

wait_for_background_result() {
  local pid="$1"
  local log_file="$2"
  local label="$3"
  local status=0

  if wait "$pid"; then
    return 0
  fi

  status="$?"
  printf '%s exited with status %s\n' "$label" "$status" >&2
  if [ -f "$log_file" ]; then
    printf '%s output:\n' "$label" >&2
    sed -n '1,200p' "$log_file" >&2 || true
  fi
  return "$status"
}

rewrite_json_field() {
  local path="$1"
  local field="$2"
  local value="$3"

  python3 - "$path" "$field" "$value" <<'PY'
import json
import sys

path, field, value = sys.argv[1:]

with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

payload[field] = int(value) if value.isdigit() else value

with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
    handle.write("\n")
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
  run_launcher

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  fingerprint_file="${tmpdir}/state/codex-ubuntu/runtime.fingerprint.json"
  pid_file="${tmpdir}/state/codex-ubuntu/web.pid"
  port_file="${tmpdir}/state/codex-ubuntu/web.port"

  wait_for_file "$runtime_file" "runtime metadata file was not created"

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"
  runtime_port="$(read_runtime_field "$runtime_file" port)"

  assert_eq "$runtime_pid" "$(tr -d '[:space:]' <"$pid_file")" "runtime pid should be synced"
  assert_eq "$runtime_port" "$(tr -d '[:space:]' <"$port_file")" "port should be persisted"
  [ -f "$fingerprint_file" ] || {
    printf 'runtime fingerprint file was not created\n' >&2
    exit 1
  }
  assert_contains "$browser_log" "--class=codex-ubuntu"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/__webstrapper/auth?token=fake-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
}

test_web_log_redacts_runtime_secrets() {
  local tmpdir browser_log web_log requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  web_log="${tmpdir}/cache/codex-ubuntu/web.log"
  requested_port="$(pick_test_port)"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_RUNTIME_STDOUT_SECRET="runtime-secret-token" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher

  wait_for_file "$web_log" "web log was not created for redaction test"
  assert_contains "$web_log" "token=<redacted>"
  assert_contains "$web_log" "Local login command: <redacted>"
  assert_not_contains "$web_log" "runtime-secret-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
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
  run_launcher --stop

  if ! kill -0 "$sleeper" >/dev/null 2>&1; then
    printf 'stop killed unrelated process\n' >&2
    exit 1
  fi

  kill "$sleeper" >/dev/null 2>&1 || true
  wait "$sleeper" 2>/dev/null || true
}

test_stop_refuses_runtime_with_tampered_fingerprint() {
  local tmpdir requested_port runtime_file fingerprint_file runtime_pid

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  requested_port="$(pick_test_port)"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --browser >/dev/null 2>&1 || true

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  fingerprint_file="${tmpdir}/state/codex-ubuntu/runtime.fingerprint.json"
  wait_for_file "$runtime_file" "runtime metadata file was not created for fingerprint tamper test"
  wait_for_file "$fingerprint_file" "runtime fingerprint file was not created for fingerprint tamper test"

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"
  rewrite_json_field "$fingerprint_file" "procStarttimeAtCapture" "1"

  if XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher --stop >/dev/null 2>"${tmpdir}/stop.err"; then
    printf 'stop unexpectedly succeeded after fingerprint tampering\n' >&2
    exit 1
  fi

  if ! kill -0 "$runtime_pid" >/dev/null 2>&1; then
    printf 'tampered fingerprint still allowed runtime stop\n' >&2
    exit 1
  fi

  assert_contains "${tmpdir}/stop.err" "owning process could not be verified"
  kill "$runtime_pid" >/dev/null 2>&1 || true
  wait "$runtime_pid" 2>/dev/null || true
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
  run_launcher --browser >/dev/null 2>&1 || true

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  wait_for_file "$runtime_file" "runtime metadata file was not created for stop test"

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop

  if kill -0 "$runtime_pid" >/dev/null 2>&1; then
    printf 'verified runtime is still alive after stop\n' >&2
    exit 1
  fi

  if [ -e "${tmpdir}/state/codex-ubuntu/token.runtime" ]; then
    printf 'runtime metadata still exists after stop\n' >&2
    exit 1
  fi
}

test_hanging_health_server_is_timed_out_and_not_reused() {
  local tmpdir browser_log requested_port runtime_file runtime_port hanging_pid

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port="$(pick_test_port)"
  mkdir -p "${tmpdir}/state/codex-ubuntu" "${tmpdir}/cache" "${tmpdir}/config"
  printf '%s\n' "$requested_port" >"${tmpdir}/state/codex-ubuntu/web.port"

  python3 "$FAKE_HANGING_HEALTH_SERVER" --bind 127.0.0.1 --port "$requested_port" >/dev/null 2>&1 &
  hanging_pid="$!"
  register_pid "$hanging_pid"
  sleep 0.2

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  wait_for_file "$runtime_file" "runtime metadata file was not created for hanging health server test"
  runtime_port="$(read_runtime_field "$runtime_file" port)"

  assert_ne "$requested_port" "$runtime_port" "launcher should not reuse a hanging health endpoint"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/__webstrapper/auth?token=fake-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
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
  run_launcher

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  wait_for_file "$runtime_file" "runtime metadata file was not created for unverified server test"

  runtime_port="$(read_runtime_field "$runtime_file" port)"

  assert_ne "$requested_port" "$runtime_port" "launcher should not reuse unverified healthy server"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/__webstrapper/auth?token=fake-token"
  assert_not_contains "$browser_log" "stale-secret-token"
  assert_not_contains "$browser_log" "--app=http://127.0.0.1:${requested_port}/__webstrapper/auth?token=stale-secret-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
}

test_invalid_runtime_override_fails_loudly() {
  local tmpdir stderr_file requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/runtime.err"
  requested_port="$(pick_test_port)"

  if CODEX_UBUNTU_APP_LINUX_CMD="/definitely/missing-runtime" \
    CODEX_UBUNTU_PORT="$requested_port" \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher --browser >/dev/null 2>"$stderr_file"; then
    printf 'invalid runtime override unexpectedly succeeded\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "CODEX_UBUNTU_APP_LINUX_CMD is set to /definitely/missing-runtime"
}

test_invalid_browser_override_fails_loudly() {
  local tmpdir stderr_file requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/browser.err"
  requested_port="$(pick_test_port)"

  if CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
    CODEX_UBUNTU_BROWSER="/definitely/missing-browser" \
    CODEX_UBUNTU_PORT="$requested_port" \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher >/dev/null 2>"$stderr_file"; then
    printf 'invalid browser override unexpectedly succeeded\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "CODEX_UBUNTU_BROWSER is set to /definitely/missing-browser"
  if [ -e "${tmpdir}/state/codex-ubuntu/token.runtime" ]; then
    printf 'invalid browser override should not have started a runtime\n' >&2
    exit 1
  fi
}

test_non_loopback_bind_requires_opt_in() {
  local tmpdir stderr_file requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/bind.err"
  requested_port="$(pick_test_port)"

  if CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
    CODEX_UBUNTU_BIND="0.0.0.0" \
    CODEX_UBUNTU_PORT="$requested_port" \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher --browser >/dev/null 2>"$stderr_file"; then
    printf 'non-loopback bind unexpectedly succeeded without opt-in\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Refusing non-loopback bind 0.0.0.0 without CODEX_UBUNTU_ALLOW_NON_LOOPBACK=1"
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
  run_launcher

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  wait_for_file "$runtime_file" "runtime metadata file was not created for compatible runtime test"

  runtime_pid="$(read_runtime_field "$runtime_file" pid)"

  CODEX_UBUNTU_APP_LINUX_CMD="$compatible_runtime" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop

  if kill -0 "$runtime_pid" >/dev/null 2>&1; then
    printf 'compatible runtime is still alive after stop\n' >&2
    exit 1
  fi

  if [ -e "$runtime_file" ]; then
    printf 'compatible runtime metadata still exists after stop\n' >&2
    exit 1
  fi
}

test_manual_open_fallback_redacts_token_url() {
  local tmpdir stderr_file requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/fallback.err"
  requested_port="$(pick_test_port)"

  if PATH="${FAKE_XDOTOOL_DIR}:$PATH" \
    CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
    CODEX_UBUNTU_PORT="$requested_port" \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher --browser >/dev/null 2>"$stderr_file"; then
    printf 'manual-open fallback unexpectedly succeeded without a browser or opener\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Manual URL: http://127.0.0.1:${requested_port}/__webstrapper/auth?token=%3Credacted%3E"
  assert_contains "$stderr_file" "CODEX_UBUNTU_DEBUG_SHOW_TOKEN_URL=1"
  assert_not_contains "$stderr_file" "fake-token"
}

test_notifications_can_be_disabled() {
  local tmpdir stderr_file notify_log requested_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/notify.err"
  notify_log="${tmpdir}/notify.log"
  requested_port="$(pick_test_port)"

  if PATH="${FAKE_XDOTOOL_DIR}:$PATH" \
    CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
    CODEX_UBUNTU_DISABLE_NOTIFICATIONS=1 \
    CODEX_UBUNTU_TEST_NOTIFY_LOG="$notify_log" \
    CODEX_UBUNTU_PORT="$requested_port" \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_launcher --browser >/dev/null 2>"$stderr_file"; then
    printf 'notification-disable test unexpectedly succeeded without a browser or opener\n' >&2
    exit 1
  fi

  [ ! -e "$notify_log" ] || {
    printf 'notifications should have been disabled for this launcher invocation\n' >&2
    exit 1
  }
  assert_contains "$stderr_file" "Manual URL: http://127.0.0.1:${requested_port}/__webstrapper/auth?token=%3Credacted%3E"
}

test_lock_timeout_fails_loudly() {
  local tmpdir stderr_file lock_file lock_holder

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  stderr_file="${tmpdir}/lock.err"
  lock_file="${tmpdir}/state/codex-ubuntu/launcher.lock"
  mkdir -p "$(dirname "$lock_file")"

  (
    exec 9>"$lock_file"
    flock 9
    sleep 5
  ) &
  lock_holder="$!"
  register_pid "$lock_holder"
  sleep 0.1

  if CODEX_UBUNTU_LOCK_TIMEOUT_SECONDS=1 \
    XDG_CONFIG_HOME="${tmpdir}/config" \
    XDG_CACHE_HOME="${tmpdir}/cache" \
    XDG_STATE_HOME="${tmpdir}/state" \
    run_with_timeout 5 "$LAUNCHER" --stop >/dev/null 2>"$stderr_file"; then
    printf 'lock timeout test unexpectedly succeeded\n' >&2
    exit 1
  fi

  assert_contains "$stderr_file" "Another Codex Ubuntu Fallback launcher operation is already in progress."
  assert_contains "$stderr_file" "codex-ubuntu --status"
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
  run_launcher

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop

  PATH="${FAKE_XDOTOOL_DIR}:$PATH" \
  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_XDOTOOL_WINDOW_ID="4242" \
  CODEX_UBUNTU_PORT="$requested_port_two" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher

  assert_eq "2" "$(wc -l <"$browser_log" | tr -d '[:space:]')" "fresh runtime should relaunch browser even if a window exists"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${requested_port_one}/__webstrapper/auth?token=fake-token"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${requested_port_two}/__webstrapper/auth?token=fake-token"

  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
}

test_retries_fingerprint_capture_after_health() {
  local tmpdir browser_log requested_port runtime_file fingerprint_file runtime_port

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  requested_port="$(pick_test_port)"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_RUNTIME_METADATA_DELAY_MS=500 \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher

  runtime_file="${tmpdir}/state/codex-ubuntu/token.runtime"
  fingerprint_file="${tmpdir}/state/codex-ubuntu/runtime.fingerprint.json"
  wait_for_file "$runtime_file" "runtime metadata file was not created after delayed fingerprint capture"
  wait_for_file "$fingerprint_file" "runtime fingerprint file was not created after delayed fingerprint capture"

  runtime_port="$(read_runtime_field "$runtime_file" port)"
  assert_contains "$browser_log" "--app=http://127.0.0.1:${runtime_port}/__webstrapper/auth?token=fake-token"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
}

test_restart_keeps_outer_lock_during_verified_stop() {
  local tmpdir browser_log start_log requested_port token_file runtime_file launcher_one launcher_two launcher_one_log launcher_two_log status_one status_two

  tmpdir="$(mktemp -d)"
  register_tmpdir "$tmpdir"
  browser_log="${tmpdir}/browser.log"
  start_log="${tmpdir}/runtime-start.log"
  launcher_one_log="${tmpdir}/launcher-one.log"
  launcher_two_log="${tmpdir}/launcher-two.log"
  requested_port="$(pick_test_port)"
  token_file="${tmpdir}/state/codex-ubuntu/token"
  runtime_file="${token_file}.runtime"
  mkdir -p "${tmpdir}/state/codex-ubuntu" "${tmpdir}/cache" "${tmpdir}/config"

  CODEX_UBUNTU_TEST_HEALTH_MODE=unhealthy \
  CODEX_UBUNTU_TEST_START_LOG="$start_log" \
  "$FAKE_RUNTIME" web \
    --bind 127.0.0.1 \
    --port "$requested_port" \
    --token-file "$token_file" >/dev/null 2>&1 &
  register_pid "$!"

  wait_for_file "$runtime_file" "stale verified runtime metadata file was not created"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_START_LOG="$start_log" \
  CODEX_UBUNTU_TEST_HEALTH_DELAY_MS=1500 \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --browser >"$launcher_one_log" 2>&1 &
  launcher_one="$!"

  sleep 0.1

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  CODEX_UBUNTU_BROWSER="$FAKE_BROWSER" \
  CODEX_UBUNTU_TEST_BROWSER_LOG="$browser_log" \
  CODEX_UBUNTU_TEST_START_LOG="$start_log" \
  CODEX_UBUNTU_TEST_HEALTH_DELAY_MS=1500 \
  CODEX_UBUNTU_PORT="$requested_port" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --browser >"$launcher_two_log" 2>&1 &
  launcher_two="$!"

  if wait_for_background_result "$launcher_one" "$launcher_one_log" "first launcher"; then
    status_one=0
  else
    status_one="$?"
  fi

  if wait_for_background_result "$launcher_two" "$launcher_two_log" "second launcher"; then
    status_two=0
  else
    status_two="$?"
  fi

  assert_eq "0" "$status_one" "first launcher restart should succeed"
  assert_eq "0" "$status_two" "second launcher restart should succeed"
  assert_eq "2" "$(wc -l <"$start_log" | tr -d '[:space:]')" "only one replacement runtime should start while the outer lock is held"

  CODEX_UBUNTU_APP_LINUX_CMD="$FAKE_RUNTIME" \
  XDG_CONFIG_HOME="${tmpdir}/config" \
  XDG_CACHE_HOME="${tmpdir}/cache" \
  XDG_STATE_HOME="${tmpdir}/state" \
  run_launcher --stop
}

chmod +x \
  "$FAKE_RUNTIME" \
  "$FAKE_BROWSER" \
  "$FAKE_HEALTH_SERVER" \
  "$FAKE_HANGING_HEALTH_SERVER" \
  "${FAKE_XDOTOOL_DIR}/gio" \
  "${FAKE_XDOTOOL_DIR}/notify-send" \
  "${FAKE_XDOTOOL_DIR}/sensible-browser" \
  "${FAKE_XDOTOOL_DIR}/xdg-open" \
  "${FAKE_XDOTOOL_DIR}/xdotool"
trap cleanup_test_artifacts EXIT

test_browser_launch_creates_verified_state
test_web_log_redacts_runtime_secrets
test_stop_does_not_kill_unrelated_process
test_stop_refuses_runtime_with_tampered_fingerprint
test_stop_verified_runtime_removes_state
test_hanging_health_server_is_timed_out_and_not_reused
test_unverified_healthy_server_is_not_reused
test_invalid_runtime_override_fails_loudly
test_invalid_browser_override_fails_loudly
test_non_loopback_bind_requires_opt_in
test_compatible_runtime_is_stoppable
test_manual_open_fallback_redacts_token_url
test_notifications_can_be_disabled
test_lock_timeout_fails_loudly
test_fresh_runtime_relaunches_even_if_window_exists
test_retries_fingerprint_capture_after_health
test_restart_keeps_outer_lock_during_verified_stop

printf '[INFO] launcher smoke tests passed\n'
