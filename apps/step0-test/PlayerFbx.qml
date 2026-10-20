import QtQuick 2.3
import fbx.media 1.0 as Media

// Lecteur de test base sur le lecteur natif Freebox (fbx.media.VideoPlayer),
// sur le modele de l'exemple miniplay de fbx/qmlapps_examples.
Media.VideoPlayer {
    id: player

    property string url: ""
    property string lastOsd: ""
    signal logMessage(string msg)

    function stopPlayback() {
        // L'API exacte de VideoPlayer n'est pas documentee : on teste avant d'appeler.
        if (typeof player.stop === "function")
            player.stop();
    }

    onMediaStateChanged: player.logMessage("fbx.media etat : " + mediaState)
    onDebugOsdString: lastOsd = str

    Component.onCompleted: {
        player.logMessage("fbx.media urlOpen(" + url + ")");
        urlOpen(url);
    }

    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 20 }
        color: "white"
        style: Text.Outline
        font.pixelSize: 22
        text: "fbx.media | " + player.mediaState + " | Retour pour quitter"
              + (player.lastOsd ? "\n" + player.lastOsd : "")
    }
}
