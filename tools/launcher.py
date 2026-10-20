#!/usr/bin/env python3
"""Lanceur unique cote PC : verifie tout, demarre Stremio, l'agent, puis l'appli sur le Player.

Double-cliquer sur Lancer-Stremio-Freebox.bat (a la racine du depot) suffit.

Options :
  --nom "PC du salon"       nom du PC affiche sur la tele (enregistre)
  --player 192.168.0.42     adresse du Player si la recherche automatique echoue
  --sans-player             ne pas afficher l'appli sur la tele (agent seul)
  --addon-test              servir aussi l'addon de test (videos de tools/make_test_media.sh)
  --demarrage-auto oui|non  lancer (ou plus) ce lanceur a l'ouverture de session Windows
"""

import argparse
import json
import os
import platform
import socket
import subprocess
import sys
import threading
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "companion"))
import capacity  # noqa: E402
import companion  # noqa: E402
import fbx_qml_run  # noqa: E402

LOG_DIR = os.path.join(companion.CONFIG_DIR, "logs")
STARTUP_LINK = os.path.join(os.environ.get("APPDATA", ""), "Microsoft", "Windows", "Start Menu",
                            "Programs", "Startup", "Stremio Freebox.bat")
OK, WARN, FAIL = "OK ", "!! ", "XX "


def line(state, text):
    print("  [%s] %s" % (state, text), flush=True)


def powershell(command, timeout=20):
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", command],
                             capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


# ----- Verifications -----

def check_python():
    ok = sys.version_info >= (3, 8)
    line(OK if ok else FAIL, "Python %s" % platform.python_version())
    return ok


def check_stremio(stremio):
    status = companion.stremio_status(stremio)
    if status["ok"]:
        line(OK, "Serveur Stremio %s actif (port 11470)" % status["version"])
        return True
    exe = companion.find_stremio_exe()
    if not exe:
        line(FAIL, "Stremio Desktop introuvable : installez-le depuis https://www.stremio.com/downloads")
        return False
    print("  ... demarrage de Stremio (%s), jusqu'a 60 s" % os.path.basename(exe), flush=True)
    ok, message = companion.start_stremio(stremio)
    line(OK if ok else FAIL, message)
    return ok


def check_port(port):
    """Port libre, ou deja occupe par un agent (on le reutilise)."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:%d/fbx/api/status" % port, timeout=2) as rsp:
            data = json.load(rsp)
            if data.get("agent") == "stremio-fbx":
                line(WARN, "Un agent tourne deja sur le port %d (autre fenetre ?) : il sera reutilise" % port)
                return "running"
    except Exception:  # noqa: BLE001
        pass
    with socket.socket() as s:
        if s.connect_ex(("127.0.0.1", port)) == 0:
            line(FAIL, "Le port %d est pris par un autre programme" % port)
            return "busy"
    line(OK, "Port %d libre" % port)
    return "free"


def check_pillow():
    if companion.Image is None:
        line(WARN, "Pillow absent : les affiches WebP ne seront pas converties (pip install pillow)")
    else:
        line(OK, "Pillow present (conversion des affiches WebP)")


def check_network():
    ip = companion.local_ip_towards()
    line(OK if ip else WARN, "Adresse du PC : %s" % (ip or "inconnue"))
    category = powershell("(Get-NetConnectionProfile | Select-Object -First 1).NetworkCategory")
    if category:
        line(OK, "Reseau Windows : %s" % ("Prive" if category == "Private" else "Public" if category == "Public" else category))
    exe = sys.executable.replace("'", "''")
    rules = powershell(
        "Get-NetFirewallApplicationFilter | Where-Object { $_.Program -eq '%s' } | "
        "Get-NetFirewallRule | Where-Object { $_.Enabled -eq 'True' -and $_.Direction -eq 'Inbound' } | "
        "ForEach-Object { $_.Action.ToString() + ':' + $_.Profile.ToString() }" % exe, timeout=40)
    profiles = rules.split() if rules else []
    allowed = [p for p in profiles if p.startswith("Allow") and (category in p or "Any" in p)]
    blocked = [p for p in profiles if p.startswith("Block") and (category in p or "Any" in p)]
    if blocked or (profiles and not allowed):
        line(WARN, "Pare-feu : Python est bloque en entree sur ce reseau ; la tele ne pourra pas joindre le PC."
             " Autorisez-le dans Pare-feu Windows > Autoriser une application (%s)." % sys.executable)
    elif allowed:
        line(OK, "Pare-feu : Python autorise en entree")
    else:
        line(WARN, "Pare-feu : aucune regle pour Python ; Windows demandera l'autorisation au premier acces"
             " (repondez Autoriser, reseau prive)")
    return ip


def find_player(address):
    if address:
        line(OK, "Player : %s (indique)" % address)
        return address
    print("  ... recherche du Player en mode developpeur", flush=True)
    found = fbx_qml_run.mdns_find(fbx_qml_run.DEVEL_SERVICE, 5)
    if found:
        line(OK, "Player trouve : %s" % found)
    else:
        line(WARN, "Player introuvable : allumez-le, verifiez le mode developpeur (Reglages > Systeme),"
             " ou passez --player <adresse>")
    return found


# ----- Agent, addon de test, lancement sur le Player -----

def start_agent(port, stremio, test_addon):
    server = companion.make_server(port, stremio, test_addon, quiet=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def start_test_addon():
    try:
        import test_addon
    except ImportError:
        return ""
    media = test_addon.MEDIA_DIR
    if not os.path.isdir(media) or not os.listdir(media):
        line(WARN, "Addon de test : pas de videos (lancer tools/make_test_media.sh)")
        return ""
    import functools
    handler = functools.partial(test_addon.AddonHandler, directory=media)
    server = fbx_qml_run.ThreadedHTTPServer(("0.0.0.0", 8235), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    url = "http://%s:8235/manifest.json" % companion.local_ip_towards()
    line(OK, "Addon de test : %s" % url)
    return url


def launch_on_player(player, pc_ip, port, stop):
    """Affiche l'appli sur la tele (lanceur du Player servi par l'agent) ; journal dans un fichier."""
    manifest = "http://%s:%d/fbx/bootstrap/manifest.json" % (pc_ip, port)
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, "player-%s.log" % time.strftime("%Y%m%d-%H%M%S"))
    log = open(log_path, "w", encoding="utf-8")
    try:
        result = fbx_qml_run.jsonrpc("http://%s/pub/devel" % player, "debug_qml_app", {
            "manifest_url": manifest, "entry_point": "main", "wait": False})
    except Exception as e:  # noqa: BLE001
        line(FAIL, "Le Player refuse le lancement : %s" % e)
        return None
    for key in ("stdout_port", "stderr_port"):
        threading.Thread(target=fbx_qml_run.dump_socket, args=(player, result[key], log, stop), daemon=True).start()
    line(OK, "Appli affichee sur la tele (journal : %s)" % log_path)
    return log_path


def enter_pressed():
    """Touche Entree dans la fenetre (Windows) ; False ailleurs ou sans console."""
    try:
        import msvcrt
    except ImportError:
        return False
    pressed = False
    try:
        while msvcrt.kbhit():
            pressed = msvcrt.getwch() in ("\r", "\n") or pressed
    except OSError:
        return False
    return pressed


def check_capacity(cfg, stremio, args):
    """Mesure (une fois par semaine) avant d'afficher l'appli : Stremio ne convertit qu'une
    video a la fois, une mesure pendant une lecture la perturberait."""
    if args.sans_mesure:
        return
    profiles = companion.stremio_status(stremio).get("profiles", [])
    current = cfg.get("capacity")
    if current and capacity.is_fresh(current, profiles) and not args.mesurer:
        enc = current.get("encoders", {})
        best = max((v.get("hevc", 0) for v in enc.values()), default=0)
        line(OK, "Capacites du PC (mesurees le %s) : conversion HEVC jusqu'a %.1fx, Internet %.0f Mbit/s"
             % (time.strftime("%d/%m", time.localtime(current["measuredAt"])), best, current.get("pcInternetMbps", 0)))
        return
    folder = os.path.join(companion.CONFIG_DIR, "bench")
    base = "http://127.0.0.1:%d/fbx/bench/" % args.port
    cfg = companion.load_config()
    cfg["capacity"] = capacity.measure(stremio, base, profiles, folder, log=lambda m: print(m, flush=True))
    companion.save_config(cfg)


def set_autostart(enable):
    if enable:
        bat = os.path.join(ROOT, "Lancer-Stremio-Freebox.bat")
        with open(STARTUP_LINK, "w", encoding="utf-8") as f:
            f.write('@echo off\r\nstart "Stremio Freebox" /min "%s"\r\n' % bat)
        print("Lancement automatique active : %s" % STARTUP_LINK)
    elif os.path.exists(STARTUP_LINK):
        os.remove(STARTUP_LINK)
        print("Lancement automatique desactive.")
    else:
        print("Le lancement automatique n'etait pas active.")


def main():
    parser = argparse.ArgumentParser(description="Lanceur Stremio pour Freebox Player")
    parser.add_argument("--nom", help="nom du PC affiche sur la tele")
    parser.add_argument("--player", default="", help="adresse IP du Player")
    parser.add_argument("--sans-player", action="store_true", help="ne pas afficher l'appli sur la tele")
    parser.add_argument("--addon-test", action="store_true", help="servir l'addon de test")
    parser.add_argument("--port", type=int, default=companion.DEFAULT_PORT)
    parser.add_argument("--demarrage-auto", choices=["oui", "non"])
    parser.add_argument("--mesurer", action="store_true", help="refaire la mesure des capacites du PC")
    parser.add_argument("--sans-mesure", action="store_true", help="ne pas mesurer les capacites du PC")
    args = parser.parse_args()

    if args.demarrage_auto:
        set_autostart(args.demarrage_auto == "oui")
        return 0

    cfg = companion.load_config()
    if args.nom:
        cfg["pcName"] = args.nom
        companion.save_config(cfg)

    stremio = companion.DEFAULT_STREMIO
    print("\n=== Stremio pour Freebox Player : %s (identifiant %s) ===\n" % (cfg["pcName"], cfg["pcId"]))
    if not check_python():
        return 1
    if not check_stremio(stremio):
        return 1
    port_state = check_port(args.port)
    if port_state == "busy":
        return 1
    check_pillow()
    pc_ip = check_network()
    player = None if args.sans_player else find_player(args.player)

    stop = threading.Event()
    if port_state == "free":
        test_url = start_test_addon() if args.addon_test else ""
        start_agent(args.port, stremio, test_url)
        line(OK, "Agent pret : http://%s:%d/fbx/api/status" % (pc_ip, args.port))
        check_capacity(cfg, stremio, args)
    if player and pc_ip:
        launch_on_player(player, pc_ip, args.port, stop)

    print("\nTout est pret. Laissez cette fenetre ouverte pendant que vous regardez.")
    print("Sur la tele : l'appli se connecte toute seule a \"%s\"." % cfg["pcName"])
    if player and pc_ip:
        print("Appli fermee sur la tele ? Appuyez sur Entree ici pour la reafficher.")
    print("Ctrl+C pour arreter.\n")
    warned = False
    last_check = time.time()
    try:
        while True:
            time.sleep(0.3)
            if player and pc_ip and enter_pressed():
                launch_on_player(player, pc_ip, args.port, stop)
            if time.time() - last_check < 30:
                continue
            last_check = time.time()
            ok = companion.stremio_status(stremio)["ok"]
            if not ok and not warned:
                line(WARN, "Le serveur Stremio ne repond plus ; la tele pourra le redemarrer (Reglages)")
            warned = not ok
    except KeyboardInterrupt:
        print("Arret.")
    finally:
        stop.set()
    return 0


if __name__ == "__main__":
    sys.exit(main())
