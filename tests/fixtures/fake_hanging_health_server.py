#!/usr/bin/env python3
import argparse
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class HangingHandler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/__webstrapper/healthz":
            time.sleep(10)
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, fmt: str, *args: object) -> None:
        return


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", required=True)
    parser.add_argument("--port", type=int, required=True)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.bind, args.port), HangingHandler)
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
