import QtQuick 2.15

// Fiche d'un film ou d'une serie. Pour une serie : liste des episodes a gauche,
// flux de l'episode choisi a droite. Pour un film : flux directement.
FocusScope {
    id: page

    property var meta: null
    property var episodes: []        // [{ id, title, season, episode }] (series)
    property var streams: []         // [{ addon, stream }]
    property string streamsStatus: ""
    signal episodeChosen(var video)
    signal streamChosen(var item)

    readonly property bool isSeries: episodes.length > 0

    function focusStreams() {
        streamList.forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: "#0e1318"
    }

    Image {
        anchors.fill: parent
        source: page.meta && page.meta.background ? page.meta.background : ""
        sourceSize { width: 1280; height: 720 }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.25
    }

    Column {
        id: header
        x: 60
        y: 40
        width: parent.width - 120
        spacing: 10

        Text {
            color: "white"
            font.pixelSize: 40
            font.bold: true
            text: page.meta ? page.meta.name : ""
        }
        Text {
            color: "#9aa7b4"
            font.pixelSize: 20
            text: page.meta ? [page.meta.releaseInfo, (page.meta.genres || []).slice(0, 3).join(", "),
                               page.meta.imdbRating ? "IMDb " + page.meta.imdbRating : ""]
                              .filter(function (s) { return s; }).join("  ·  ") : ""
        }
        Text {
            width: parent.width
            color: "#d8dee4"
            font.pixelSize: 18
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            text: page.meta ? (page.meta.description || "") : ""
        }
    }

    ListView {
        id: episodeList
        visible: page.isSeries
        anchors { left: parent.left; leftMargin: 60; top: header.bottom; topMargin: 30; bottom: parent.bottom; bottomMargin: 30 }
        width: page.isSeries ? 520 : 0
        clip: true
        focus: page.isSeries
        model: page.episodes
        highlightMoveDuration: 0
        highlight: Rectangle { color: "#2a6fdb"; radius: 4; visible: episodeList.activeFocus }
        delegate: Text {
            width: episodeList.width
            height: 36
            leftPadding: 10
            verticalAlignment: Text.AlignVCenter
            color: "white"
            font.pixelSize: 18
            elide: Text.ElideRight
            text: "S" + modelData.season + "E" + (modelData.episode || modelData.number) + "  " + (modelData.title || modelData.name || "")
        }
        Keys.onReturnPressed: page.episodeChosen(page.episodes[currentIndex])
        Keys.onRightPressed: streamList.forceActiveFocus()
    }

    Text {
        id: streamsTitle
        anchors { left: episodeList.right; leftMargin: page.isSeries ? 40 : 0; top: header.bottom; topMargin: 30 }
        color: "#9aa7b4"
        font.pixelSize: 20
        text: "Flux" + (page.streamsStatus ? " : " + page.streamsStatus : "") + "   ·   Menu : tri des sources"
    }

    ListView {
        id: streamList
        anchors { left: streamsTitle.left; right: parent.right; rightMargin: 60; top: streamsTitle.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: 30 }
        clip: true
        focus: !page.isSeries
        model: page.streams
        spacing: 6
        highlightMoveDuration: 0
        highlight: Rectangle { color: "#2a6fdb"; radius: 4; visible: streamList.activeFocus }
        delegate: Column {
            width: streamList.width
            leftPadding: 10
            Text {
                width: parent.width - 20
                color: "white"
                font.pixelSize: 18
                elide: Text.ElideRight
                text: (modelData.badges || "") + (modelData.badges ? "   " : "") + modelData.addon
            }
            Text {
                width: parent.width - 20
                color: "#c8d0d8"
                font.pixelSize: 15
                elide: Text.ElideRight
                text: (modelData.stream.title || modelData.stream.description || modelData.stream.name || "").split("\n")[0]
            }
        }
        Keys.onReturnPressed: if (count) page.streamChosen(page.streams[currentIndex])
        Keys.onLeftPressed: if (page.isSeries) episodeList.forceActiveFocus()
    }
}
