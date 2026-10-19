import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/sorting.js" as Sorting

// Reglages du tri des flux. Haut/Bas : choisir une ligne ; Gauche/Droite : changer la valeur
// (sur un critere : le faire monter ou descendre) ; OK : basculer ; Retour : revenir a la fiche.
FocusScope {
    id: page

    property var prefs: Sorting.normalize(null)
    signal changed(var prefs)

    readonly property var rows: Sorting.settingsRows(prefs)

    function apply(key, step) {
        const before = list.currentIndex;
        prefs = Sorting.edit(prefs, key, step);
        changed(prefs);
        // Un critere deplace : la selection le suit.
        if (key.indexOf("order:") === 0 && step)
            list.currentIndex = Math.max(0, Math.min(prefs.order.length - 1, before + step));
        else
            list.currentIndex = before;
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    Text {
        id: header
        x: 60
        y: 40
        color: T.text
        font.pixelSize: 36
        font.bold: true
        text: "Tri des sources"
    }
    Text {
        anchors { left: header.left; top: header.bottom; topMargin: 8 }
        color: T.textMuted
        font.pixelSize: 18
        text: "Gauche/Droite : changer (sur un critere : le monter ou le descendre) · OK : basculer · Retour : fermer. Enregistre automatiquement."
    }

    ListView {
        id: list
        anchors { left: parent.left; right: parent.right; top: header.bottom; topMargin: 50; bottom: parent.bottom; margins: 60 }
        focus: true
        clip: true
        model: page.rows
        spacing: 4
        highlightMoveDuration: 0
        highlight: Rectangle { color: T.surfaceHigh; radius: T.radiusSmall; border.color: T.focus; border.width: 2 }
        delegate: Item {
            width: list.width
            height: 46
            readonly property bool separator: index > 0 && modelData.key.indexOf("order:") !== 0
                                              && page.rows[index - 1].key.indexOf("order:") === 0
            Rectangle {
                visible: parent.separator
                width: parent.width
                height: 1
                color: T.line
                anchors.top: parent.top
            }
            Text {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                color: T.textMuted
                font.pixelSize: 20
                text: modelData.label
            }
            Text {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                color: T.text
                font.pixelSize: 20
                font.bold: true
                text: modelData.value ? "◀  " + modelData.value + "  ▶" : ""
            }
        }
        Keys.onLeftPressed: page.apply(page.rows[currentIndex].key, -1)
        Keys.onRightPressed: page.apply(page.rows[currentIndex].key, 1)
        Keys.onReturnPressed: page.apply(page.rows[currentIndex].key, 0)
        Keys.onEnterPressed: page.apply(page.rows[currentIndex].key, 0)
    }
}
