import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons

// Une rangee de l'accueil en grille (plusieurs lignes) : « Tout voir ». Les pages suivantes du
// catalogue sont chargees en descendant (extra « skip »), quand l'addon le permet.
FocusScope {
    id: page

    property string title: ""
    property var metas: []
    property string status: ""           // "", "chargement", "fin", "erreur"
    property var progressOf: null
    signal activated(var meta)
    signal moreWanted()

    readonly property int columns: 6

    function reset(newTitle) {
        title = newTitle;
        metas = [];
        status = "chargement";
        grid.currentIndex = 0;
        grid.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    Text {
        id: heading
        x: T.margin
        y: 36
        width: parent.width - 2 * T.margin
        text: page.title
        color: T.text
        font.pixelSize: T.fontHeading
        font.bold: true
        elide: Text.ElideRight
    }
    Text {
        anchors { left: heading.left; top: heading.bottom; topMargin: 4 }
        text: (page.metas.length ? page.metas.length + " titres" : "")
              + (page.status === "chargement" ? (page.metas.length ? "  ·  " : "") + "chargement…" : "")
              + "   ·   Retour : accueil"
        color: T.textDim
        font.pixelSize: T.fontSmall
    }

    GridView {
        id: grid
        objectName: "grille"
        anchors { top: heading.bottom; topMargin: 44; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        width: page.columns * cellWidth
        cellWidth: T.posterW + 24
        cellHeight: T.posterH + 64
        focus: true
        clip: true
        model: page.metas
        cacheBuffer: 600
        highlightMoveDuration: T.anim
        preferredHighlightBegin: 0
        preferredHighlightEnd: cellHeight
        highlightRangeMode: GridView.ApplyRange
        keyNavigationEnabled: true
        onCurrentIndexChanged: {
            // Avant-derniere ligne atteinte : page suivante.
            if (count && currentIndex >= count - 2 * page.columns && page.status === "")
                page.moreWanted();
        }

        delegate: Item {
            id: cell
            width: grid.cellWidth
            height: grid.cellHeight
            readonly property bool current: GridView.isCurrentItem && grid.activeFocus
            readonly property real progress: page.progressOf ? page.progressOf(modelData) : (modelData.progress || 0)
            z: current ? 2 : 1

            Rectangle {
                id: card
                x: 12
                y: 6
                width: T.posterW
                height: T.posterH
                radius: T.radius
                color: T.surface
                clip: true
                scale: cell.current ? 1.06 : 1.0
                Behavior on scale { NumberAnimation { duration: T.anim } }
                border.width: cell.current ? 3 : 0
                border.color: T.focus

                Text {
                    anchors { fill: parent; margins: 12 }
                    visible: poster.status !== Image.Ready
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    color: T.textMuted
                    wrapMode: Text.Wrap
                    font.pixelSize: T.fontSmall
                    text: modelData.name || ""
                }
                Image {
                    id: poster
                    anchors { fill: parent; margins: cell.current ? 3 : 0 }
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize { width: T.posterW; height: T.posterH }
                    source: Addons.posterUrl(modelData.poster)
                    opacity: status === Image.Ready ? 1 : 0
                }
                Rectangle {
                    visible: cell.progress > 0
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 6
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.min(1, cell.progress)
                        color: cell.progress >= 1 ? T.ok : T.accent
                    }
                }
            }
            Text {
                anchors { top: card.bottom; topMargin: 8; left: card.left; right: card.right }
                color: cell.current ? T.text : T.textMuted
                elide: Text.ElideRight
                font.pixelSize: T.fontSmall
                text: modelData.name || ""
            }
        }

        Keys.onReturnPressed: if (count) page.activated(page.metas[currentIndex])
        Keys.onEnterPressed: if (count) page.activated(page.metas[currentIndex])
    }

    Text {
        anchors.centerIn: parent
        visible: !page.metas.length && page.status !== "chargement"
        text: page.status === "erreur" ? "Catalogue indisponible" : "Aucun titre"
        color: T.textMuted
        font.pixelSize: T.fontBody
    }
}
