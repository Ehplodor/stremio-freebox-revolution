import QtQuick 2.15
import "../js/theme.js" as T

// Recherche : clavier a l'ecran (telecommande) a gauche, resultats (films, series) a droite.
// Les resultats arrivent pendant la saisie (apres une courte pause).
FocusScope {
    id: page

    property string query: ""
    property var results: []             // [{ title, metas }]
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
        Text {
            anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
            text: "⌕"
            color: T.textMuted
            font.pixelSize: 26
        }
        Text {
            anchors { left: parent.left; leftMargin: 58; right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            text: page.query ? page.query + "▏" : "Titre, acteur…"
            color: page.query ? T.text : T.textDim
            font.pixelSize: T.fontBody + 2
            elide: Text.ElideLeft
        }
    }

    GridView {
        id: keyboard
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
                Text {
                    anchors.centerIn: parent
                    text: modelData === "ESPACE" ? "␣" : modelData === "EFFACER" ? "✕" : modelData
                    color: parent.focused ? T.bg : T.text
                    font.pixelSize: T.fontBody
                    font.bold: true
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
        text: "OK : taper · ⌫ : effacer · → : resultats"
        color: T.textDim
        font.pixelSize: T.fontTiny
    }

    // ----- Resultats -----
    Text {
        id: header
        anchors { left: field.right; leftMargin: 40; top: parent.top; topMargin: 104 }
        text: page.status || (page.results.length ? "Resultats pour « " + page.query.trim() + " »" : "Tapez au moins 2 lettres")
        color: T.textMuted
        font.pixelSize: T.fontBody
    }

    ListView {
        id: resultsView
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
