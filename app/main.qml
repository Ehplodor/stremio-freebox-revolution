import QtQuick 2.15
import fbx.application 1.0

// Point d'entree direct (developpement : python tools/fbx_qml_run.py app/manifest.json).
// En usage normal, l'appli est chargee par le lanceur du Player (bootstrap/), qui trouve le PC.
Application {
    id: window

    AppRoot {
        anchors.fill: parent
        focus: true
    }
}
