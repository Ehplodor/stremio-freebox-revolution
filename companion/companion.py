#!/usr/bin/env python3
"""Service compagnon sur le PC, entre le Freebox Player et le serveur de streaming Stremio.

Le Player parle a ce service (port 11480 par defaut) au lieu du port 11470 de Stremio :
  - toutes les requetes sont relayees telles quelles vers le serveur Stremio ;
  - dans les master.m3u8 de /hlsv2, la piste #EXT-X-MEDIA:TYPE=SUBTITLES est retiree,
    car le lecteur HLS du Player se bloque a la fin de son premier segment
    (voir docs/ETAPE0-RESULTATS.md). Les sous-titres sont affiches par l'appli.

  - /image?url=... renvoie l'image en JPEG si elle est en WebP (le Player ne decode pas
    le WebP) ; necessite Pillow, sinon l'image est relayee telle quelle.

Sans dependance obligatoire (Python 3.8+, Pillow en option). Exemple :
  python companion/companion.py
  python companion/companion.py --port 11480 --stremio http://127.0.0.1:11470
"""

import argparse
import http.server
import socketserver
import sys
import io
import urllib.error
import urllib.parse
import urllib.request

try:
    from PIL import Image
except ImportError:  # Pillow absent : pas de conversion WebP
    Image = None

DEFAULT_PORT = 11480
DEFAULT_STREMIO = "http://127.0.0.1:11470"
HOP_HEADERS = ("Range", "Content-Type")


def strip_subtitles(playlist):
    """Retire la piste de sous-titres d'un master.m3u8 et sa reference dans STREAM-INF."""
    out = []
    for line in playlist.splitlines():
        if line.startswith("#EXT-X-MEDIA:TYPE=SUBTITLES"):
            continue
        out.append(line.replace(',SUBTITLES="subtitles"', ""))
    return "\n".join(out) + "\n"


def is_master_playlist(path):
    return path.split("?", 1)[0].endswith("/master.m3u8")


def relay(handler, stremio, path, method="GET"):
    """Relaie handler (BaseHTTPRequestHandler) vers stremio + path et ecrit la reponse."""
    headers = {k: handler.headers[k] for k in HOP_HEADERS if handler.headers.get(k)}
    body = None
    if method == "POST":
        length = int(handler.headers.get("Content-Length") or 0)
        body = handler.rfile.read(length) if length else b""
    req = urllib.request.Request(stremio + path, data=body, headers=headers, method=method)
    try:
        rsp = urllib.request.urlopen(req, timeout=300)
    except urllib.error.HTTPError as e:
        rsp = e
    except urllib.error.URLError as e:
        handler.send_error(502, "Serveur Stremio injoignable : %s" % e.reason)
        return
    status = getattr(rsp, "status", None) or rsp.code

    if is_master_playlist(path) and status == 200:
        data = strip_subtitles(rsp.read().decode("utf-8")).encode("utf-8")
        handler.send_response(status)
        handler.send_header("Content-Type", rsp.headers.get("Content-Type", "application/vnd.apple.mpegurl"))
        handler.send_header("Content-Length", str(len(data)))
        handler.end_headers()
        _write(handler, data)
        return

    # Reponse en flux continu (segments video, torrents) : pas de mise en memoire.
    handler.send_response(status)
    for k in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
        if rsp.headers.get(k):
            handler.send_header(k, rsp.headers[k])
    handler.end_headers()
    try:
        while True:
            chunk = rsp.read(65536)
            if not chunk:
                break
            handler.wfile.write(chunk)
    except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
        pass  # le Player a coupe (arret, saut dans la video) : normal
    finally:
        rsp.close()


def image(handler):
    """/image?url=... : WebP -> JPEG pour le Player."""
    qs = urllib.parse.parse_qs(urllib.parse.urlsplit(handler.path).query)
    url = (qs.get("url") or [""])[0]
    if not url.startswith(("http://", "https://")):
        handler.send_error(400, "url manquante")
        return
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", "Accept": "image/jpeg,image/png,*/*"})
        with urllib.request.urlopen(req, timeout=20) as rsp:
            data = rsp.read()
            ctype = rsp.headers.get("Content-Type", "application/octet-stream")
    except Exception as e:  # noqa: BLE001 - toute erreur reseau devient un 502
        handler.send_error(502, str(e))
        return
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP" and Image is not None:
        out = io.BytesIO()
        Image.open(io.BytesIO(data)).convert("RGB").save(out, "JPEG", quality=85)
        data, ctype = out.getvalue(), "image/jpeg"
    handler.send_response(200)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "max-age=86400")
    handler.end_headers()
    _write(handler, data)


def _write(handler, data):
    try:
        handler.wfile.write(data)
    except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
        pass


class CompanionHandler(http.server.BaseHTTPRequestHandler):
    stremio = DEFAULT_STREMIO
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path.startswith("/image?"):
            return image(self)
        relay(self, self.stremio, self.path)

    def do_HEAD(self):
        relay(self, self.stremio, self.path, "HEAD")

    def do_POST(self):
        relay(self, self.stremio, self.path, "POST")

    def log_message(self, fmt, *args):
        sys.stderr.write("[compagnon] %s %s\n" % (self.client_address[0], fmt % args))


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    # Pas de SO_REUSEADDR : sous Windows il laisse un second serveur prendre le meme port.
    allow_reuse_address = False


def main():
    parser = argparse.ArgumentParser(description="Relais entre le Freebox Player et le serveur Stremio")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="port d'ecoute (%d)" % DEFAULT_PORT)
    parser.add_argument("--stremio", default=DEFAULT_STREMIO, help="serveur Stremio (%s)" % DEFAULT_STREMIO)
    args = parser.parse_args()

    CompanionHandler.stremio = args.stremio.rstrip("/")
    server = ThreadedHTTPServer(("0.0.0.0", args.port), CompanionHandler)
    print("Compagnon a l'ecoute sur le port %d, relais vers %s. Ctrl+C pour arreter."
          % (args.port, CompanionHandler.stremio))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
