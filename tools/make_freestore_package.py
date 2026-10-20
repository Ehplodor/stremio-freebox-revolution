#!/usr/bin/env python3
"""Fabrique le paquet FreeStore : dist/<nom>-<version>.tar.gz

Par defaut l'appli entiere (app/, option B du plan V2 : fonctionne sans PC). Le lanceur de la V1
(bootstrap/, qui charge l'appli depuis le PC) reste disponible : --source bootstrap.

Meme format que "Make FreeStore Package" du plugin Qt Creator de Free (fbx/freebox-qtcreator-plugin,
src/freestorepackager.cc) : archive tar gzippee des fichiers du projet, manifest.json a la racine,
avec les memes verifications du manifest (identifiant, points d'entree, fichiers presents).
Le paquet s'envoie ensuite sur https://factory.free.fr (voir docs/INSTALLATION.md).
"""

import argparse
import gzip
import io
import json
import os
import re
import sys
import tarfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
EXCLUDE = re.compile(r"(\.fbxproject(\.user)?$|^\.|/\.|__pycache__|(^|/)_obsolete/)")


def check_manifest(manifest, files):
    errors = []
    if not re.fullmatch(r"\w+(\.\w+)+", manifest.get("identifier", "")):
        errors.append("identifier absent ou invalide")
    eps = manifest.get("entryPoints")
    if not isinstance(eps, dict) or not eps:
        errors.append("entryPoints absent")
        return errors
    defaults = 0
    for key, ep in eps.items():
        f = ep.get("file", "") if isinstance(ep, dict) else ""
        if not re.fullmatch(r"[/\w.+~-]+", f):
            errors.append("entryPoints.%s.file invalide" % key)
        elif f not in files:
            errors.append("entryPoints.%s.file absent du paquet : %s" % (key, f))
        defaults += 1 if isinstance(ep, dict) and ep.get("default") else 0
    if defaults != 1:
        errors.append("il faut exactement un point d'entree par defaut")
    icon = manifest.get("icon")
    if icon and icon not in files:
        errors.append("icone absente : %s" % icon)
    return errors


def main():
    parser = argparse.ArgumentParser(description="Paquet FreeStore (FreeFactory)")
    parser.add_argument("--source", default="app", help="dossier a empaqueter : app (defaut) ou bootstrap")
    args = parser.parse_args()
    SRC = os.path.join(ROOT, args.source)
    files = []
    for folder, _, names in os.walk(SRC):
        for name in names:
            rel = os.path.relpath(os.path.join(folder, name), SRC).replace(os.sep, "/")
            if not EXCLUDE.search(rel):
                files.append(rel)
    files.sort()
    with open(os.path.join(SRC, "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    errors = check_manifest(manifest, files)
    if errors:
        print("Paquet refuse :\n  - " + "\n  - ".join(errors))
        return 1

    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        dirs = sorted({os.path.dirname(f) for f in files if os.path.dirname(f)})
        for d in dirs:
            info = tarfile.TarInfo(d + "/")
            info.type = tarfile.DIRTYPE
            info.mode = 0o755
            tar.addfile(info)
        for rel in files:
            path = os.path.join(SRC, rel)
            info = tar.gettarinfo(path, rel)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mode = 0o644
            with open(path, "rb") as f:
                tar.addfile(info, f)

    out_dir = os.path.join(ROOT, "dist")
    os.makedirs(out_dir, exist_ok=True)
    name = re.sub(r"\W+", "-", manifest.get("name", "app")).strip("-").lower()
    out = os.path.join(out_dir, "%s-%s.tar.gz" % (name, manifest.get("version", "0")))
    with open(out, "wb") as f:
        f.write(gzip.compress(raw.getvalue()))
    print("Paquet : %s (%d fichiers, %d octets)" % (out, len(files), os.path.getsize(out)))
    for rel in files:
        print("  " + rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
