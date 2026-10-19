import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons

// Accueil : grand bandeau du titre selectionne (fond, logo, resume) + rangees de catalogues.
FocusScope {
    id: page

    property alias model: rows.model
    property var loadCatalog: null       // function(ref) -> Promise de metas
    property var localRows: ({})         // { continue: [...], library: [...] }
    property string companion: ""
    property var progressOf: null
    property alias count: rows.count
    signal activated(var meta, string fallbackType)
    signal up()                          // Haut depuis la premiere rangee : barre du haut

    readonly property var heroMeta: rows.currentItem ? rows.currentItem.currentMeta : null

    function itemAt(i) {
        return rows.itemAtIndex(i);
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    // ----- Bandeau (fond en fondu enchaine) -----
    Item {
        id: hero
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 400

        property string shown: ""
        property bool useA: true

        function setBackground(url) {
            if (url === shown)
                return;
            shown = url;
            useA = !useA;
            (useA ? bgA : bgB).source = url;
        }

        Timer {
            // Petit delai : pas de rechargement d'image a chaque pas de la telecommande.
            id: heroDelay
            interval: 280
            onTriggered: {
                const m = page.heroMeta;
                hero.setBackground(m && m.background ? Addons.posterUrl(m.background) : "");
                heroInfo.meta = m;
            }
        }

        Image {
            id: bgA
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: parent.width * 0.78
            fillMode: Image.PreserveAspectCrop
            sourceSize { width: 1000; height: 560 }
            asynchronous: true
            opacity: hero.useA && status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 500 } }
        }
        Image {
            id: bgB
            anchors.fill: bgA
            fillMode: Image.PreserveAspectCrop
            sourceSize { width: 1000; height: 560 }
            asynchronous: true
            opacity: !hero.useA && status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 500 } }
        }
        // Degrades : lisibilite du texte a gauche, fondu vers les rangees en bas.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: T.bg }
                GradientStop { position: 0.38; color: T.bg }
                GradientStop { position: 0.62; color: Qt.rgba(0.04, 0.05, 0.07, 0.35) }
                GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.07, 0.15) }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 160
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.05, 0.07, 0) }
                GradientStop { position: 1.0; color: T.bg }
            }
        }

        Column {
            id: heroInfo
            property var meta: null
            x: T.margin
            y: 92
            width: parent.width * 0.42
            spacing: 12
            opacity: meta ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            Item {
                width: parent.width
                height: 86
                Image {
                    id: logo
                    anchors { left: parent.left; bottom: parent.bottom }
                    width: Math.min(parent.width, 380)
                    height: parent.height
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignLeft
                    sourceSize { width: 380; height: 86 }
                    asynchronous: true
                    source: heroInfo.meta && heroInfo.meta.logo ? Addons.posterUrl(heroInfo.meta.logo) : ""
                    visible: status === Image.Ready
                }
                Text {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    visible: !logo.visible
                    text: heroInfo.meta ? heroInfo.meta.name : ""
                    color: T.text
                    font.pixelSize: T.fontTitle
                    font.bold: true
                    elide: Text.ElideRight
                }
            }
            Row {
                spacing: 10
                Repeater {
                    model: heroInfo.meta ? [heroInfo.meta.releaseInfo, heroInfo.meta.imdbRating ? "★ " + heroInfo.meta.imdbRating : "",
                                            heroInfo.meta.type === "series" ? "Serie" : heroInfo.meta.type === "movie" ? "Film" : ""]
                                           .concat((heroInfo.meta.genres || []).slice(0, 2)).filter(function (s) { return s; }) : []
                    delegate: Rectangle {
                        height: 28
                        width: chip.implicitWidth + 22
                        radius: 14
                        color: index === 1 && String(modelData).charAt(0) === "★" ? "#3a3215" : Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: modelData
                            color: String(modelData).charAt(0) === "★" ? "#ffd166" : T.text
                            font.pixelSize: T.fontTiny + 1
                        }
                    }
                }
            }
            Text {
                width: parent.width
                text: heroInfo.meta ? (heroInfo.meta.description || "") : ""
                color: "#c9d1dc"
                font.pixelSize: T.fontSmall + 1
                lineHeight: 1.15
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }
    }

    // ----- Rangees -----
    ListView {
        id: rows
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 330; bottom: parent.bottom }
        focus: true
        clip: true
        spacing: 26
        cacheBuffer: 900
        highlightMoveDuration: T.anim + 80
        preferredHighlightBegin: 0
        preferredHighlightEnd: 10
        highlightRangeMode: ListView.StrictlyEnforceRange
        onCurrentIndexChanged: heroDelay.restart()

        delegate: PosterRow {
            id: row
            width: rows.width
            companion: page.companion
            progressOf: page.progressOf
            title: model.kind === "catalog" ? model.name + "  ·  " + model.addonName : model.name
            focus: ListView.isCurrentItem
            onActivated: page.activated(meta, model.type)
            onCurrentMetaChanged: if (ListView.isCurrentItem) heroDelay.restart()
            Component.onCompleted: {
                if (model.kind !== "catalog") {
                    row.metas = page.localRows[model.kind] || [];
                    if (ListView.isCurrentItem) heroDelay.restart();
                    return;
                }
                const ref = { transportUrl: model.transportUrl, type: model.type, id: model.cid, name: model.name };
                row.status = "chargement";
                page.loadCatalog(ref).then(metas => {
                    row.metas = metas;
                    row.status = metas.length ? "" : "vide";
                    if (row.ListView.isCurrentItem)
                        heroDelay.restart();
                }).catch(e => {
                    row.status = "indisponible";
                });
            }
        }

        Keys.onUpPressed: {
            if (currentIndex === 0)
                page.up();
            else
                decrementCurrentIndex();
        }
    }
}
