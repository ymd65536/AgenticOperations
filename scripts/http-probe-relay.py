#!/usr/bin/env python3
"""Small HTTP relay that performs read-only URL probes for the hosted agent.

Use:
  python3 scripts/http-probe-relay.py --port 8081

Then call:
  curl -X POST http://127.0.0.1:8081/probe -H 'Content-Type: application/json' \
    -d '{"url":"http://PUBLIC_IP/health"}'
"""

from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
import urllib.error
import urllib.parse
import urllib.request


class ProbeRelayHandler(BaseHTTPRequestHandler):
    server_version = "ProbeRelay/1.0"

    def do_GET(self) -> None:  # noqa: N802
        self._handle_probe_request()

    def do_POST(self) -> None:  # noqa: N802
        self._handle_probe_request()

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return

    def _handle_probe_request(self) -> None:
        try:
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path == "/health":
                self._send_json({"status": "ok", "service": "http-probe-relay"}, 200)
                return

            if parsed.path not in {"/probe", "/"}:
                self._send_json({"error": "not found"}, 404)
                return

            if self.command == "GET":
                query = urllib.parse.parse_qs(parsed.query)
                url = query.get("url", [None])[0]
            else:
                content_length = int(self.headers.get("Content-Length", "0"))
                raw = self.rfile.read(content_length) if content_length else b""
                body = json.loads(raw.decode("utf-8", errors="replace")) if raw else {}
                url = body.get("url")

            if not url or not isinstance(url, str) or not url.startswith(("http://", "https://")):
                self._send_json({"error": "missing or invalid url"}, 400)
                return

            request = urllib.request.Request(
                url,
                method="GET",
                headers={"User-Agent": "agentic-ops-probe-relay/1.0"},
            )
            try:
                with urllib.request.urlopen(request, timeout=10) as response:
                    status = int(response.getcode())
                    body = response.read(4096).decode("utf-8", errors="replace")
                    self._send_json({"url": url, "status": status, "body": body}, status)
                    return
            except urllib.error.HTTPError as exc:
                body = exc.read(4096).decode("utf-8", errors="replace")
                self._send_json({"url": url, "status": int(exc.code), "body": body}, int(exc.code))
                return
            except Exception as exc:  # pragma: no cover - communication failure path
                self._send_json({"url": url, "status": 503, "body": f"probe_error: {exc}", "error": str(exc)}, 503)
                return
        except Exception as exc:  # pragma: no cover - unexpected request contexts
            self._send_json({"error": str(exc)}, 500)

    def _send_json(self, payload: dict[str, Any], status_code: int) -> None:
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def main() -> None:
    parser = argparse.ArgumentParser(description="HTTP probe relay for the hosted agent")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8081)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), ProbeRelayHandler)
    print(f"Listening on http://{args.host}:{args.port}/probe")
    server.serve_forever()


if __name__ == "__main__":
    main()
