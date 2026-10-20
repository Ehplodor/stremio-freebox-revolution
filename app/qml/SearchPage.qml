import QtQuick 2.15
import "../js/theme.js" as T

// Recherche : clavier a l'ecran (telecommande) a gauche, resultats (films, series) a droite.
// Les resultats arrivent pendant la saisie (apres une courte pause).
FocusScope {
    id: page

    property string query: ""
    property var results: []             // [{ title, metas }]
    readonly property bool resultsFocused: resultsView.activeFocus
    property string status: ""
    property string companion: ""
    property var progressOf: null
    signal search(string text)
    signal activated(var meta)
    signal up()

    readonly property var keys: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".split("").concat(["ESPACE", "⌫", "EFFACER"])

    function type(k) {
        if (k === "⌫")
            query = query.slice(0, -1);
        else if (k === "EFFACER")
            query = "";
        else if (k === "ESPACE")
            query = query + " ";
        else if (query.length < 40)
            query = query + k.toLowerCase();
        debounce.restart();
    }

    function focusKeyboard() {
        keyboard.forceActiveFocus();
    }

    Timer {
        id: debounce
        interval: 700
        onTriggered: if (page.query.trim().length >= 2) page.search(page.query.trim())
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    // ----- Saisie -----
    Rectangle {
        id: field
        x: T.margin
        y: 96
        width: 420
        height: 60
        radius: 30
        color: T.surface
        border.color: keyboard.activeFocus ? T.accent : T.line
        border.width: 2
        Canvas {
            // Loupe dessinee (le caractere ⌕ manque a la police du Player)
            anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
            width: 24
            height: 24
            onPaint: {
                const c = getContext("2d");
                c.reset();
                c.strokeStyle = T.textMuted;
                c.lineWidth = 2.5;
                c.beginPath();
                c.arc(10, 10, 7, 0, 2 * Math.PI);
                c.moveTo(15, 15);
                c.lineTo(22, 22);
                c.stroke();
            }
        }
        Text {
            anchors { left: parent.left; leftMargin: 58; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: page.query ? page.query + "|" : "Titre, acteur…"
            color: page.query ? T.text : T.textDim
            font.pixelSize: T.fontBody + 2
            elide: Text.ElideLeft
        }
    }

    GridView {
        id: keyboard
        objectName: "clavier"
        anchors { left: field.left; top: field.bottom; topMargin: 24 }
        width: 420
        height: 7 * 60
        cellWidth: 70
        cellHeight: 60
        focus: true
        interactive: false
        keyNavigationEnabled: true   // sinon les fleches sont desactivees avec interactive: false (Qt >= 5.7)
        model: page.keys
        highlightMoveDuration: 0
        delegate: Item {
            readonly property bool wide: modelData.length > 1 && modelData !== "⌫"
            width: keyboard.cellWidth
            height: keyboard.cellHeight
            Rectangle {
                anchors { fill: parent; margins: 5 }
                radius: T.radiusSmall
                readonly property bool focused: keyboard.activeFocus && keyboard.currentIndex === index
                color: focused ? T.text : T.surface
                Behavior on color { ColorAnimation { duration: 90 } }
                // Espace et retour arriere dessines : les caracteres ␣ et ⌫ manquent a la police du Player.
                Text {
                    anchors.centerIn: parent
                    visible: modelData !== "ESPACE" && modelData !== "⌫"
                    text: modelData === "EFFACER" ? "✕" : modelData
                    color: parent.focused ? T.bg : T.text
                    font.pixelSize: T.fontBody
                    font.bold: true
                }
                Item {
                    // Espace : crochet ouvert vers le haut
                    visible: modelData === "ESPACE"
                    anchors.centerIn: parent
                    width: 26
                    height: 10
                    readonly property color ink: parent.focused ? T.bg : T.text
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 3; color: parent.ink }
                    Rectangle { anchors { left: parent.left; top: parent.top; bottom: parent.bottom } width: 3; color: parent.ink }
                    Rectangle { anchors { right: parent.right; top: parent.top; bottom: parent.bottom } width: 3; color: parent.ink }
                }
                Canvas {
                    // Retour arriere : etiquette pointant a gauche, avec une croix
                    id: backspaceIcon
                    visible: modelData === "⌫"
                    anchors.centerIn: parent
                    width: 30
                    height: 20
                    readonly property color ink: parent.focused ? T.bg : T.text
                    onInkChanged: requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        c.strokeStyle = ink;
                        c.lineWidth = 2.5;
                        c.lineJoin = "round";
                        c.beginPath();
                        c.moveTo(2, 10); c.lineTo(10, 2); c.lineTo(28, 2); c.lineTo(28, 18); c.lineTo(10, 18); c.closePath();
                        c.stroke();
                        c.beginPath();
                        c.moveTo(15, 6); c.lineTo(23, 14); c.moveTo(23, 6); c.lineTo(15, 14);
                        c.stroke();
                    }
                }
            }
        }
        Keys.onReturnPressed: page.type(page.keys[currentIndex])
        Keys.onEnterPressed: page.type(page.keys[currentIndex])
        Keys.onRightPressed: {
            if ((currentIndex + 1) % 6 === 0 || currentIndex === count - 1) {
                if (resultsView.count)
                    resultsView.forceActiveFocus();
            } else {
                moveCurrentIndexRight();
            }
        }
        Keys.onUpPressed: {
            if (currentIndex < 6)
                page.up();
            else
                moveCurrentIndexUp();
        }
        // Chiffres de la telecommande : saisie directe
        Keys.onPressed: {
            if (event.key >= Qt.Key_0 && event.key <= Qt.Key_9) {
                page.type(String(event.key - Qt.Key_0));
                event.accepted = true;
            }
        }
    }

    Text {
        anchors { left: field.left; top: keyboard.bottom; topMargin: 6 }
        width: 420
        text: "OK : taper · chiffres : saisie directe · → : résultats"
        color: T.textDim
        font.pixelSize: T.fontTiny
    }

    // ----- Resultats -----
    Text {
        id: header
        anchors { left: field.right; leftMargin: 40; top: parent.top; topMargin: 104 }
        text: page.status || (page.results.length ? "Résultats pour « " + page.query.trim() + " »" : "Tapez au moins 2 lettres")
        color: T.textMuted
        font.pixelSize: T.fontBody
    }

    ListView {
        id: resultsView
        objectName: "resultats"
        anchors { left: field.right; leftMargin: -T.margin + 40; right: parent.right; top: header.bottom; topMargin: 14; bottom: parent.bottom }
        clip: true
        spacing: 18
        model: page.results
        highlightMoveDuration: T.anim
        delegate: PosterRow {
            width: resultsView.width
            title: modelData.title
            metas: modelData.metas
            companion: page.companion
            progressOf: page.progressOf
            focus: ListView.isCurrentItem
            onActivated: page.activated(meta)
        }
        Keys.onLeftPressed: keyboard.forceActiveFocus()
    }
}
