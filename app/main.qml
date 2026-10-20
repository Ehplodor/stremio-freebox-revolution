import QtQuick 2.15
import fbx.application 1.0

// Point d'entree de l'appli installee depuis le FreeStore (paquet : tools/make_freestore_package.py).
// Toute l'appli est dans le paquet : elle fonctionne sans PC, qui reste facultatif.
// Developpement : python tools/fbx_qml_run.py app/manifest.json (identifiant suffixe .dev).
Application {
    id: window

    AppRoot {
        anchors.fill: parent
        focus: true
    }
}
