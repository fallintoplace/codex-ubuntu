#!/usr/bin/env python3
import signal
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def usage() -> int:
    sys.stderr.write("usage: fake_unverified_health_server.py --bind <ip> --port <port>\n")
    return 1


def parse_args(argv: list[str]) -> tuple[str, int]:
    bind = "127.0.0.1"
    port = None

    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--bind" and index + 1 < len(argv):
            bind = argv[index + 1]
            index += 2
        elif arg == "--port" and index + 1 < len(argv):
            port = int(argv[index + 1])
            index += 2
        else:
            index += 1

    if port is None:
        raise ValueError("missing port")

    return bind, port


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/__webstrapper/healthz":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"unverified")

    def log_message(self, fmt: str, *args: object) -> None:
        return


def main() -> int:
    try:
        bind, port = parse_args(sys.argv[1:])
    except ValueError:
        return usage()

    server = ThreadingHTTPServer((bind, port), Handler)
    shutting_down = threading.Event()

    def shutdown(_signum: int, _frame: object) -> None:
        if shutting_down.is_set():
            return
        shutting_down.set()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    try:
        server.serve_forever()
    finally:
        server.server_close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
