#!/usr/bin/env python3
"""Rendu des vrais ecrans QML de l'appli sur le PC (PyQt5, Qt 5.15) + controle des chevauchements.

Les modules de la box sont remplaces par tests/qml_stubs (fbx.application, QtMultimedia).
L'appli tourne pour de vrai (addons, Cinemeta... : il faut Internet), sans PC par defaut.

  python tools/render_screens.py                    # tous les ecrans dans dist/screens/
  python tools/render_screens.py home series:tt0903747 --out C:/tmp/shots
  python tools/render_screens.py --pc 192.168.0.16  # avec l'agent du PC
  python tools/render_screens.py --strict           # code de sortie 1 si des textes se chevauchent

Ecrans : home, discover, credits:<imdb>, home:down (tuile « Tout voir »), grid, search, settings, sort, account, movie:<imdb>, series:<imdb>, player.
Chaque capture est suivie de la liste des textes visibles qui se chevauchent (bug du 20/10/2026 :
titre de rangee sous les affiches).
"""

import argparse
import os
import sys
import tempfile

from PyQt5.QtCore import QMetaObject, QRectF, QTimer, QUrl, Q_ARG, QVariant
from PyQt5.QtGui import QGuiApplication
from PyQt5.QtQuick import QQuickView

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
STUBS = os.path.join(ROOT, "tests", "qml_stubs")
APP_QML = QUrl.fromLocalFile(os.path.join(ROOT, "app", "qml")).toString()
DEFAULT_SCREENS = ["home", "discover", "grid", "search", "settings", "sort", "account", "movie:tt15239678", "series:tt0903747", "player"]

APP_WRAPPER = """import QtQuick 2.15
import "%(app)s" as A
Item {
    width: 1280; height: 720
    property alias app: root
    A.AppRoot { id: root; anchors.fill: parent; launchHost: "%(pc)s" }
}
"""

PLAYER_WRAPPER = """import QtQuick 2.15
import "%(app)s" as A
Item {
    width: 1280; height: 720
    property var app: null
    Rectangle { anchors.fill: parent; color: "#203040" }
    A.PlayerPage {
        anchors.fill: parent
        title: "Breaking Bad"
        subtitleLine: "S1 E2  ·  Cat's in the Bag…  ·  1080p  ·  lecture directe"
        bufferVisible: true
        bufferTitle: "Préchargement…"
        bufferPercent: 68
        bufferEta: "9 s"
        bufferDetail: "Téléchargement 38.4 Mbit/s   ·   vidéo 8.2 Mbit/s"
        bufferedTo: 0.04
    }
}
"""


def painted_rect(item):
    """Rectangle reellement occupe par le texte d'un element Text, en coordonnees de la scene."""
    w, h = item.width(), item.height()
    cw = min(float(item.property("contentWidth") or 0), w) if w > 0 else float(item.property("contentWidth") or 0)
    ch = min(float(item.property("contentHeight") or 0), h) if h > 0 else float(item.property("contentHeight") or 0)
    ha = int(item.property("horizontalAlignment") or 1)
    va = int(item.property("verticalAlignment") or 32)
    x = 0.0 if ha & 1 or w <= 0 else (w - cw if ha & 2 else (w - cw) / 2)
    y = 0.0 if va & 32 or h <= 0 else (h - ch if va & 64 else (h - ch) / 2)
    return item.mapRectToScene(QRectF(x, y, cw, ch))


def visible_texts(root, window_rect):
    """Textes non vides effectivement visibles : [(texte, rectangle)]."""
    out = []

    def walk(item, clip):
        if not item.isVisible() or item.opacity() <= 0.01:
            return
        if item.clip():
            r = item.mapRectToScene(QRectF(0, 0, item.width(), item.height()))
            clip = clip.intersected(r)
        if item.metaObject().className().startswith("QQuickText") and "Input" not in item.metaObject().className():
            text = str(item.property("text") or "").strip()
            if text:
                r = painted_rect(item).intersected(clip)
                if r.width() > 2 and r.height() > 2:
                    out.append((text, r))
        for child in item.childItems():
            walk(child, clip)

    walk(root, window_rect)
    return out


def overlaps(texts):
    found = []
    for i in range(len(texts)):
        for j in range(i + 1, len(texts)):
            a, ra = texts[i]
            b, rb = texts[j]
            inter = ra.intersected(rb)
            # Quelques pixels : lettres jambages / interlignes, pas un chevauchement visible.
            if inter.width() > 4 and inter.height() > 4:
                found.append((a, b, inter))
    return found


def render(screen, out_dir, pc, wait_s):
    tmp = tempfile.mkdtemp(prefix="revo-render-")
    wrapper = os.path.join(tmp, "Wrapper.qml")
    with open(wrapper, "w", encoding="utf-8") as f:
        f.write((PLAYER_WRAPPER if screen == "player" else APP_WRAPPER) % {"app": APP_QML, "pc": pc})

    view = QQuickView()
    view.engine().addImportPath(STUBS)
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.resize(1280, 720)
    view.setSource(QUrl.fromLocalFile(wrapper))
    errors = [e.toString() for e in view.errors()]
    if errors:
        print("  erreurs QML :\n    " + "\n    ".join(errors))
        return False, []
    view.show()
    app = view.rootObject().property("app")

    def step():
        if app is None:
            return
        if screen == "home:down":
            # Deuxieme rangee de l'accueil (tuile « Tout voir » visible)
            from PyQt5.QtCore import Qt, QEvent
            from PyQt5.QtGui import QKeyEvent
            QMetaObject.invokeMethod(app, "showTab", Q_ARG(QVariant, 0))
            for kind in (QEvent.KeyPress, QEvent.KeyRelease):
                QTimer.singleShot(4000, lambda k=kind: QGuiApplication.sendEvent(view, QKeyEvent(k, Qt.Key_Down, Qt.NoModifier)))
            QTimer.singleShot(5000, lambda: [QGuiApplication.sendEvent(view, QKeyEvent(k, Qt.Key_Left, Qt.NoModifier))
                                             for k in (QEvent.KeyPress, QEvent.KeyRelease)])
        elif screen in ("home", "discover", "search", "settings"):
            QMetaObject.invokeMethod(app, "showTab", Q_ARG(QVariant, ["home", "discover", "search", "settings"].index(screen)))
        elif screen.startswith("credits:"):
            # Fiche puis panneau « Distribution et genres » (Droite x3, OK)
            from PyQt5.QtCore import Qt, QEvent
            from PyQt5.QtGui import QKeyEvent
            QMetaObject.invokeMethod(app, "openMeta", Q_ARG(QVariant, "movie"), Q_ARG(QVariant, screen.split(":", 1)[1]))
            for n, key in enumerate([Qt.Key_Right] * 3 + [Qt.Key_Return]):
                for kind in (QEvent.KeyPress, QEvent.KeyRelease):
                    QTimer.singleShot(4000 + 300 * n, lambda k=kind, c=key: QGuiApplication.sendEvent(view, QKeyEvent(k, c, Qt.NoModifier)))
        elif screen == "sort":
            QMetaObject.invokeMethod(app, "openSortSettings")
        elif screen == "grid":
            QMetaObject.invokeMethod(app, "openGrid", Q_ARG(QVariant, {
                "kind": "catalog", "transportUrl": "https://v3-cinemeta.strem.io/manifest.json", "type": "movie",
                "cid": "top", "name": "Popular", "addonName": "Cinemeta", "skip": True, "metas": []}))
        elif screen == "account":
            QMetaObject.invokeMethod(app, "openAccount")
        elif ":" in screen:
            kind, ident = screen.split(":", 1)
            QMetaObject.invokeMethod(app, "openMeta", Q_ARG(QVariant, kind), Q_ARG(QVariant, ident))

    result = {}

    def shoot():
        name = screen.replace(":", "-")
        path = os.path.join(out_dir, name + ".png")
        view.grabWindow().save(path)
        texts = visible_texts(view.rootObject(), QRectF(0, 0, 1280, 720))
        result["overlaps"] = overlaps(texts)
        result["path"] = path
        QGuiApplication.instance().quit()

    QTimer.singleShot(2500, step)
    QTimer.singleShot(int(wait_s * 1000), shoot)
    QGuiApplication.instance().exec_()
    view.close()
    view.deleteLater()
    print("  %s" % result.get("path"))
    return True, result.get("overlaps", [])


def main():
    parser = argparse.ArgumentParser(description="Rendu des ecrans QML de l'appli sur le PC")
    parser.add_argument("screens", nargs="*", help="ecrans (defaut : tous)")
    parser.add_argument("--out", default=os.path.join(ROOT, "dist", "screens"), help="dossier des captures")
    parser.add_argument("--pc", default="", help="adresse de l'agent du PC (defaut : sans PC)")
    parser.add_argument("--wait", type=float, default=12, help="attente avant capture, en secondes")
    parser.add_argument("--strict", action="store_true", help="echec si des textes se chevauchent")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    qapp = QGuiApplication(sys.argv[:1])  # noqa: F841 (reference gardee : sinon detruite)
    failed = False
    total = 0
    for screen in args.screens or DEFAULT_SCREENS:
        print("%s :" % screen)
        ok, found = render(screen, args.out, args.pc, args.wait)
        failed |= not ok
        for a, b, r in found:
            total += 1
            print("  CHEVAUCHEMENT (%d,%d %dx%d) : %r / %r"
                  % (r.x(), r.y(), r.width(), r.height(), a[:40], b[:40]))
    print("%d chevauchement(s)" % total)
    return 1 if failed or (args.strict and total) else 0


if __name__ == "__main__":
    sys.exit(main())
