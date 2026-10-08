#!/usr/bin/env python3
"""Minimal HTTP server with Range support for the Teaching Feeling web port.
python3 -m http.server does NOT support Range requests, which breaks <video> on WebKit.
"""
import os
import re
import sys
import http.server
import socketserver

ROOT = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else ".")
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8765

EXT = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".ks": "text/plain; charset=utf-8",
    ".tjs": "text/plain; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".mp3": "audio/mpeg",
    ".m4a": "audio/mp4",
    ".ogg": "audio/ogg",
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".ttf": "font/ttf",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".svg": "image/svg+xml",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        path = path.lstrip("/")
        return os.path.join(ROOT, path)

    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        return EXT.get(ext, "application/octet-stream")

    def do_GET(self):
        # WebKit aborts large media reads constantly; a broken pipe must never
        # take the handler (or the server) down with it.
        try:
            self._serve()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _serve(self):
        fs_path = self.translate_path(self.path)
        if os.path.isdir(fs_path):
            fs_path = os.path.join(fs_path, "index.html")
        if not os.path.isfile(fs_path):
            self.send_error(404, "File not found")
            return

        size = os.path.getsize(fs_path)
        ctype = self.guess_type(fs_path)
        rng = self.headers.get("Range")

        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)$", rng.strip())
            if m:
                start = int(m.group(1)) if m.group(1) else 0
                end = int(m.group(2)) if m.group(2) else size - 1
                if start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", "bytes */%d" % size)
                    self.end_headers()
                    return
                end = min(end, size - 1)
                length = end - start + 1
                self.send_response(206)
                self.send_header("Content-Type", ctype)
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
                self.send_header("Content-Length", str(length))
                self.end_headers()
                with open(fs_path, "rb") as f:
                    f.seek(start)
                    remaining = length
                    while remaining > 0:
                        chunk = f.read(min(65536, remaining))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                return

        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(fs_path, "rb") as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def log_message(self, fmt, *args):
        pass


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        print("serving %s on http://127.0.0.1:%d" % (ROOT, PORT), flush=True)
        httpd.serve_forever()
