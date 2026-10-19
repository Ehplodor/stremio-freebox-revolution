#!/usr/bin/env python3
"""Lance une appli QML sur un Freebox Player en mode developpeur.

Reecriture en Python 3, sans dependance, de bin/fbx-qml-run de
https://github.com/fbx/freebox-dev-utils (domaine public) :
  1. sert le dossier de l'appli en HTTP sur le PC ;
  2. demande au Player (JSON-RPC http://<player>/pub/devel, methode
     debug_qml_app) de charger manifest.json depuis ce serveur ;
  3. affiche la sortie stdout/stderr de l'appli renvoyee par le Player.

Exemple :
  python tools/fbx_qml_run.py apps/step0-test/manifest.json
  python tools/fbx_qml_run.py -t 192.168.0.20 apps/step0-test/manifest.json
"""

import argparse
import functools
import http.server
import json
import os
import random
import select
import socket
import socketserver
import struct
import sys
import threading
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "companion"))
import companion  # noqa: E402

MDNS_ADDR = ("224.0.0.251", 5353)
DEVEL_SERVICE = "_fbx-devel._tcp.local."


def mdns_find(service, timeout=3.0):
    """Envoie une requete mDNS PTR et renvoie l'IP du premier appareil qui repond."""
    query = struct.pack(">HHHHHH", 0, 0, 1, 0, 0, 0)
    for label in service.rstrip(".").split("."):
        query += bytes([len(label)]) + label.encode()
    query += b"\x00" + struct.pack(">HH", 12, 1)  # PTR, IN

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
    sock.settimeout(0.5)
    deadline = time.time() + timeout
    needle = service.split(".")[0].encode()
    try:
        while time.time() < deadline:
            sock.sendto(query, MDNS_ADDR)
            try:
                data, addr = sock.recvfrom(9000)
            except socket.timeout:
                continue
            # Reponse (bit QR) qui mentionne le service recherche.
            if len(data) > 2 and data[2] & 0x80 and needle in data:
                return addr[0]
    finally:
        sock.close()
    return None


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    """Serveur de fichiers sans cache, avec prise en charge de Range (lecteurs video, ffmpeg)."""

    STREMIO = companion.DEFAULT_STREMIO
    entry_file = "/main.qml"
    entry_loaded = threading.Event()     # le Player a demande le fichier QML d'entree

    def do_GET(self):
        if self.path.split("?", 1)[0] == self.entry_file:
            self.entry_loaded.set()
        # /stremio/... : meme relais que le service compagnon (companion/companion.py).
        if self.path.startswith("/stremio/"):
            self._proxied = True
            return companion.relay(self, self.STREMIO, self.path[len("/stremio"):])
        return super().do_GET()

    def send_head(self):
        self._range = None
        rng = self.headers.get("Range", "")
        path = self.translate_path(self.path)
        if not rng.startswith("bytes=") or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        start_s, _, end_s = rng[6:].split(",")[0].strip().partition("-")
        try:
            if start_s:
                start = int(start_s)
                end = min(int(end_s), size - 1) if end_s else size - 1
            else:
                start, end = max(size - int(end_s), 0), size - 1
        except ValueError:
            return super().send_head()
        if start >= size or start > end:
            self.send_response(416)
            self.send_header("Content-Range", "bytes */%d" % size)
            self.end_headers()
            return None
        f = open(path, "rb")
        f.seek(start)
        self._range = end - start + 1
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        self.send_header("Content-Length", str(self._range))
        self.end_headers()
        return f

    def copyfile(self, source, outputfile):
        remaining = getattr(self, "_range", None)
        try:
            if remaining is None:
                return super().copyfile(source, outputfile)
            while remaining > 0:
                chunk = source.read(min(65536, remaining))
                if not chunk:
                    break
                outputfile.write(chunk)
                remaining -= len(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass  # le lecteur a coupe la connexion (arret, saut) : normal

    def end_headers(self):
        if not getattr(self, "_proxied", False):
            self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("[http] %s %s\n" % (self.client_address[0], fmt % args))


class ThreadedHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    # Pas de SO_REUSEADDR : sous Windows il laisse un second serveur prendre le meme port
    # et lui voler les requetes du Player.
    allow_reuse_address = False


def local_addr_to(host, port=80):
    with socket.create_connection((host, port), timeout=5) as s:
        return s.getsockname()[0]


def jsonrpc(endpoint, method, params):
    body = json.dumps({
        "jsonrpc": "2.0",
        "id": str(random.randint(0, 10000)),
        "method": method,
        "params": params,
    }).encode()
    req = urllib.request.Request(endpoint, body, {
        "Content-Type": "application/json",
        "Accept": "application/json",
    })
    with urllib.request.urlopen(req, timeout=15) as rsp:
        answer = json.load(rsp)
    print("[rpc]", answer)
    if "result" in answer:
        return answer["result"]
    err = answer.get("error", {})
    raise RuntimeError("JSON-RPC %s : %s" % (err.get("code", -1), err.get("message", "pas de resultat")))


def dump_socket(host, port, out, stop):
    sock = socket.create_connection((host, port))
    sock.setblocking(False)
    try:
        while not stop.is_set():
            ready, _, _ = select.select([sock], [], [], 0.5)
            if not ready:
                continue
            data = sock.recv(4096)
            if not data:
                break
            out.write(data.decode("utf-8", "replace"))
            out.flush()
    finally:
        sock.close()


def main():
    parser = argparse.ArgumentParser(description="Lance une appli QML sur un Freebox Player")
    parser.add_argument("manifest", help="chemin du manifest.json de l'appli")
    parser.add_argument("-t", dest="target", default="", help="IP du Player (sinon recherche mDNS)")
    parser.add_argument("-p", dest="http_port", type=int, default=8234, help="port HTTP local (8234)")
    parser.add_argument("-e", dest="entry_point", default="main", help="point d'entree (main)")
    parser.add_argument("--serve-only", action="store_true",
                        help="sert seulement le dossier, sans contacter le Player (test)")
    args = parser.parse_args()

    manifest = os.path.abspath(args.manifest)
    app_dir = os.path.dirname(manifest)

    host = args.target
    if not host and not args.serve_only:
        print("Recherche du Player en mode developpeur (%s)..." % DEVEL_SERVICE)
        host = mdns_find(DEVEL_SERVICE)
        if not host:
            sys.exit("Player introuvable par mDNS : mode developpeur actif ? Sinon passez -t <IP du Player>.")
        print("Player trouve :", host)

    bind = local_addr_to(host) if host else "0.0.0.0"
    handler = functools.partial(NoCacheHandler, directory=app_dir)
    server = ThreadedHTTPServer((bind, args.http_port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    base = "http://%s:%d/" % (bind, args.http_port)
    print("Appli servie depuis", app_dir, "sur", base)

    stop = threading.Event()
    threads = []
    try:
        if not args.serve_only:
            with open(manifest, encoding="utf-8") as f:
                entry = json.load(f).get("entryPoints", {}).get(args.entry_point, {}).get("file", "main.qml")
            NoCacheHandler.entry_file = "/" + entry
            # Relance juste apres une autre appli : le Player lit parfois manifest.json sans
            # lancer l'appli. Si le fichier d'entree n'est pas demande en 10 s, on redemande.
            for attempt in range(1, 4):
                NoCacheHandler.entry_loaded.clear()
                result = jsonrpc("http://%s/pub/devel" % host, "debug_qml_app", {
                    "manifest_url": base + "manifest.json",
                    "entry_point": args.entry_point,
                    "wait": False,
                })
                if NoCacheHandler.entry_loaded.wait(10):
                    break
                print("L'appli ne demarre pas (essai %d/3), nouvelle demande..." % attempt)
            for port, out in ((result["stdout_port"], sys.stdout), (result["stderr_port"], sys.stderr)):
                t = threading.Thread(target=dump_socket, args=(host, port, out, stop), daemon=True)
                t.start()
                threads.append(t)
        print("Ctrl+C pour arreter.")
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        print("Arret.")
        stop.set()
        for t in threads:
            t.join(2)
        server.shutdown()


if __name__ == "__main__":
    main()
