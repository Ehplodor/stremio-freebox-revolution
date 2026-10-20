import QtQuick 2.15
import QtMultimedia 5.15
import "../js/core/vtt.js" as Vtt
import "../js/theme.js" as T

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
    property int startAt: 0              // reprise de lecture : position de depart (ms)
    property string subtitleLine: ""     // episode, source... sous le titre
    property string nextTitle: ""        // episode suivant ("" : aucun)
    property bool autoNext: true         // enchainer l'episode suivant
    // Decalage des sous-titres (ms) : positif = affiches plus tard, negatif = plus tot.
    property int subDelay: 0

    function shiftSubtitles(step) {
        subDelay = step === 0 ? 0 : Math.max(-60000, Math.min(60000, subDelay + step));
        delayHint.show();
    }

    function delayText() {
        if (subDelay === 0)
            return "0 s (synchro d'origine)";
        return (subDelay > 0 ? "+" : "-") + (Math.abs(subDelay) / 1000).toFixed(2).replace(".", ",") + " s"
            + (subDelay > 0 ? "  ·  plus tard" : "  ·  plus tot");
    }
    signal nextRequested()
    // Prechargement par le PC (pilote par AppRoot) : ecran d'attente et partie prechargee.
    property bool bufferVisible: false
    property string bufferTitle: ""
    property int bufferPercent: 0
    property string bufferEta: ""
    property string bufferDetail: ""
    property real bufferedFrom: 0        // debut de la partie prechargee (0..1)
    property real bufferedTo: 0          // fin de la partie prechargee (0..1)
    signal skipBuffering()

    function pausePlayer() {
        player.pause();
    }

    function resumePlayer() {
        player.play();
    }
    readonly property int positionMs: player.position
    readonly property int durationMs: player.duration
    signal finished()
    signal failed(string reason)
    property bool failedOnce: false      // erreur + media invalide arrivent souvent ensemble
    // Le lecteur du Player peut rester sur "Loading" sans erreur (ex. H.264 10 bits) :
    // sans image apres ce delai, la lecture est consideree en echec.
    property int startTimeoutMs: 15000
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
        startWatchdog.restart();
        logMessage("rechargement a " + fmt(resumeAt));
        source = url;
    }

    function fail(reason) {
        if (failedOnce)
            return;
        failedOnce = true;
        failed(reason);
    }

    // Reprise apres rechargement : une seule fois, des que le flux est pret et navigable.
    function tryResume() {
        if (resumeAt > 0 && player.seekable
                && (player.status === MediaPlayer.Buffered || player.status === MediaPlayer.Loaded)) {
            const at = resumeAt;
            resumeAt = -1;
            player.seek(at);
            logMessage("reprise a " + fmt(at));
        }
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

    Timer {
        id: startWatchdog
        interval: page.startTimeoutMs
        running: page.source !== ""
        onTriggered: page.fail("pas de lecture apres " + Math.round(interval / 1000) + " s")
    }

    // Lecture reellement commencee : la position avance.
    Connections {
        target: player
        function onPositionChanged() {
            if (player.position > 0 && startWatchdog.running)
                startWatchdog.stop();
        }
    }

    MediaPlayer {
        id: player
        autoPlay: true
        source: page.source
        // Position mise a jour toutes les 200 ms (1 s par defaut) : sinon les sous-titres
        // apparaissent et disparaissent jusqu'a une seconde en retard. Affecte au demarrage
        // seulement si la propriete existe, pour ne pas casser le chargement de la page.
        Component.onCompleted: if ("notifyInterval" in player) player.notifyInterval = 200
        onStatusChanged: {
            page.logMessage("lecteur : " + page.statusName(status));
            if (status === MediaPlayer.EndOfMedia) {
                if (page.nextTitle && page.autoNext)
                    page.nextRequested();
                else
                    page.finished();
            }
            else if (status === MediaPlayer.InvalidMedia)
                page.fail("media invalide");
            page.tryResume();
        }
        onSeekableChanged: page.tryResume()
        onPlaybackStateChanged: page.logMessage("etat de lecture : " + ["arret", "lecture", "pause"][playbackState])
        onError: {
            page.logMessage("lecteur erreur " + error + " : " + errorString);
            page.fail(errorString || "erreur " + error);
        }
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
        text: page.cues.length ? Vtt.textAt(page.cues, player.position - page.subDelay) : ""
    }

    // ----- Affichage par-dessus la video -----
    Item {
        id: bar
        anchors.fill: parent
        visible: opacity > 0
        opacity: page.osd || menu.visible || player.playbackState === MediaPlayer.PausedState ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 120
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.75) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
            }
        }
        Text {
            id: clock
            anchors { right: parent.right; rightMargin: T.margin; top: parent.top; topMargin: 28 }
            color: T.text
            font.pixelSize: T.fontBody
            text: Qt.formatTime(new Date(), "hh:mm")
            Timer { interval: 20000; running: bar.visible; repeat: true; onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm") }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 210
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
            }
        }
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: T.margin; rightMargin: T.margin; bottomMargin: 36 }
            spacing: 12
            Text {
                width: parent.width
                text: page.title
                color: T.text
                font.pixelSize: T.fontHeading
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                visible: page.subtitleLine !== ""
                width: parent.width
                text: page.subtitleLine
                color: T.textMuted
                font.pixelSize: T.fontSmall
                elide: Text.ElideRight
            }
            // Barre de progression
            Item {
                width: parent.width
                height: 22
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.22)
                    Rectangle {
                        // Partie deja prechargee par le PC
                        visible: page.bufferedTo > 0
                        x: parent.width * page.bufferedFrom
                        width: parent.width * Math.max(0, page.bufferedTo - page.bufferedFrom)
                        height: parent.height
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.38)
                    }
                    Rectangle {
                        height: parent.height
                        radius: 3
                        width: player.duration > 0 ? parent.width * Math.min(1, player.position / player.duration) : 0
                        color: T.accent
                    }
                }
                Rectangle {
                    visible: player.duration > 0
                    x: (player.duration > 0 ? track.width * Math.min(1, player.position / player.duration) : 0) - width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 16
                    height: 16
                    radius: 8
                    color: T.text
                }
            }
            Item {
                width: parent.width
                height: 24
                Text {
                    text: page.fmt(player.position)
                    color: T.text
                    font.pixelSize: T.fontSmall
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: T.textMuted
                    font.pixelSize: T.fontSmall
                    text: player.playbackState === MediaPlayer.PausedState ? "❚❚  Pause  ·  OK pour reprendre"
                          : player.status === MediaPlayer.Stalled || player.status === MediaPlayer.Loading ? "Chargement…"
                          : "◀ -10 s   ·   OK pause   ·   +30 s ▶   ·   ▲ Audio et sous-titres   ·   4/6 synchro"
                }
                Text {
                    anchors.right: parent.right
                    text: player.duration > 0 ? "-" + page.fmt(player.duration - player.position) : "--:--"
                    color: T.text
                    font.pixelSize: T.fontSmall
                }
            }
        }
    }

    // Chargement : indicateur au centre
    Rectangle {
        anchors.centerIn: parent
        width: 72
        height: 72
        radius: 36
        color: Qt.rgba(0, 0, 0, 0.55)
        visible: !page.bufferVisible && page.source !== ""
                 && (player.status === MediaPlayer.Loading || player.status === MediaPlayer.Stalled
                     || (player.status === MediaPlayer.Buffering && player.position === 0))
        Rectangle {
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: 20
            color: "transparent"
            border.width: 4
            border.color: T.accent
            Rectangle {
                width: 12
                height: 12
                radius: 6
                color: T.text
                x: parent.width / 2 - 6
                y: -4
            }
            RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: parent.visible }
        }
    }

    // Prechargement : carte d'attente (avant la lecture, ou pause automatique si l'avance s'epuise)
    Rectangle {
        id: bufferCard
        visible: page.bufferVisible
        anchors.centerIn: parent
        width: 620
        height: bufferColumn.implicitHeight + 56
        radius: T.radius + 4
        color: Qt.rgba(0.07, 0.09, 0.13, 0.94)
        border.color: T.line
        Column {
            id: bufferColumn
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 14
            Text {
                text: page.bufferTitle
                color: T.text
                font.pixelSize: T.fontHeading
                font.bold: true
            }
            Rectangle {
                width: parent.width
                height: 10
                radius: 5
                color: Qt.rgba(1, 1, 1, 0.15)
                Rectangle {
                    width: parent.width * page.bufferPercent / 100
                    height: parent.height
                    radius: 5
                    color: T.accent
                    Behavior on width { NumberAnimation { duration: 400 } }
                }
            }
            Text {
                text: page.bufferPercent + " %" + (page.bufferEta ? "   ·   lecture dans " + page.bufferEta : "")
                color: T.text
                font.pixelSize: T.fontBody
            }
            Text {
                width: parent.width
                text: page.bufferDetail
                color: T.textMuted
                font.pixelSize: T.fontSmall
                wrapMode: Text.Wrap
            }
            Text {
                text: "OK : lancer maintenant   ·   Retour : quitter"
                color: T.accent
                font.pixelSize: T.fontSmall
            }
        }
    }

    // Episode suivant : carte avec compte a rebours sur les 20 dernieres secondes
    Rectangle {
        id: nextCard
        readonly property int remaining: player.duration > 0 ? Math.ceil((player.duration - player.position) / 1000) : 999
        visible: page.nextTitle !== "" && page.autoNext && remaining <= 20 && player.duration > 60000
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: T.margin; bottomMargin: 230 }
        width: 380
        height: 104
        radius: T.radius
        color: Qt.rgba(0.1, 0.13, 0.19, 0.95)
        border.color: T.accent
        border.width: 2
        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 6
            Text {
                text: "Episode suivant dans " + Math.max(0, nextCard.remaining) + " s"
                color: T.textMuted
                font.pixelSize: T.fontSmall
            }
            Text {
                width: parent.width
                text: page.nextTitle
                color: T.text
                font.pixelSize: T.fontBody
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: "▶ OK maintenant   ·   Retour : annuler"
                color: T.accent
                font.pixelSize: T.fontTiny + 1
            }
        }
    }

    // ----- Menu des pistes -----

    Rectangle {
        id: menu
        visible: false
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 40; bottomMargin: 40; rightMargin: T.margin }
        width: 780
        color: Qt.rgba(0.07, 0.09, 0.13, 0.96)
        radius: T.radius
        border.color: T.line

        function open() {
            visible = true;
            (page.audioTracks.length > 1 ? audioList : subList).forceActiveFocus();
            audioList.currentIndex = page.audioIndex;
            subList.currentIndex = page.subtitleIndex;
        }
        function close() {
            visible = false;
            // Rendre le focus a l'element des touches du lecteur : page.forceActiveFocus() le
            // redonnerait a la derniere liste du menu (FocusScope), invisible, qui capterait OK.
            keyTarget.forceActiveFocus();
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
            objectName: "menu audio"
            anchors { left: parent.left; leftMargin: 20; top: audioTitle.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 20 }
            width: 340
            clip: true
            model: page.audioTracks
            highlightMoveDuration: 0
            highlight: Rectangle { color: T.surfaceHigh; radius: T.radiusSmall; border.color: T.focus; border.width: 2; visible: audioList.activeFocus }
            delegate: Text {
                width: audioList.width
                height: 40
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: (index === page.audioIndex ? "✓  " : "     ") + modelData.label
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
        // Synchronisation : Gauche/Droite = -/+ 0,25 s ; OK = remise a zero ; Bas = liste.
        Rectangle {
            id: syncRow
            objectName: "synchro"
            anchors { left: subTitle.left; right: parent.right; rightMargin: 20; top: subTitle.bottom; topMargin: 10 }
            height: 56
            radius: T.radiusSmall
            color: activeFocus ? T.surfaceHigh : Qt.rgba(1, 1, 1, 0.05)
            border.color: activeFocus ? T.focus : "transparent"
            border.width: 2
            Text {
                anchors { left: parent.left; leftMargin: 12; top: parent.top; topMargin: 6 }
                text: "Synchronisation"
                color: T.textMuted
                font.pixelSize: T.fontTiny + 1
            }
            Text {
                anchors { left: parent.left; leftMargin: 12; bottom: parent.bottom; bottomMargin: 6 }
                text: (syncRow.activeFocus ? "◀  " : "") + page.delayText() + (syncRow.activeFocus ? "  ▶" : "")
                color: T.text
                font.pixelSize: T.fontSmall + 1
                font.bold: true
            }
            Keys.onLeftPressed: page.shiftSubtitles(-250)
            Keys.onRightPressed: page.shiftSubtitles(250)
            Keys.onReturnPressed: page.shiftSubtitles(0)
            Keys.onEnterPressed: page.shiftSubtitles(0)
            Keys.onDownPressed: subList.forceActiveFocus()
        }
        ListView {
            id: subList
            objectName: "menu sous-titres"
            anchors { left: subTitle.left; right: parent.right; rightMargin: 20; top: syncRow.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 20 }
            clip: true
            model: page.subtitleTracks
            highlightMoveDuration: 0
            highlight: Rectangle { color: T.surfaceHigh; radius: T.radiusSmall; border.color: T.focus; border.width: 2; visible: subList.activeFocus }
            delegate: Text {
                width: subList.width
                height: 40
                leftPadding: 10
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: (index === page.subtitleIndex ? "✓  " : "     ") + modelData.label
            }
            Keys.onLeftPressed: if (page.audioTracks.length) audioList.forceActiveFocus()
            Keys.onUpPressed: {
                if (currentIndex === 0)
                    syncRow.forceActiveFocus();
                else
                    decrementCurrentIndex();
            }
            Keys.onReturnPressed: {
                if (currentIndex !== page.subtitleIndex)
                    page.subtitleChosen(currentIndex);
                menu.close();
            }
        }

        Keys.onPressed: {
            // La touche Retour de la telecommande Freebox envoie Key_Backspace.
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Backspace || event.key === Qt.Key_Escape || event.key === Qt.Key_Menu) {
                event.accepted = true;
                menu.close();
            }
        }
    }

    Rectangle {
        id: delayHint
        function show() {
            opacity = 1;
            delayHideTimer.restart();
        }
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 60 }
        width: delayLabel.implicitWidth + 48
        height: 52
        radius: 26
        color: Qt.rgba(0.07, 0.09, 0.13, 0.92)
        border.color: T.accent
        opacity: 0
        visible: opacity > 0 && !menu.visible
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: delayLabel
            anchors.centerIn: parent
            text: "Sous-titres : " + page.delayText() + "   (4 / 6 · 5 : zero)"
            color: T.text
            font.pixelSize: T.fontSmall + 1
        }
        Timer {
            id: delayHideTimer
            interval: 2500
            onTriggered: delayHint.opacity = 0
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

    // Recoit les touches hors du menu ; les touches non traitees remontent au gestionnaire de la page.
    Item {
        id: keyTarget
        focus: true
    }

    focus: true
    Keys.onPressed: {
        logMessage("touche " + event.key + " (etat " + ["arret", "lecture", "pause"][player.playbackState] + ", position " + fmt(player.position) + ")");
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (page.bufferVisible) {
                page.skipBuffering();
                break;
            }
            if (nextCard.visible) {
                page.nextRequested();
                break;
            }
            if (player.playbackState === MediaPlayer.PlayingState)
                player.pause();
            else
                player.play();
            break;
        case Qt.Key_Back:
        case Qt.Key_Backspace:            // touche Retour de la telecommande Freebox
        case Qt.Key_Escape:
            if (nextCard.visible) {
                page.autoNext = false;
                break;
            }
            return;
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
            page.resumeAt = -1;
            // Duree encore inconnue (0) pendant le chargement : ne pas revenir au debut.
            if (player.duration > 0)
                player.seek(Math.min(player.position + 30000, player.duration));
            break;
        case Qt.Key_Left:
        case Qt.Key_MediaPrevious:
            page.resumeAt = -1;
            player.seek(Math.max(player.position - 10000, 0));
            break;
        case Qt.Key_Up:
        case Qt.Key_Menu:
            menu.open();
            break;
        case Qt.Key_4:
            page.shiftSubtitles(-250);
            event.accepted = true;
            return;
        case Qt.Key_6:
            page.shiftSubtitles(250);
            event.accepted = true;
            return;
        case Qt.Key_5:
            page.shiftSubtitles(0);
            event.accepted = true;
            return;
        default:
            return;
        }
        event.accepted = true;
        showOsd();
    }

    Component.onCompleted: {
        if (startAt > 0)
            resumeAt = startAt;
        showOsd();
    }
}
