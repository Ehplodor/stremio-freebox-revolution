import QtQuick 2.15
import "../js/core/addons.js" as Addons

// Une rangee de l'accueil : titre du catalogue + affiches defilant horizontalement.
FocusScope {
    id: row

    property string title: ""
    property var metas: []
    property string status: ""          // "", "chargement", ou message d'erreur
    property int loadedImages: 0
    property int failedImages: 0
    property string companion: ""       // service compagnon, pour convertir les affiches WebP
    signal activated(var meta)

    height: 330

    Text {
        id: label
        x: 40
        color: row.activeFocus ? "white" : "#9aa7b4"
        font.pixelSize: 24
        font.bold: row.activeFocus
        text: row.title + (row.status ? "  (" + row.status + ")" : "")
    }

    ListView {
        id: list
        anchors { top: label.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom }
        orientation: ListView.Horizontal
        leftMargin: 40
        rightMargin: 40
        spacing: 16
        focus: true
        clip: true
        model: row.metas
        cacheBuffer: 400
        highlightMoveDuration: 120
        preferredHighlightBegin: 40
        preferredHighlightEnd: width - 240
        highlightRangeMode: ListView.ApplyRange

        delegate: Item {
            width: 180
            height: list.height
            property bool current: ListView.isCurrentItem && row.activeFocus

            Rectangle {
                id: frame
                width: 180
                height: 270
                color: "#1d2733"
                border.width: parent.current ? 4 : 0
                border.color: "#f5f5f5"
                scale: parent.current ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 100 } }

                Image {
                    property bool retried: false
                    anchors { fill: parent; margins: frame.border.width }
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    // Petites affiches : peu de memoire sur le Player.
                    sourceSize { width: 180; height: 270 }
                    source: Addons.posterUrl(modelData.poster)
                    onStatusChanged: {
                        if (status === Image.Ready) {
                            row.loadedImages++;
                        } else if (status === Image.Error && !retried && row.companion) {
                            retried = true;
                            source = Addons.posterFallback(modelData.poster, row.companion);
                        } else if (status === Image.Error) {
                            row.failedImages++;
                        }
                    }
                }
                Text {
                    anchors { fill: parent; margins: 10 }
                    visible: !modelData.poster
                    color: "white"
                    wrapMode: Text.Wrap
                    font.pixelSize: 18
                    text: modelData.name
                }
            }
            Text {
                anchors { top: frame.bottom; topMargin: 8; left: frame.left; right: frame.right }
                color: parent.current ? "white" : "#9aa7b4"
                elide: Text.ElideRight
                font.pixelSize: 16
                text: modelData.name
            }
        }

        Keys.onReturnPressed: if (count) row.activated(row.metas[currentIndex])
        Keys.onEnterPressed: if (count) row.activated(row.metas[currentIndex])
    }
}
