import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons

// Une rangee de l'accueil : titre + affiches defilant horizontalement.
FocusScope {
    id: row

    property string title: ""
    property var metas: []
    property string status: ""          // "", "chargement", "vide", "erreur"
    property int loadedImages: 0
    property int failedImages: 0
    property string companion: ""       // agent du PC, pour convertir les affiches WebP
    property var progressOf: null       // function(meta) -> 0..1 (barre de progression)
    readonly property var currentMeta: list.currentIndex >= 0 && list.currentIndex < metas.length ? metas[list.currentIndex] : null
    signal activated(var meta)

    height: T.posterH + 78

    Row {
        id: header
        x: T.margin
        spacing: 12
        Text {
            text: row.title
            color: row.activeFocus ? T.text : T.textMuted
            font.pixelSize: T.fontBody + 2
            font.bold: true
            Behavior on color { ColorAnimation { duration: T.anim } }
        }
        Text {
            visible: row.status !== ""
            text: row.status === "chargement" ? "chargement…" : row.status
            color: T.textDim
            font.pixelSize: T.fontSmall
        }
    }

    ListView {
        id: list
        objectName: "affiches"
        anchors { top: header.bottom; topMargin: 12; left: parent.left; right: parent.right; bottom: parent.bottom }
        orientation: ListView.Horizontal
        leftMargin: T.margin
        rightMargin: T.margin
        spacing: 18
        focus: true
        model: row.metas
        cacheBuffer: 600
        highlightMoveDuration: T.anim
        preferredHighlightBegin: T.margin
        preferredHighlightEnd: width - T.margin - T.posterW
        highlightRangeMode: ListView.ApplyRange

        // Squelettes pendant le chargement.
        Row {
            visible: row.status === "chargement" && list.count === 0
            x: T.margin
            spacing: 18
            Repeater {
                model: 7
                Rectangle {
                    width: T.posterW
                    height: T.posterH
                    radius: T.radius
                    color: T.surface
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: parent.visible
                        NumberAnimation { from: 0.45; to: 0.9; duration: 700 }
                        NumberAnimation { from: 0.9; to: 0.45; duration: 700 }
                    }
                }
            }
        }

        delegate: Item {
            id: cell
            width: T.posterW
            height: list.height
            readonly property bool current: ListView.isCurrentItem && row.activeFocus
            readonly property real progress: row.progressOf ? row.progressOf(modelData) : (modelData.progress || 0)
            z: current ? 2 : 1

            Item {
                id: card
                width: T.posterW
                height: T.posterH
                scale: cell.current ? 1.08 : 1.0
                transformOrigin: Item.Bottom
                Behavior on scale { NumberAnimation { duration: T.anim; easing.type: Easing.OutCubic } }

                // Halo du focus
                Rectangle {
                    anchors { fill: parent; margins: -5 }
                    radius: T.radius + 4
                    color: "transparent"
                    border.width: 3
                    border.color: T.focus
                    opacity: cell.current ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: T.anim } }
                }

                Rectangle {
                    id: frame
                    anchors.fill: parent
                    radius: T.radius
                    color: T.surface
                    clip: true

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
                        property bool retried: false
                        anchors.fill: parent
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        // Petites affiches : peu de memoire sur le Player.
                        sourceSize { width: T.posterW; height: T.posterH }
                        source: Addons.posterUrl(modelData.poster)
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        onStatusChanged: {
                            if (status === Image.Ready) {
                                row.loadedImages++;
                            } else if (status === Image.Error && !retried && row.companion && modelData.poster) {
                                retried = true;
                                source = Addons.posterFallback(modelData.poster, row.companion);
                            } else if (status === Image.Error) {
                                row.failedImages++;
                            }
                        }
                    }

                    // Barre de progression (reprise de lecture)
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
            }

            Text {
                anchors { top: card.bottom; topMargin: 10; left: card.left; right: card.right }
                color: cell.current ? T.text : T.textMuted
                elide: Text.ElideRight
                font.pixelSize: T.fontSmall
                text: modelData.name || ""
                opacity: cell.current ? 1 : 0.8
            }
        }

        Keys.onReturnPressed: if (count) row.activated(row.metas[currentIndex])
        Keys.onEnterPressed: if (count) row.activated(row.metas[currentIndex])
    }
}
