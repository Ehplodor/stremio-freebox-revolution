import QtQuick 2.3
import QtMultimedia 5.0

// Lecteur de test base sur QtMultimedia (MediaPlayer + VideoOutput).
Rectangle {
    id: root
    color: "black"

    property string url: ""
    signal logMessage(string msg)

    function statusName(s) {
        switch (s) {
        case MediaPlayer.NoMedia: return "NoMedia";
        case MediaPlayer.Loading: return "Loading";
        case MediaPlayer.Loaded: return "Loaded";
        case MediaPlayer.Buffering: return "Buffering";
        case MediaPlayer.Stalled: return "Stalled";
        case MediaPlayer.Buffered: return "Buffered";
        case MediaPlayer.EndOfMedia: return "EndOfMedia";
        case MediaPlayer.InvalidMedia: return "InvalidMedia";
        default: return "inconnu (" + s + ")";
        }
    }

    function stopPlayback() {
        player.stop();
    }

    MediaPlayer {
        id: player
        autoLoad: true
        autoPlay: true
        source: root.url

        onStatusChanged: root.logMessage("QtMM statut : " + root.statusName(status))
        onPlaying: root.logMessage("QtMM lecture demarree, duree " + Math.round(duration / 1000) + " s")
        onError: root.logMessage("QtMM erreur " + error + " : " + errorString)
    }

    // Trace reguliere pour juger la lecture depuis la console du PC.
    Timer {
        interval: 5000
        repeat: true
        running: player.playbackState === MediaPlayer.PlayingState
        onTriggered: root.logMessage("QtMM position " + Math.round(player.position / 1000) + " s, "
                                     + root.statusName(player.status) + ", buffer " + Math.round(player.bufferProgress * 100) + " %"
                                     + (player.metaData.resolution ? ", " + player.metaData.resolution.width + "x" + player.metaData.resolution.height : ""))
    }

    VideoOutput {
        anchors.fill: parent
        source: player
    }

    Text {
        anchors { left: parent.left; bottom: parent.bottom; margins: 20 }
        color: "white"
        style: Text.Outline
        font.pixelSize: 22
        text: "QtMultimedia | " + root.statusName(player.status)
              + " | " + Math.round(player.position / 1000) + " / " + Math.round(player.duration / 1000) + " s"
              + " | Retour pour quitter"
    }
}
