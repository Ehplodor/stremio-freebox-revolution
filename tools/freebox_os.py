#!/usr/bin/env python3
"""Client minimal de l'API Freebox OS (Freebox Server) : autorisation de l'appli, envoi de fichiers
sur le disque de la Freebox, liste des dossiers.

  python tools/freebox_os.py autoriser                 # a valider sur l'ecran de la Freebox Server
  python tools/freebox_os.py lister /                  # dossiers du disque
  python tools/freebox_os.py envoyer <fichier> <dossier Freebox>

Le jeton d'application est garde hors du depot, dans %APPDATA%/stremio-fbx/freebox-os.json.
L'autorisation se retire dans Freebox OS > Parametres > Gestion des acces.
"""

import base64
import hashlib
import hmac
import json
import mimetypes
import os
import sys
import time
import urllib.request
import uuid

HOST = "http://mafreebox.freebox.fr"
APP_ID = "com.ehplodor.stremiofbx"
CONFIG_DIR = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "stremio-fbx")
TOKEN_FILE = os.path.join(CONFIG_DIR, "freebox-os.json")


def api_base():
    with urllib.request.urlopen(HOST + "/api_version", timeout=10) as rsp:
        v = json.load(rsp)
    return "%s%sv%s" % (HOST, v["api_base_url"], v["api_version"].split(".")[0])


def call(url, data=None, method=None, session=None, raw=None, ctype=None):
    headers = {}
    body = None
    if raw is not None:
        body, headers["Content-Type"] = raw, ctype
    elif data is not None:
        body, headers["Content-Type"] = json.dumps(data).encode(), "application/json"
    if session:
        headers["X-Fbx-App-Auth"] = session
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as rsp:
            return json.load(rsp)
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8", "replace") or "{}")


def authorize(base):
    r = call(base + "/login/authorize/", {"app_id": APP_ID, "app_name": "Stremio Freebox",
                                          "app_version": "2.0.0", "device_name": os.environ.get("COMPUTERNAME", "PC")})
    if not r.get("success"):
        raise SystemExit("demande refusee : %s" % r)
    token, track = r["result"]["app_token"], r["result"]["track_id"]
    print("Demande envoyee : validez avec la fleche droite sur l'ecran de la Freebox Server (2 min).", flush=True)
    for _ in range(120):
        status = call("%s/login/authorize/%s" % (base, track))["result"]["status"]
        if status == "granted":
            os.makedirs(CONFIG_DIR, exist_ok=True)
            with open(TOKEN_FILE, "w", encoding="utf-8") as f:
                json.dump({"app_id": APP_ID, "app_token": token}, f)
            print("Autorisation accordee.")
            return
        if status != "pending":
            raise SystemExit("autorisation %s" % status)
        time.sleep(1)
    raise SystemExit("pas de reponse sur la Freebox (delai depasse)")


def session(base):
    with open(TOKEN_FILE, encoding="utf-8") as f:
        token = json.load(f)["app_token"]
    challenge = call(base + "/login/")["result"]["challenge"]
    password = hmac.new(token.encode(), challenge.encode(), hashlib.sha1).hexdigest()
    r = call(base + "/login/session/", {"app_id": APP_ID, "password": password})
    if not r.get("success"):
        raise SystemExit("ouverture de session refusee : %s" % r.get("msg", r))
    return r["result"]["session_token"], r["result"].get("permissions", {})


def b64(path):
    return base64.b64encode(path.encode("utf-8")).decode()


def list_dir(base, sess, path):
    r = call("%s/fs/ls/%s" % (base, b64(path)), session=sess)
    if not r.get("success"):
        raise SystemExit("liste impossible : %s" % r.get("msg", r))
    res = r["result"]
    return res.get("entries", []) if isinstance(res, dict) else res     # API v16 : { entries }


def upload(base, sess, local, folder):
    boundary = uuid.uuid4().hex
    name = os.path.basename(local)
    with open(local, "rb") as f:
        content = f.read()
    ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
    body = b"".join([
        b"--%s\r\nContent-Disposition: form-data; name=\"dirname\"\r\n\r\n%s\r\n" % (boundary.encode(), b64(folder).encode()),
        b"--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
        % (boundary.encode(), name.encode("utf-8"), ctype.encode()),
        content, b"\r\n--%s--\r\n" % boundary.encode()])
    r = call(base + "/upload/", session=sess, raw=body, ctype="multipart/form-data; boundary=" + boundary)
    if not r.get("success"):
        raise SystemExit("envoi de %s refuse : %s" % (name, r.get("msg", r)))
    return r


def upload_ws(base, sess, local, folder):
    """Envoi par websocket (API v16 : l'ancien envoi HTTP n'est plus disponible)."""
    import websocket                      # websocket-client
    name = os.path.basename(local)
    with open(local, "rb") as f:
        content = f.read()
    ws = websocket.create_connection(base.replace("http://", "ws://") + "/ws/upload",
                                     header=["X-Fbx-App-Auth: " + sess], timeout=60)
    try:
        ws.send(json.dumps({"action": "upload_start", "request_id": 1, "size": len(content),
                            "dirname": b64(folder), "filename": name, "force": "overwrite"}))
        r = json.loads(ws.recv())
        if not r.get("success"):
            raise SystemExit("envoi de %s refuse : %s" % (name, r.get("msg", r)))
        for i in range(0, len(content), 512 * 1024):
            ws.send_binary(content[i:i + 512 * 1024])
        ws.send(json.dumps({"action": "upload_finalize", "request_id": 1}))
        while True:
            r = json.loads(ws.recv())
            if r.get("action") == "upload_finalize":
                break
        if not r.get("success"):
            raise SystemExit("envoi de %s non finalise : %s" % (name, r.get("msg", r)))
        return r
    finally:
        ws.close()


def mkdir(base, sess, parent, name):
    return call(base + "/fs/mkdir/", {"parent": b64(parent), "dirname": name}, session=sess)


def main(args):
    base = api_base()
    if args[:1] == ["autoriser"]:
        authorize(base)
        return
    sess, perms = session(base)
    if args[:1] == ["droits"]:
        print(json.dumps(perms, indent=1))
    elif args[:1] == ["lister"]:
        for e in list_dir(base, sess, args[1] if len(args) > 1 else "/"):
            print(("[d] " if e.get("type") == "dir" else "    ") + e["name"])
    elif args[:1] == ["dossier"]:
        print(mkdir(base, sess, args[1], args[2]))
    elif args[:1] == ["envoyer"]:
        print(upload_ws(base, sess, args[1], args[2]).get("success"))
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
