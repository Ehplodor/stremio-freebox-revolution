import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons

// Fiche d'un film ou d'une serie.
// Haut : fond, titre, informations, boutons (Lecture / Sources / Tri).
// Bas : episodes (serie) ou liste des sources (bouton Sources).
FocusScope {
    id: page

    property var meta: null
    property var episodes: []        // [{ id, title, season, episode, thumbnail }] (series)
    property var streams: []         // [{ addon, stream, badges }]
    property string streamsStatus: ""
    property string selectedTitle: ""     // episode choisi (series)
    property string resumeText: ""        // "Reprendre à 12:34" si une position existe
    property bool showingSources: false
    property var progressOf: null         // function(videoId) -> 0..1
    signal episodeChosen(var video)
    signal streamChosen(var item)
    signal playBest()
    signal sortRequested()

    readonly property bool isSeries: episodes.length > 0
    readonly property var seasons: {
        const out = [];
        episodes.forEach(e => { if (out.indexOf(e.season) === -1) out.push(e.season); });
        return out;
    }
    property int seasonIndex: 0
    readonly property var seasonEpisodes: episodes.filter(e => e.season === seasons[seasonIndex])

    function reset() {
        showingSources = false;
        seasonIndex = 0;
        selectedTitle = "";
        resumeText = "";
        actions.currentIndex = 0;
        actions.forceActiveFocus();
    }

    // Saison et episode affiches sur la video donnee (reprise de la serie).
    function showEpisode(videoId) {
        const v = episodes.find(e => e.id === videoId);
        if (!v)
            return;
        seasonIndex = Math.max(0, seasons.indexOf(v.season));
        seasonTabs.currentIndex = seasonIndex;
        const i = seasonEpisodes.findIndex(e => e.id === videoId);
        episodeList.currentIndex = Math.max(0, i);
        episodeList.positionViewAtIndex(episodeList.currentIndex, ListView.Center);
    }

    function focusStreams() {
        // Appele quand les premiers flux arrivent : on reste sur les boutons (Lecture pret).
        if (!showingSources && !episodeList.activeFocus && !seasonTabs.activeFocus)
            actions.forceActiveFocus();
    }

    function openSources() {
        showingSources = true;
        streamList.forceActiveFocus();
    }

    // Retour : sources -> boutons ; renvoie false s'il faut quitter la fiche.
    function back() {
        if (showingSources) {
            showingSources = false;
            (isSeries ? episodeList : actions).forceActiveFocus();
            return true;
        }
        return false;
    }

    // Nouvelle liste (un addon de plus a repondu, ou tri modifie) : si l'utilisateur est descendu
    // dans la liste, la selection reste sur le meme flux au lieu de revenir en tete, pour que OK
    // lance bien celui qui etait choisi. Tant qu'il est en tete, il y reste (meilleur flux).
    function setStreams(list) {
        const selected = streamList.currentIndex > 0 ? streams[streamList.currentIndex] : null;
        streams = list;
        const i = selected ? list.findIndex(x => x.stream === selected.stream) : -1;
        streamList.currentIndex = i === -1 ? 0 : i;
        streamList.positionViewAtIndex(streamList.currentIndex, ListView.Contain);
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    // ----- Fond -----
    Image {
        id: backdrop
        anchors { right: parent.right; top: parent.top }
        width: parent.width * 0.8
        height: parent.height * 0.78
        source: page.meta && page.meta.background ? Addons.posterUrl(page.meta.background) : ""
        sourceSize { width: 1024; height: 576 }
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: status === Image.Ready ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 450 } }
    }
    Rectangle {
        anchors.fill: backdrop
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: T.bg }
            GradientStop { position: 0.35; color: Qt.rgba(0.04, 0.05, 0.07, 0.85) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.07, 0.2) }
        }
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: parent.height * 0.4 }
        height: parent.height * 0.4
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.05, 0.07, 0) }
            GradientStop { position: 1.0; color: T.bg }
        }
    }

    // ----- Informations -----
    Column {
        id: info
        x: T.margin
        y: 40
        width: parent.width * 0.55
        spacing: 12

        Item {
            width: parent.width
            height: 90
            Image {
                id: logo
                anchors { left: parent.left; bottom: parent.bottom }
                width: Math.min(parent.width, 420)
                height: parent.height
                fillMode: Image.PreserveAspectFit
                horizontalAlignment: Image.AlignLeft
                sourceSize { width: 420; height: 90 }
                asynchronous: true
                source: page.meta && page.meta.logo ? Addons.posterUrl(page.meta.logo) : ""
                visible: status === Image.Ready
            }
            Text {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                visible: !logo.visible
                text: page.meta ? page.meta.name : "Chargement…"
                color: T.text
                font.pixelSize: T.fontTitle
                font.bold: true
                elide: Text.ElideRight
            }
        }
        Row {
            spacing: 10
            Repeater {
                model: page.meta ? [page.meta.releaseInfo, page.meta.runtime, page.meta.imdbRating ? "★ " + page.meta.imdbRating : ""]
                                   .concat((page.meta.genres || []).slice(0, 3)).filter(function (s) { return s; }) : []
                delegate: Rectangle {
                    height: 28
                    width: chipText.implicitWidth + 22
                    radius: 14
                    color: String(modelData).charAt(0) === "★" ? "#3a3215" : Qt.rgba(1, 1, 1, 0.1)
                    Text {
                        id: chipText
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
            text: page.meta ? (page.meta.description || "") : ""
            color: "#c9d1dc"
            font.pixelSize: T.fontSmall + 1
            lineHeight: 1.15
            wrapMode: Text.Wrap
            maximumLineCount: page.isSeries ? 2 : 4
            elide: Text.ElideRight
        }
        Text {
            visible: page.selectedTitle !== ""
            width: parent.width
            text: page.selectedTitle
            color: T.text
            font.pixelSize: T.fontBody
            font.bold: true
            elide: Text.ElideRight
        }
    }

    // ----- Boutons -----
    ListView {
        id: actions
        objectName: "boutons"
        anchors { left: parent.left; leftMargin: T.margin; top: info.bottom; topMargin: 22 }
        width: parent.width - 2 * T.margin
        height: 52
        orientation: ListView.Horizontal
        spacing: 14
        interactive: false
        keyNavigationEnabled: true   // sinon les fleches sont desactivees avec interactive: false (Qt >= 5.7)
        focus: true
        // Liste fixe : la recalculer (nombre de sources, reprise) remettrait la selection sur "Lecture"
        // a chaque reponse d'addon. Seuls les libelles changent (label()).
        model: ["play", "sources", "sort"]
        function label(key) {
            if (key === "play")
                return page.resumeText ? "▶  " + page.resumeText : "▶  Lecture";
            if (key === "sources")
                return "Sources" + (page.streams.length ? "  (" + page.streams.length + ")" : "");
            return "Tri des sources";
        }
        delegate: Rectangle {
            readonly property bool focused: actions.activeFocus && ListView.isCurrentItem
            readonly property bool enabledAction: modelData === "sort" || page.streams.length > 0
            height: 52
            width: actionLabel.implicitWidth + 48
            radius: 26
            color: focused ? T.text : modelData === "play" ? T.accent : Qt.rgba(1, 1, 1, 0.12)
            opacity: enabledAction ? 1 : 0.45
            scale: focused ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: T.anim } }
            Behavior on color { ColorAnimation { duration: T.anim } }
            Text {
                id: actionLabel
                anchors.centerIn: parent
                text: actions.label(modelData)
                color: parent.focused ? T.bg : T.text
                font.pixelSize: T.fontBody
                font.bold: true
            }
        }
        Keys.onReturnPressed: activate()
        Keys.onEnterPressed: activate()
        Keys.onDownPressed: (page.isSeries ? seasonTabs : streamList).forceActiveFocus()
        function activate() {
            const key = model[currentIndex];
            if (key === "play" && page.streams.length)
                page.playBest();
            else if (key === "sources" && page.streams.length)
                page.openSources();
            else if (key === "sort")
                page.sortRequested();
        }
    }

    Text {
        id: statusLine
        anchors { left: actions.left; top: actions.bottom; topMargin: 12 }
        text: page.streamsStatus
        color: T.textMuted
        font.pixelSize: T.fontSmall
    }

    // ----- Series : saisons et episodes -----
    ListView {
        id: seasonTabs
        objectName: "saisons"
        visible: page.isSeries && !page.showingSources
        anchors { left: parent.left; leftMargin: T.margin; right: parent.right; top: statusLine.bottom; topMargin: 16 }
        height: 40
        orientation: ListView.Horizontal
        spacing: 10
        model: page.seasons
        currentIndex: page.seasonIndex
        delegate: Rectangle {
            readonly property bool focused: seasonTabs.activeFocus && ListView.isCurrentItem
            height: 36
            width: seasonLabel.implicitWidth + 32
            radius: 18
            color: focused ? T.text : index === page.seasonIndex ? T.surfaceHigh : "transparent"
            border.color: index === page.seasonIndex && !focused ? T.line : "transparent"
            Text {
                id: seasonLabel
                anchors.centerIn: parent
                text: "Saison " + modelData
                color: parent.focused ? T.bg : T.text
                font.pixelSize: T.fontSmall
                font.bold: index === page.seasonIndex
            }
        }
        Keys.onLeftPressed: if (currentIndex > 0) { currentIndex--; page.seasonIndex = currentIndex; }
        Keys.onRightPressed: if (currentIndex < count - 1) { currentIndex++; page.seasonIndex = currentIndex; }
        Keys.onUpPressed: actions.forceActiveFocus()
        Keys.onDownPressed: episodeList.forceActiveFocus()
    }

    ListView {
        id: episodeList
        objectName: "episodes"
        visible: page.isSeries && !page.showingSources
        anchors { left: parent.left; right: parent.right; top: seasonTabs.bottom; topMargin: 14; bottom: parent.bottom }
        orientation: ListView.Horizontal
        leftMargin: T.margin
        rightMargin: T.margin
        spacing: 18
        clip: true
        model: page.seasonEpisodes
        highlightMoveDuration: T.anim
        preferredHighlightBegin: T.margin
        preferredHighlightEnd: width - T.margin - 280
        highlightRangeMode: ListView.ApplyRange
        delegate: Item {
            readonly property bool focused: episodeList.activeFocus && ListView.isCurrentItem
            readonly property real progress: page.progressOf ? page.progressOf(modelData.id) : 0
            width: 280
            height: episodeList.height
            Rectangle {
                id: thumb
                width: 280
                height: 158
                radius: T.radius
                color: T.surface
                clip: true
                scale: parent.focused ? 1.05 : 1
                transformOrigin: Item.Top
                Behavior on scale { NumberAnimation { duration: T.anim } }
                border.width: parent.focused ? 3 : 0
                border.color: T.focus
                Image {
                    anchors { fill: parent; margins: parent.border.width }
                    source: modelData.thumbnail ? Addons.posterUrl(modelData.thumbnail) : ""
                    sourceSize { width: 280; height: 158 }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    anchors { left: parent.left; top: parent.top; margins: 8 }
                    height: 24
                    width: epNum.implicitWidth + 16
                    radius: 6
                    color: Qt.rgba(0, 0, 0, 0.7)
                    Text {
                        id: epNum
                        anchors.centerIn: parent
                        text: "E" + (modelData.episode || modelData.number)
                        color: T.text
                        font.pixelSize: T.fontTiny
                        font.bold: true
                    }
                }
                Rectangle {
                    visible: progress > 0
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 5
                    color: Qt.rgba(0, 0, 0, 0.6)
                    Rectangle {
                        height: parent.height
                        width: parent.width * Math.min(1, progress)
                        color: progress >= 1 ? T.ok : T.accent
                    }
                }
            }
            Text {
                anchors { top: thumb.bottom; topMargin: 12; left: thumb.left; right: thumb.right }
                text: modelData.title || modelData.name || ("Épisode " + (modelData.episode || modelData.number))
                color: parent.focused ? T.text : T.textMuted
                font.pixelSize: T.fontSmall
                font.bold: parent.focused
                elide: Text.ElideRight
            }
            Text {
                anchors { top: thumb.bottom; topMargin: 38; left: thumb.left; right: thumb.right }
                text: modelData.overview || modelData.description || ""
                color: T.textDim
                font.pixelSize: T.fontTiny
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
        Keys.onReturnPressed: if (count) { page.episodeChosen(page.seasonEpisodes[currentIndex]); actions.forceActiveFocus(); }
        Keys.onEnterPressed: if (count) { page.episodeChosen(page.seasonEpisodes[currentIndex]); actions.forceActiveFocus(); }
        Keys.onUpPressed: seasonTabs.forceActiveFocus()
        onModelChanged: currentIndex = 0
    }

    // ----- Sources -----
    ListView {
        id: streamList
        objectName: "sources"
        visible: page.showingSources || !page.isSeries
        anchors { left: parent.left; leftMargin: T.margin; right: parent.right; rightMargin: T.margin;
                  top: statusLine.bottom; topMargin: 16; bottom: parent.bottom; bottomMargin: 20 }
        clip: true
        model: page.streams
        spacing: 8
        highlightMoveDuration: T.anim
        opacity: page.showingSources || activeFocus ? 1 : 0.55
        Behavior on opacity { NumberAnimation { duration: T.anim } }
        delegate: Rectangle {
            readonly property bool focused: streamList.activeFocus && ListView.isCurrentItem
            width: streamList.width
            height: 64
            radius: T.radiusSmall
            color: focused ? T.surfaceHigh : Qt.rgba(1, 1, 1, 0.04)
            border.color: focused ? T.focus : "transparent"
            border.width: 2
            Rectangle {
                visible: index === 0
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 2 }
                width: 4
                radius: 2
                color: T.accent
            }
            Column {
                anchors { left: parent.left; leftMargin: 18; right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    width: parent.width
                    text: (index === 0 ? "Recommandé  ·  " : "") + (modelData.badges || "") + (modelData.badges ? "   " : "") + modelData.addon
                    color: T.text
                    font.pixelSize: T.fontSmall + 1
                    font.bold: index === 0
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: (modelData.stream.title || modelData.stream.description || modelData.stream.name || "").split("\n")[0]
                    color: T.textMuted
                    font.pixelSize: T.fontTiny + 1
                    elide: Text.ElideRight
                }
            }
        }
        Keys.onReturnPressed: if (count) page.streamChosen(page.streams[currentIndex])
        Keys.onEnterPressed: if (count) page.streamChosen(page.streams[currentIndex])
        Keys.onUpPressed: {
            if (currentIndex > 0)
                decrementCurrentIndex();
            else
                actions.forceActiveFocus();
        }
    }
}
