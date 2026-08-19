#!/usr/bin/env python3
"""Local dev server for landing/ that mirrors production Netlify behavior.

Node is not installed on this machine, so `npx serve` is unavailable — and a
plain `python3 -m http.server` would not reproduce two things that matter:

  1. /invite/{CODE} — Netlify serves invite.html for paths beneath it. Without
     this, the invite page 404s locally and cannot be tested at its real URL.
  2. The security headers from netlify.toml, notably
     X-Content-Type-Options: nosniff. That header is what turned a wrong
     stylesheet path into a completely unstyled page in production. Sending it
     locally means that class of bug surfaces here instead of after a deploy.

Usage:  python3 scripts/dev-server.py [port]   (default 8000)
"""

import functools
import http.server
import os
import posixpath
import socketserver
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "landing")
ROOT = os.path.normpath(ROOT)
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8000

# Paths whose sub-routes are handled client-side by a single HTML file.
PREFIX_REWRITES = {
    "/invite/": "/invite.html",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        # Mirror netlify.toml [[headers]] for "/*"
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def translate_path(self, path):
        clean = posixpath.normpath(path.split("?", 1)[0].split("#", 1)[0])

        for prefix, target in PREFIX_REWRITES.items():
            if clean.startswith(prefix) and clean != prefix.rstrip("/"):
                candidate = os.path.join(ROOT, clean.lstrip("/"))
                # Only rewrite when nothing real is at that path, so a genuine
                # asset under the prefix still wins.
                if not os.path.isfile(candidate):
                    return os.path.join(ROOT, target.lstrip("/"))

        # Netlify pretty URLs: /terms -> terms.html
        if not os.path.splitext(clean)[1] and clean != "/":
            html = os.path.join(ROOT, clean.lstrip("/") + ".html")
            if os.path.isfile(html):
                return html

        return super().translate_path(path)

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))


if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    handler = functools.partial(Handler, directory=ROOT)
    with socketserver.TCPServer(("127.0.0.1", PORT), handler) as httpd:
        print(f"serving {ROOT}")
        print(f"  http://localhost:{PORT}/")
        print(f"  http://localhost:{PORT}/dashboard/")
        print(f"  http://localhost:{PORT}/invite/3ESHFJNX")
        print("ctrl-c to stop")
        httpd.serve_forever()
