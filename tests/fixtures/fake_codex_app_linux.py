#!/usr/bin/env python3
import json
import os
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def read_env_int(name: str, default: int = 0) -> int:
    raw = os.environ.get(name, "")
    if not raw:
        return default

    try:
        return int(raw)
    except ValueError:
        return default


def usage() -> int:
    sys.stderr.write("usage: fake_codex_app_linux.py web --bind <ip> --port <port> --token-file <path>\n")
    return 1


def parse_web_args(argv: list[str]) -> dict[str, str]:
    bind = "127.0.0.1"
    port = None
    token_file = None

    index = 0
    while index < len(argv):
      arg = argv[index]
      if arg == "--bind" and index + 1 < len(argv):
          bind = argv[index + 1]
          index += 2
      elif arg == "--port" and index + 1 < len(argv):
          port = argv[index + 1]
          index += 2
      elif arg == "--token-file" and index + 1 < len(argv):
          token_file = argv[index + 1]
          index += 2
      else:
          index += 1

    if port is None or token_file is None:
        raise ValueError("missing required args")

    return {"bind": bind, "port": port, "token_file": token_file}


class Handler(BaseHTTPRequestHandler):
    token = ""
    health_mode = "healthy"
    health_ready_at = 0.0

    def do_GET(self) -> None:
        if self.path == "/__webstrapper/healthz":
            if self.health_mode == "unhealthy" or time.monotonic() < self.health_ready_at:
                self.send_response(503)
                self.send_header("Content-Type", "text/plain")
                self.end_headers()
                self.wfile.write(b"not ready")
                return

            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        body = f"<html><body>fake runtime token={self.token}</body></html>".encode("utf-8")
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        sys.stdout.write((fmt % args) + "\n")


def main() -> int:
    if len(sys.argv) >= 2 and sys.argv[1] in {"--version", "-v", "version"}:
        sys.stdout.write("fake-launcher.1\n")
        return 0

    if len(sys.argv) < 2 or sys.argv[1] != "web":
        return usage()

    try:
        config = parse_web_args(sys.argv[2:])
    except ValueError:
        return usage()

    bind = config["bind"]
    port = int(config["port"])
    token_file = config["token_file"]
    runtime_file = f"{token_file}.runtime"
    health_mode = os.environ.get("CODEX_UBUNTU_TEST_HEALTH_MODE", "healthy")
    health_delay_ms = read_env_int("CODEX_UBUNTU_TEST_HEALTH_DELAY_MS")
    runtime_metadata_delay_ms = read_env_int("CODEX_UBUNTU_TEST_RUNTIME_METADATA_DELAY_MS")
    start_log = os.environ.get("CODEX_UBUNTU_TEST_START_LOG", "")
    stdout_secret = os.environ.get("CODEX_UBUNTU_TEST_RUNTIME_STDOUT_SECRET", "")

    os.makedirs(os.path.dirname(token_file), exist_ok=True)
    token = "fake-token"
    with open(token_file, "w", encoding="utf-8") as handle:
        handle.write(token)

    if start_log:
        with open(start_log, "a", encoding="utf-8") as handle:
            handle.write(f"{os.getpid()} {port}\n")

    if stdout_secret:
        sys.stdout.write(f"runtime token={stdout_secret}\n")
        sys.stdout.write(f"Local login command: http://{bind}:{port}/?token={stdout_secret}\n")
        sys.stdout.flush()

    shutting_down = threading.Event()

    def write_runtime_metadata() -> None:
        if shutting_down.is_set():
            return

        with open(runtime_file, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "bind": bind,
                    "port": port,
                    "tokenFile": token_file,
                    "authDisabled": False,
                    "pid": os.getpid(),
                    "startedAt": int(time.time() * 1000),
                },
                handle,
            )
            handle.write("\n")

    if runtime_metadata_delay_ms > 0:
        def delayed_runtime_metadata() -> None:
            time.sleep(runtime_metadata_delay_ms / 1000)
            write_runtime_metadata()

        threading.Thread(target=delayed_runtime_metadata, daemon=True).start()
    else:
        write_runtime_metadata()

    server = ThreadingHTTPServer((bind, port), Handler)
    Handler.token = token
    Handler.health_mode = health_mode
    Handler.health_ready_at = time.monotonic() + (health_delay_ms / 1000)

    def shutdown(_signum: int, _frame: object) -> None:
        if shutting_down.is_set():
            return
        shutting_down.set()
        try:
            os.unlink(runtime_file)
        except FileNotFoundError:
            pass
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        try:
            os.unlink(runtime_file)
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
