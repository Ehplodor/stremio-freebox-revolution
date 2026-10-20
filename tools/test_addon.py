#!/usr/bin/env python3
"""Addon Stremio de test, servi par le PC, pour essayer l'appli sur le Player sans addon tiers.

Il expose un catalogue "Tests Freebox" dont chaque film pointe vers une video synthetique
de apps/step0-test/media (generee par tools/make_test_media.sh), servie avec Range.

  python tools/test_addon.py            # http://<IP-du-PC>:8235/manifest.json

Pour les films "MP4" et "HEVC", deux sources supplementaires simulent une connexion lente
(debit bride) : elles sont annoncees en 127.0.0.1 pour passer par le prechargement de l'agent,
comme une vraie source Internet (prechargement desactive : elles sont illisibles).
"""

import argparse
import functools
import http.server
import json
import os
import sys
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbx_qml_run import NoCacheHandler, ThreadedHTTPServer  # noqa: E402

MEDIA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "step0-test", "media")
PREFIX = "fbxtest-"
SLOW_ITEMS = ("mp4-aac", "hevc-srt")
POSTER = "https://dummyimage.com/300x450/1d2733/ffffff.png&text="

ITEMS = [
    ("mp4-aac", "MP4 H.264 + AAC", "test.mp4", "Lecture directe attendue."),
    ("mkv-ac3", "MKV H.264 + AC3 5.1", "h264_ac3.mkv", "Lecture directe attendue (AC3)."),
    ("mkv-dts", "MKV H.264 + DTS 5.1", "h264_dts.mkv", "Lecture directe attendue (DTS)."),
    ("hevc-srt", "MKV HEVC + AC3 + sous-titres", "hevc_ac3_srt.mkv",
     "Transcodage H.264/AAC par le PC, sous-titres SRT externes affiches par l'appli."),
    ("h264-10bit", "MKV H.264 10 bits", "h264_10bit.mkv",
     "Le probe le croit lisible en direct ; si le Player echoue, l'appli doit basculer en transcodage."),
    ("multi", "MKV 2 pistes audio + 2 sous-titres", "multi.mkv",
     "Audio FR (440 Hz) et EN (880 Hz), sous-titres integres SRT FR et ASS EN."),
]

# Serie de test (episodes d'une minute) : enchainement, episode suivant prepare, source la plus proche.
SERIES_ID = PREFIX + "serie"
EPISODES = [(1, 1, "Premier", "test.mp4"), (1, 2, "Deuxieme", "h264_ac3.mkv"), (1, 3, "Troisieme", "test.mp4")]


def manifest():
    return {
        "id": "org.ehplodor.fbxtest",
        "version": "0.1.0",
        "name": "Tests Freebox",
        "description": "Videos synthetiques servies par le PC",
        "resources": ["catalog", "meta", "stream", "subtitles"],
        "types": ["movie", "series"],
        "idPrefixes": [PREFIX],
        "catalogs": [{"type": "movie", "id": "fbxtest", "name": "Tests Freebox"},
                     {"type": "series", "id": "fbxtest", "name": "Tests Freebox"}],
    }


def meta(item, base):
    key, name, _, desc = item
    return {
        "id": PREFIX + key,
        "type": "movie",
        "name": name,
        "poster": POSTER + urllib.parse.quote(name),
        "description": desc,
        "releaseInfo": "2026",
    }


def series_meta():
    return {
        "id": SERIES_ID,
        "type": "series",
        "name": "Serie de test",
        "poster": POSTER + "Serie%20de%20test",
        "description": "Trois episodes d'une minute : episode suivant, source la plus proche, prechargement.",
        "releaseInfo": "2026",
        "videos": [{"id": "%s:%d:%d" % (SERIES_ID, se, ep), "title": title, "season": se, "episode": ep,
                    "released": "2026-01-%02dT00:00:00.000Z" % ep} for se, ep, title, _ in EPISODES],
    }


def streams_for(name, base, port, slow):
    streams = [{"name": "PC", "title": name, "url": "%s/media/%s" % (base, name)}]
    if slow:
        # Adresse locale du PC : l'appli y voit une source distante et la fait precharger
        # par l'agent (seul a pouvoir la joindre). Le parametre n change a chaque
        # demande : prechargement neuf a chaque essai.
        far = "http://127.0.0.1:%s/slow/%s?n=%d&" % (port, name, time.time())
        streams += [
            {"name": "PC lent", "title": name + " - 1,5 Mbit/s (moitie du debit video)", "url": far + "kbps=1500"},
            {"name": "PC irregulier", "title": name + " - rapide puis 1 Mbit/s apres 6 Mo",
             "url": far + "kbps=1000&fastMb=6"},
        ]
    return streams


class AddonHandler(NoCacheHandler):
    def do_GET(self):
        path = urllib.parse.unquote(self.path.split("?", 1)[0])
        host = self.headers.get("Host") or "127.0.0.1:8235"
        base = "http://%s" % host
        items = {PREFIX + i[0]: i for i in ITEMS}

        if path == "/manifest.json":
            return self.json(manifest())
        if path == "/catalog/movie/fbxtest.json":
            return self.json({"metas": [meta(i, base) for i in ITEMS]})
        if path == "/catalog/series/fbxtest.json":
            return self.json({"metas": [series_meta()]})
        if path == "/meta/series/%s.json" % SERIES_ID:
            return self.json({"meta": series_meta()})
        if path.startswith("/stream/series/%s:" % SERIES_ID) and path.endswith(".json"):
            se_ep = path[len("/stream/series/%s:" % SERIES_ID):-5].split(":")
            ep = [e for e in EPISODES if ["%d" % e[0], "%d" % e[1]] == se_ep]
            return self.json({"streams": streams_for(ep[0][3], base, host.rsplit(":", 1)[-1], True) if ep else []})
        if path.startswith("/subtitles/series/"):
            return self.json({"subtitles": []})
        for resource in ("meta", "stream", "subtitles"):
            prefix = "/%s/movie/" % resource
            if path.startswith(prefix) and path.endswith(".json"):
                item = items.get(path[len(prefix):-5].split("/")[0])
                if not item:
                    return self.json({"meta": None} if resource == "meta" else {resource + "s": []})
                if resource == "meta":
                    return self.json({"meta": meta(item, base)})
                if resource == "stream":
                    return self.json({"streams": streams_for(item[2], base, host.rsplit(":", 1)[-1],
                                                             item[0] in SLOW_ITEMS)})
                subs = []
                if item[0] == "hevc-srt":
                    subs.append({"id": "srt-fr", "lang": "fre", "url": "%s/media/test.srt" % base})
                return self.json({"subtitles": subs})
        if path.startswith("/media/"):
            return super().do_GET()
        if path.startswith("/slow/"):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
            self._throttle = (int(q.get("kbps", ["1500"])[0]) * 1000 / 8, int(q.get("fastMb", ["0"])[0]) * 1048576)
            return super().do_GET()
        self.send_error(404)

    def json(self, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def translate_path(self, path):
        # /media/x ou /slow/x -> MEDIA_DIR/x
        rel = urllib.parse.unquote(path.split("?", 1)[0])
        return os.path.join(MEDIA_DIR, os.path.basename(rel))

    def copyfile(self, source, outputfile):
        throttle = getattr(self, "_throttle", None)
        if not throttle:
            return super().copyfile(source, outputfile)
        rate, fast = throttle
        remaining = getattr(self, "_range", None)
        remaining = remaining if remaining is not None else 1 << 62
        started, sent = time.time(), 0
        try:
            while remaining > 0:
                pos = source.tell()
                chunk = source.read(min(32768, remaining))
                if not chunk:
                    break
                outputfile.write(chunk)
                remaining -= len(chunk)
                if pos + len(chunk) > fast:
                    sent += len(chunk)
                    delay = started + sent / rate - time.time()
                    if delay > 0:
                        time.sleep(delay)
                else:
                    started = time.time()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass


def main():
    parser = argparse.ArgumentParser(description="Addon Stremio de test")
    parser.add_argument("--port", type=int, default=8235)
    args = parser.parse_args()
    handler = functools.partial(AddonHandler, directory=MEDIA_DIR)
    server = ThreadedHTTPServer(("0.0.0.0", args.port), handler)
    print("Addon de test : http://<IP-du-PC>:%d/manifest.json (Ctrl+C pour arreter)" % args.port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
