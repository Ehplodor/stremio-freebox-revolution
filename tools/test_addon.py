#!/usr/bin/env python3
"""Addon Stremio de test, servi par le PC, pour essayer l'appli sur le Player sans addon tiers.

Il expose un catalogue "Tests Freebox" dont chaque film pointe vers une video synthetique
de apps/step0-test/media (generee par tools/make_test_media.sh), servie avec Range.

  python tools/test_addon.py            # http://<IP-du-PC>:8235/manifest.json
"""

import argparse
import functools
import http.server
import json
import os
import sys
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fbx_qml_run import NoCacheHandler, ThreadedHTTPServer  # noqa: E402

MEDIA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "apps", "step0-test", "media")
PREFIX = "fbxtest-"
POSTER = "https://dummyimage.com/300x450/1d2733/ffffff.png&text="

ITEMS = [
    ("mp4-aac", "MP4 H.264 + AAC", "test.mp4", "Lecture directe attendue."),
    ("mkv-ac3", "MKV H.264 + AC3 5.1", "h264_ac3.mkv", "Lecture directe attendue (AC3)."),
    ("mkv-dts", "MKV H.264 + DTS 5.1", "h264_dts.mkv", "Lecture directe attendue (DTS)."),
    ("hevc-srt", "MKV HEVC + AC3 + sous-titres", "hevc_ac3_srt.mkv",
     "Transcodage H.264/AAC par le PC, sous-titres SRT externes affiches par l'appli."),
]


def manifest():
    return {
        "id": "org.ehplodor.fbxtest",
        "version": "0.1.0",
        "name": "Tests Freebox",
        "description": "Videos synthetiques servies par le PC",
        "resources": ["catalog", "meta", "stream", "subtitles"],
        "types": ["movie"],
        "idPrefixes": [PREFIX],
        "catalogs": [{"type": "movie", "id": "fbxtest", "name": "Tests Freebox"}],
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
        for resource in ("meta", "stream", "subtitles"):
            prefix = "/%s/movie/" % resource
            if path.startswith(prefix) and path.endswith(".json"):
                item = items.get(path[len(prefix):-5].split("/")[0])
                if not item:
                    return self.json({"meta": None} if resource == "meta" else {resource + "s": []})
                if resource == "meta":
                    return self.json({"meta": meta(item, base)})
                if resource == "stream":
                    return self.json({"streams": [{
                        "name": "PC",
                        "title": item[2],
                        "url": "%s/media/%s" % (base, item[2]),
                    }]})
                subs = []
                if item[0] == "hevc-srt":
                    subs.append({"id": "srt-fr", "lang": "fre", "url": "%s/media/test.srt" % base})
                return self.json({"subtitles": subs})
        if path.startswith("/media/"):
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
        # /media/x -> MEDIA_DIR/x
        rel = urllib.parse.unquote(path.split("?", 1)[0])[len("/media/"):]
        return os.path.join(MEDIA_DIR, os.path.basename(rel))


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
