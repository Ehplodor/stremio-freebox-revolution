import QtQuick 2.15
import QtMultimedia 5.15
import "../js/core/vtt.js" as Vtt

// Lecteur plein ecran : QtMultimedia (moteur fbxmms du Player) + calque de sous-titres VTT.
FocusScope {
    id: page

    property string title: ""
    property string source: ""
    property var cues: []
    property bool osd: true
    signal finished()
    signal logMessage(string msg)

    function stop() {
        player.stop();
        player.source = "";
    }

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
        default: return "Unknown(" + s + ")";
        }
    }

    function fmt(ms) {
        const s = Math.floor(ms / 1000);
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        return (h ? h + ":" + ("0" + m).slice(-2) : m) + ":" + ("0" + (s % 60)).slice(-2);
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    MediaPlayer {
        id: player
        autoPlay: true
        source: page.source
        onStatusChanged: {
            page.logMessage("lecteur : " + page.statusName(status));
            if (status === MediaPlayer.EndOfMedia)
                page.finished();
        }
        onError: page.logMessage("lecteur erreur " + error + " : " + errorString)
    }

    VideoOutput {
        anchors.fill: parent
        source: player
    }

    Text {
        id: subtitle
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 60 }
        width: parent.width * 0.8
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: "white"
        style: Text.Outline
        styleColor: "black"
        font.pixelSize: 34
        text: page.cues.length ? Vtt.textAt(page.cues, player.position) : ""
    }

    Rectangle {
        id: bar
        visible: page.osd
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 90
        color: "#c0000000"

        Text {
            x: 40
            y: 14
            color: "white"
            font.pixelSize: 24
            elide: Text.ElideRight
            width: parent.width - 80
            text: page.title
        }
        Text {
            x: 40
            y: 52
            color: "#c8d0d8"
            font.pixelSize: 18
            text: page.fmt(player.position) + " / " + page.fmt(player.duration) + "   " + page.statusName(player.status)
                  + (player.playbackState === MediaPlayer.PausedState ? "   pause" : "")
        }
    }

    Timer {
        id: osdTimer
        interval: 4000
        onTriggered: page.osd = false
    }

    function showOsd() {
        osd = true;
        osdTimer.restart();
    }

    // Position reguliere dans la console du PC (tests sans temoin).
    Timer {
        interval: 10000
        repeat: true
        running: player.playbackState === MediaPlayer.PlayingState
        onTriggered: page.logMessage("position " + page.fmt(player.position) + " " + page.statusName(player.status)
                                     + " | " + page.cues.length + " lignes de sous-titres, affiche : \""
                                     + subtitle.text.replace(/\n/g, " / ") + "\"")
    }

    focus: true
    Keys.onPressed: {
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_MediaTogglePlayPause:
        case Qt.Key_MediaPlay:
        case Qt.Key_MediaPause:
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            else
                player.play();
            break;
        case Qt.Key_Right:
        case Qt.Key_MediaNext:
            player.seek(Math.min(player.position + 30000, player.duration));
            break;
        case Qt.Key_Left:
        case Qt.Key_MediaPrevious:
            player.seek(Math.max(player.position - 10000, 0));
            break;
        default:
            return;
        }
        event.accepted = true;
        showOsd();
    }

    Component.onCompleted: showOsd()
}
