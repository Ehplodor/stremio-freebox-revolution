import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons

// Grille d'affiches (Tout voir, Decouvrir). moreWanted : avant-derniere ligne atteinte.
GridView {
    id: grid
    property var metas: []
    property var progressOf: null
    property int columns: 6
    property bool canLoadMore: false
    signal activated(var meta)
    signal moreWanted()
    signal upFromTop()

    width: columns * cellWidth
    cellWidth: T.posterW + 24
    cellHeight: T.posterH + 64
    clip: true
    model: []
    cacheBuffer: 600
    highlightMoveDuration: T.anim
    preferredHighlightBegin: 0
    preferredHighlightEnd: cellHeight
    highlightRangeMode: GridView.ApplyRange
    keyNavigationEnabled: true
    // Suite chargee (meme debut de liste) : la selection reste ou elle etait, au lieu de revenir
    // au premier titre.
    onMetasChanged: {
        const old = model || [];
        const list = metas || [];
        const keep = old.length && list.length >= old.length && list[0].id === old[0].id ? currentIndex : -1;
        model = list;
        if (keep > 0 && count) {
            currentIndex = Math.min(keep, count - 1);
            positionViewAtIndex(currentIndex, GridView.Contain);
        }
    }
    onCurrentIndexChanged: {
        if (count && currentIndex >= count - 2 * columns && canLoadMore)
            moreWanted();
    }

    delegate: Item {
        id: cell
        width: grid.cellWidth
        height: grid.cellHeight
        readonly property bool current: GridView.isCurrentItem && grid.activeFocus
        readonly property real progress: grid.progressOf ? grid.progressOf(modelData) : (modelData.progress || 0)
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

    Keys.onReturnPressed: if (count) grid.activated(grid.metas[currentIndex])
    Keys.onEnterPressed: if (count) grid.activated(grid.metas[currentIndex])
    Keys.onUpPressed: {
        if (currentIndex < columns)
            upFromTop();
        else
            moveCurrentIndexUp();
    }
}
