#!/usr/bin/env python3
"""Service compagnon sur le PC, entre le Freebox Player et le serveur de streaming Stremio.

Le Player parle a ce service (port 11480 par defaut) au lieu du port 11470 de Stremio :
  - toutes les requetes sont relayees telles quelles vers le serveur Stremio ;
  - dans les master.m3u8 de /hlsv2, la piste #EXT-X-MEDIA:TYPE=SUBTITLES est retiree,
    car le lecteur HLS du Player se bloque a la fin de son premier segment
    (voir docs/ETAPE0-RESULTATS.md). Les sous-titres sont affiches par l'appli.

  - parametre fbxAudio=N sur un master.m3u8 : seule la piste audio N est gardee (le lecteur
    du Player ne sait pas changer de piste ; l'appli recharge le flux avec la piste choisie) ;
  - /subtitles/embedded.vtt?path=/hlsv2/...master.m3u8?...&id=N&codec=C : sous-titres
    integres a la video en un seul fichier VTT (le serveur Stremio ne les donne qu'en
    segments HLS de 10 s, ou en ASS) ;
  - /image?url=... renvoie l'image en JPEG si elle est en WebP (le Player ne decode pas
    le WebP) ; necessite Pillow, sinon l'image est relayee telle quelle.

Sans dependance obligatoire (Python 3.8+, Pillow en option). Exemple :
  python companion/companion.py
  python companion/companion.py --port 11480 --stremio http://127.0.0.1:11470
"""

import argparse
import http.server
import io
import ipaddress
import re
import socket
import socketserver
import sys
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


def strip_subtitles(playlist, audio=None):
    """Retire la piste de sous-titres d'un master.m3u8 et sa reference dans STREAM-INF.
    audio : identifiant de la seule piste audio a garder (None : toutes)."""
    out = []
    for line in playlist.splitlines():
        if line.startswith("#EXT-X-MEDIA:TYPE=SUBTITLES"):
            continue
        if audio is not None and line.startswith("#EXT-X-MEDIA:TYPE=AUDIO"):
            if 'URI="audio%s.m3u8' % audio not in line:
                continue
            line = re.sub(r"DEFAULT=NO", "DEFAULT=YES", line)
        out.append(line.replace(',SUBTITLES="subtitles"', ""))
    return "\n".join(out) + "\n"


def query_param(path, name):
    values = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query).get(name)
    return values[0] if values else None


VTT_TIME = re.compile(r"(\d+:)?\d{2}:\d{2}[.,]\d{3}\s*-->")


def vtt_cues(text):
    """Cues d'un VTT : [(entete temps, texte)]."""
    cues = []
    for block in re.split(r"\n\s*\n", text.replace("\r", "")):
        lines = block.strip().split("\n")
        for i, line in enumerate(lines):
            if VTT_TIME.match(line):
                body = "\n".join(lines[i + 1:]).strip()
                if body:
                    cues.append((line.strip(), body))
                break
    return cues


def ass_time(t):
    h, m, rest = t.strip().split(":")
    sec, cs = rest.split(".")
    return "%02d:%02d:%02d.%03d" % (int(h), int(m), int(sec), int(cs.ljust(3, "0")[:3]))


def ass_to_cues(text):
    """Dialogues d'un fichier ASS/SSA -> cues VTT (styles ignores)."""
    cues = []
    fields = None
    for line in text.splitlines():
        if line.startswith("Format:") and fields is None and "Text" in line:
            fields = [f.strip() for f in line[7:].split(",")]
        elif line.startswith("Dialogue:") and fields:
            parts = line[9:].split(",", len(fields) - 1)
            row = dict(zip(fields, parts))
            body = re.sub(r"\{[^}]*\}", "", row.get("Text", "")).replace("\\N", "\n").replace("\\n", "\n").strip()
            if body:
                cues.append(("%s --> %s" % (ass_time(row["Start"]), ass_time(row["End"])), body))
    return cues


def fetch_text(url, timeout=120):
    with urllib.request.urlopen(url, timeout=timeout) as rsp:
        return rsp.read().decode("utf-8", "replace")


def embedded_subtitles(stremio, path, sub_id, codec):
    """VTT complet d'une piste de sous-titres integree, via le serveur Stremio."""
    base, _, query = path.partition("?")
    folder = base.rsplit("/", 1)[0]               # /hlsv2/<id>
    fetch_text(stremio + path)                    # cree le convertisseur cote serveur
    if codec in ("ass", "ssa"):
        cues = ass_to_cues(fetch_text("%s%s/source/subtitle/%s.ass?%s" % (stremio, folder, sub_id, query)))
    else:
        playlist_url = "%s%s/subtitle%s.m3u8?%s" % (stremio, folder, sub_id, query)
        playlist = fetch_text(playlist_url)
        cues = []
        for line in playlist.splitlines():
            if line and not line.startswith("#"):
                cues.extend(vtt_cues(fetch_text(urllib.parse.urljoin(playlist_url, line))))
    seen, unique = set(), []
    for cue in cues:                              # les segments se recouvrent
        if cue not in seen:
            seen.add(cue)
            unique.append(cue)
    unique.sort(key=lambda c: c[0])
    return "WEBVTT\n\n" + "\n\n".join("%s\n%s" % c for c in unique) + "\n"


def send_text(handler, status, text, ctype):
    data = text.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", ctype)
    handler.send_header("Content-Length", str(len(data)))
    handler.end_headers()
    _write(handler, data)


def subtitles_route(handler, stremio):
    path = query_param(handler.path, "path") or ""
    sub_id = query_param(handler.path, "id") or ""
    codec = (query_param(handler.path, "codec") or "").lower()
    if not path.startswith("/hlsv2/") or not sub_id.isdigit():
        handler.send_error(400, "path ou id invalide")
        return
    try:
        send_text(handler, 200, embedded_subtitles(stremio, path, sub_id, codec), "text/vtt; charset=utf-8")
    except Exception as e:  # noqa: BLE001 - erreur du serveur Stremio ou de format : 502
        handler.send_error(502, "sous-titres indisponibles : %s" % e)


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
        audio = query_param(path, "fbxAudio")
        data = strip_subtitles(rsp.read().decode("utf-8"), audio).encode("utf-8")
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
    if not rsp.headers.get("Content-Length") and method != "HEAD":
        # Reponse sans taille (envoi par morceaux cote Stremio, que urllib a deja decode) :
        # en HTTP/1.1 le client ne saurait pas ou elle finit et attendrait sans fin.
        # On ferme la connexion a la fin pour la delimiter.
        handler.send_header("Connection", "close")
        handler.close_connection = True
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


def is_public_host(host):
    """Vrai si toutes les adresses du nom sont publiques (ni boucle locale ni reseau prive)."""
    try:
        infos = socket.getaddrinfo(host, None)
    except (socket.gaierror, UnicodeError):
        return False
    for info in infos:
        addr = ipaddress.ip_address(info[4][0].split("%", 1)[0])
        if not addr.is_global:
            return False
    return True


def image(handler):
    """/image?url=... : WebP -> JPEG pour le Player."""
    qs = urllib.parse.parse_qs(urllib.parse.urlsplit(handler.path).query)
    url = (qs.get("url") or [""])[0]
    if not url.startswith(("http://", "https://")):
        handler.send_error(400, "url manquante")
        return
    # Les affiches viennent d'Internet. Refuser le reste evite que n'importe quel appareil
    # du reseau se serve du compagnon pour lire les services locaux du PC (127.0.0.1...).
    if not is_public_host(urllib.parse.urlsplit(url).hostname or ""):
        handler.send_error(403, "adresse non publique refusee")
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
        try:
            Image.open(io.BytesIO(data)).convert("RGB").save(out, "JPEG", quality=85)
        except Exception as e:  # noqa: BLE001 - image corrompue : 502 au lieu d'une connexion coupee
            handler.send_error(502, "image illisible : %s" % e)
            return
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
        if self.path.startswith("/subtitles/embedded.vtt?"):
            return subtitles_route(self, self.stremio)
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
