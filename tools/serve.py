#!/usr/bin/env python3
"""Static file server with HTTP Range support.

`python3 -m http.server` ignores Range, and WebKit refuses to seek/play a
<video> it cannot range-request -- hence this.

Usage: python3 serve.py [port] [root]
"""
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
ROOT = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else os.getcwd()

TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".ks": "text/plain; charset=utf-8",
    ".tjs": "text/plain; charset=utf-8",
    ".ogg": "audio/ogg", ".m4a": "audio/mp4", ".mp3": "audio/mpeg",
    ".mp4": "video/mp4", ".webm": "video/webm",
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png",
    ".gif": "image/gif", ".webp": "image/webp", ".svg": "image/svg+xml",
    ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf",
}
RANGE = re.compile(r"bytes=(\d*)-(\d*)")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def send_head(self, body_len, ctype, status=200, extra=None):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(body_len))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()

    def do_GET(self):
        path = unquote(urlparse(self.path).path)
        if path.endswith("/"):
            path += "index.html"
        target = os.path.abspath(os.path.join(ROOT, path.lstrip("/")))
        if not target.startswith(ROOT) or not os.path.isfile(target):
            self.send_error(404, "not found")
            return

        size = os.path.getsize(target)
        ctype = TYPES.get(os.path.splitext(target)[1].lower(), "application/octet-stream")
        m = RANGE.match(self.headers.get("Range", ""))
        start, end = 0, size - 1
        if m:
            if m.group(1):
                start = int(m.group(1))
            if m.group(2):
                end = min(int(m.group(2)), size - 1)
            if start > end or start >= size:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
        length = end - start + 1
        status = 206 if m else 200
        extra = {"Content-Range": f"bytes {start}-{end}/{size}"} if m else None
        self.send_head(length, ctype, status, extra)
        with open(target, "rb") as fh:
            if start:
                fh.seek(start)
            remaining = length
            while remaining > 0:
                chunk = fh.read(min(64 * 1024, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    return
                remaining -= len(chunk)

    do_HEAD = do_GET


if __name__ == "__main__":
    os.chdir(ROOT)
    print(f"serving {ROOT} on http://127.0.0.1:{PORT}/index.html", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
