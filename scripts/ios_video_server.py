"""Sirve los videos de prueba del reproductor del iPhone (scripts/ios_software_path.sh) como Real-Debrid: con saltos dentro del
archivo (Range) y, si se pide, una espera al principio de cada archivo, como cuando Real-Debrid prepara el enlace.

    python3 scripts/ios_video_server.py [puerto=8766] [segundos de espera=0] [carpeta=/tmp/orbital-43] [colgar=v=1]

`colgar`: las peticiones con esa consulta (p. ej. `v=1`, la versión latina que abre primero `-demo-versions`) nunca reciben
respuesta, como el motor del iPhone abriendo un archivo que no llega; las demás versiones sí suenan.
"""
import http.server
import os
import re
import socketserver
import sys
import time

ROOT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/orbital-43"; DELAY = float(sys.argv[2]) if len(sys.argv) > 2 else 0
HANG = sys.argv[4] if len(sys.argv) > 4 else ""
first = {}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_HEAD(self): self.handle_req(head=True)
    def do_GET(self): self.handle_req(head=False)
    def handle_req(self, head):
        if HANG and HANG in self.path.partition("?")[2].split("&"):
            while True: time.sleep(60)
        path = os.path.join(ROOT, self.path.lstrip("/").split("?")[0])
        if not os.path.isfile(path): self.send_error(404); return
        # Los primeros DELAY segundos de cada archivo, toda petición espera (como Real-Debrid preparando el enlace).
        t0 = first.setdefault(self.path.split("?")[0], time.time())
        wait = t0 + DELAY - time.time()
        if wait > 0: time.sleep(wait)
        size = os.path.getsize(path); start, end = 0, size - 1
        m = re.match(r"bytes=(\d*)-(\d*)", self.headers.get("Range", ""))
        if m:
            if m.group(1): start = int(m.group(1))
            if m.group(2): end = min(int(m.group(2)), size - 1)
            self.send_response(206); self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        else: self.send_response(200)
        self.send_header("Content-Type", "video/x-matroska"); self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1)); self.end_headers()
        if head: return
        with open(path, "rb") as f:
            f.seek(start); left = end - start + 1
            try:
                while left > 0:
                    chunk = f.read(min(1 << 16, left))
                    if not chunk: break
                    self.wfile.write(chunk); left -= len(chunk)
            except (BrokenPipeError, ConnectionResetError): pass
class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True
S(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8766), H).serve_forever()
