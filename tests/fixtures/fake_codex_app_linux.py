#!/usr/bin/env python3
import json
import os
import signal
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


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

    def do_GET(self) -> None:
        if self.path == "/__webstrapper/healthz":
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

    os.makedirs(os.path.dirname(token_file), exist_ok=True)
    token = "fake-token"
    with open(token_file, "w", encoding="utf-8") as handle:
        handle.write(token)

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

    server = ThreadingHTTPServer((bind, port), Handler)
    Handler.token = token
    shutting_down = threading.Event()

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
