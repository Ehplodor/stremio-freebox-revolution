import QtQuick 2.15
import QtMultimedia 5.15
import "../js/core/vtt.js" as Vtt

// Lecteur plein ecran : QtMultimedia (moteur fbxmms du Player) + calque de sous-titres VTT.
// Haut ou Menu : choix de la piste audio et des sous-titres.
FocusScope {
    id: page

    property string title: ""
    property string source: ""
    property var cues: []
    property bool osd: true
    property var audioTracks: []         // [{ label }]
    property int audioIndex: 0
    property bool audioSwitchable: false // seulement en transcodage (piste choisie par le compagnon)
    property var subtitleTracks: []      // [{ label }] ; le premier est « Desactives »
    property int subtitleIndex: 0
    property int resumeAt: -1            // position (ms) a retrouver apres un rechargement
    signal finished()
    signal logMessage(string msg)
    signal audioChosen(int index)
    signal subtitleChosen(int index)

    function stop() {
        player.stop();
        player.source = "";
    }

    // Recharge un autre flux (autre piste audio) en gardant la position.
    function reload(url) {
        resumeAt = player.position;
        logMessage("rechargement a " + fmt(resumeAt));
        source = url;
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
            if ((status === MediaPlayer.Buffered || status === MediaPlayer.Loaded) && page.resumeAt > 0 && seekable) {
                seek(page.resumeAt);
                page.logMessage("reprise a " + page.fmt(page.resumeAt));
                page.resumeAt = -1;
            }
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
        visible: page.osd || menu.visible
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
                  + "   ·   Haut : audio et sous-titres"
        }
    }

    // ----- Menu des pistes -----

    Rectangle {
        id: menu
        visible: false
        anchors { right: parent.right; top: bar.bottom; bottom: parent.bottom; margins: 30 }
        width: 760
        color: "#e0101418"
        radius: 6

        function open() {
            visible = true;
            audioList.currentIndex = page.audioIndex;
            subList.currentIndex = page.subtitleIndex;
            (page.audioTracks.length > 1 ? audioList : subList).forceActiveFocus();
        }
        function close() {
            visible = false;
            page.forceActiveFocus();
        }

        Text {
            id: audioTitle
            x: 20
            y: 16
            color: audioList.activeFocus ? "white" : "#9aa7b4"
            font.pixelSize: 22
            font.bold: true
            text: "Audio" + (page.audioTracks.length > 1 && !page.audioSwitchable ? " (non modifiable)" : "")
        }
        ListView {
            id: audioList
            anchors { left: parent.left; leftMargin: 20; top: audioTitle.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 20 }
            width: 340
            clip: true
            model: page.audioTracks
            highlightMoveDuration: 0
            highlight: Rectangle { color: "#2a6fdb"; radius: 4; visible: audioList.activeFocus }
            delegate: Text {
                width: audioList.width
                height: 40
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: (index === page.audioIndex ? "● " : "   ") + modelData.label
            }
            Keys.onRightPressed: subList.forceActiveFocus()
            Keys.onReturnPressed: {
                if (page.audioSwitchable && currentIndex !== page.audioIndex)
                    page.audioChosen(currentIndex);
                menu.close();
            }
        }

        Text {
            id: subTitle
            x: 390
            y: 16
            color: subList.activeFocus ? "white" : "#9aa7b4"
            font.pixelSize: 22
            font.bold: true
            text: "Sous-titres"
        }
        ListView {
            id: subList
            anchors { left: subTitle.left; right: parent.right; rightMargin: 20; top: subTitle.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 20 }
            clip: true
            model: page.subtitleTracks
            highlightMoveDuration: 0
            highlight: Rectangle { color: "#2a6fdb"; radius: 4; visible: subList.activeFocus }
            delegate: Text {
                width: subList.width
                height: 40
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: (index === page.subtitleIndex ? "● " : "   ") + modelData.label
            }
            Keys.onLeftPressed: if (page.audioTracks.length) audioList.forceActiveFocus()
            Keys.onReturnPressed: {
                if (currentIndex !== page.subtitleIndex)
                    page.subtitleChosen(currentIndex);
                menu.close();
            }
        }

        Keys.onPressed: {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape || event.key === Qt.Key_Menu) {
                event.accepted = true;
                menu.close();
            }
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
        case Qt.Key_Up:
        case Qt.Key_Menu:
            menu.open();
            break;
        default:
            return;
        }
        event.accepted = true;
        showOsd();
    }

    Component.onCompleted: showOsd()
}
