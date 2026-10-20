import QtQuick 2.15
import "../js/theme.js" as T

// Reglages : PC connecte, compte, lecture, tri, diagnostic.
// Chaque ligne : { key, section, label, value, action } ; Gauche/Droite ou OK selon la ligne.
FocusScope {
    id: page

    property var rows: []
    signal activated(string key, int step)
    signal up()

    // Nouvelles valeurs sans perdre la ligne selectionnee.
    function setRows(list) {
        const i = list_.currentIndex;
        rows = list;
        list_.currentIndex = Math.min(Math.max(i, 0), list.length - 1);
    }

    function focusList() {
        list_.forceActiveFocus();
    }

    property alias list_: list

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    Text {
        id: title
        x: T.margin
        y: 92
        text: "Réglages"
        color: T.text
        font.pixelSize: T.fontTitle
        font.bold: true
    }

    ListView {
        id: list
        objectName: "lignes"
        anchors { left: parent.left; right: parent.right; top: title.bottom; topMargin: 20; bottom: parent.bottom; bottomMargin: 30 }
        leftMargin: 0
        focus: true
        clip: true
        model: page.rows
        highlightMoveDuration: T.anim
        preferredHighlightBegin: 120
        preferredHighlightEnd: height - 120
        highlightRangeMode: ListView.ApplyRange
        delegate: Item {
            readonly property bool focused: list.activeFocus && ListView.isCurrentItem
            // Titre de section au-dessus de la premiere ligne de chaque section.
            readonly property bool firstOfSection: index === 0 || page.rows[index - 1].section !== modelData.section
            width: list.width
            height: 58 + (firstOfSection ? 50 : 0)
            Text {
                visible: parent.firstOfSection
                x: T.margin
                y: 18
                text: modelData.section || ""
                color: T.accent
                font.pixelSize: T.fontSmall
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.5
            }
            Item {
                id: rowArea
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 58
            Rectangle {
                anchors { fill: parent; leftMargin: T.margin - 16; rightMargin: T.margin - 16; topMargin: 3; bottomMargin: 3 }
                radius: T.radiusSmall
                color: rowArea.parent.focused ? T.surfaceHigh : "transparent"
                border.color: rowArea.parent.focused ? T.focus : "transparent"
                border.width: 2
            }
            Text {
                x: T.margin
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.45
                text: modelData.label
                color: modelData.action === "info" ? T.textMuted : T.text
                font.pixelSize: T.fontBody
                elide: Text.ElideRight
            }
            Text {
                anchors { right: parent.right; rightMargin: T.margin; verticalCenter: parent.verticalCenter }
                width: parent.width * 0.45
                horizontalAlignment: Text.AlignRight
                text: modelData.action === "choice" ? "◀  " + modelData.value + "  ▶"
                      : modelData.action === "button" ? modelData.value + "  ›"
                      : modelData.value
                color: modelData.action === "button" ? T.accent : modelData.tone === "ok" ? T.ok
                       : modelData.tone === "bad" ? T.danger : T.textMuted
                font.pixelSize: T.fontBody
                font.bold: modelData.action !== "info"
                elide: Text.ElideRight
            }
            }
        }
        Keys.onLeftPressed: if (page.rows[currentIndex].action === "choice") page.activated(page.rows[currentIndex].key, -1)
        Keys.onRightPressed: if (page.rows[currentIndex].action === "choice") page.activated(page.rows[currentIndex].key, 1)
        Keys.onReturnPressed: if (page.rows[currentIndex].action !== "info") page.activated(page.rows[currentIndex].key, 0)
        Keys.onEnterPressed: if (page.rows[currentIndex].action !== "info") page.activated(page.rows[currentIndex].key, 0)
        Keys.onUpPressed: {
            if (currentIndex === 0)
                page.up();
            else
                decrementCurrentIndex();
        }
    }
}
