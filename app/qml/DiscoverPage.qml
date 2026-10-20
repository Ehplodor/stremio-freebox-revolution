import QtQuick 2.15
import "../js/theme.js" as T
import "../js/core/discover.js" as Discover

// Decouvrir : filtres en haut (Type, Catalogue, Genre / Annee, Decennie, Note), grille en dessous.
// Filtres : Gauche / Droite pour passer de l'un a l'autre, OK pour ouvrir la liste des choix,
// Bas pour la grille. Les filtres sont recalcules par AppRoot (setFilters) ; chaque changement
// emet changed(key, value).
FocusScope {
    id: page

    // [{ key, label, value, options: [{ id, label }] }]
    property var filters: []
    property var metas: []
    property string status: ""           // "", "chargement", "fin", "erreur"
    property var progressOf: null
    signal changed(string key, var value)
    signal activated(var meta)
    signal moreWanted()
    signal up()

    // Retour d'une fiche : la grille si on y etait, sinon les filtres.
    property bool inGrid: false
    function focusFilters() {
        (inGrid && grid.count ? grid : filterBar).forceActiveFocus();
    }

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    // ----- Filtres -----
    ListView {
        id: filterBar
        objectName: "filtres"
        x: T.margin
        y: 86
        width: parent.width - 2 * T.margin
        height: 64
        orientation: ListView.Horizontal
        spacing: 12
        interactive: false
        keyNavigationEnabled: true
        focus: true
        model: page.filters
        delegate: Rectangle {
            readonly property bool focused: filterBar.activeFocus && ListView.isCurrentItem
            width: Math.max(150, valueText.implicitWidth + 40)
            height: 64
            radius: T.radiusSmall
            color: focused ? T.text : T.surface
            border.color: focused ? T.focus : T.line
            Text {
                x: 16
                y: 8
                text: modelData.label
                color: parent.focused ? T.bg : T.textDim
                font.pixelSize: T.fontTiny
            }
            Text {
                id: valueText
                x: 16
                y: 28
                width: parent.width - 32
                text: modelData.valueLabel
                color: parent.focused ? T.bg : T.text
                font.pixelSize: T.fontSmall + 1
                font.bold: true
                elide: Text.ElideRight
            }
        }
        Keys.onReturnPressed: chooser.open(page.filters[currentIndex])
        Keys.onEnterPressed: chooser.open(page.filters[currentIndex])
        Keys.onDownPressed: if (grid.count) grid.forceActiveFocus()
        Keys.onUpPressed: page.up()
        onActiveFocusChanged: if (activeFocus) page.inGrid = false
    }

    Text {
        anchors { left: filterBar.left; top: filterBar.bottom; topMargin: 8 }
        text: page.status === "chargement" ? "Chargement…"
              : page.metas.length ? page.metas.length + " titres" + (page.status === "" ? "  ·  la suite se charge en descendant" : "")
              : page.status === "erreur" ? "Catalogue indisponible" : "Aucun titre avec ces filtres"
        color: T.textDim
        font.pixelSize: T.fontTiny + 1
    }

    PosterGrid {
        id: grid
        objectName: "grille"
        anchors { top: filterBar.bottom; topMargin: 34; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        columns: 6
        metas: page.metas
        progressOf: page.progressOf
        canLoadMore: page.status === ""
        onActivated: page.activated(meta)
        onMoreWanted: page.moreWanted()
        onUpFromTop: filterBar.forceActiveFocus()
        onActiveFocusChanged: if (activeFocus) page.inGrid = true
    }

    // ----- Liste des choix d'un filtre -----
    Rectangle {
        id: chooser
        property var filter: null
        visible: false
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.05, 0.85)

        function open(f) {
            filter = f;
            list.model = f.options;
            list.currentIndex = Math.max(0, f.options.findIndex(o => o.id === f.value));
            list.positionViewAtIndex(list.currentIndex, ListView.Center);
            visible = true;
            list.forceActiveFocus();
        }
        function close() {
            visible = false;
            filterBar.forceActiveFocus();
        }

        Rectangle {
            anchors.centerIn: parent
            width: 460
            height: Math.min(560, 90 + list.count * 48)
            radius: T.radius
            color: T.bgElevated
            border.color: T.line
            Text {
                x: 24
                y: 20
                text: chooser.filter ? chooser.filter.label : ""
                color: T.text
                font.pixelSize: T.fontBody
                font.bold: true
            }
            ListView {
                id: list
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 64; bottomMargin: 16; leftMargin: 12; rightMargin: 12 }
                clip: true
                highlightMoveDuration: 0
                delegate: Rectangle {
                    readonly property bool focused: list.activeFocus && ListView.isCurrentItem
                    width: list.width
                    height: 48
                    radius: T.radiusSmall
                    color: focused ? T.text : "transparent"
                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28
                        text: (chooser.filter && modelData.id === chooser.filter.value ? "✓  " : "     ") + modelData.label
                        color: parent.focused ? T.bg : T.text
                        font.pixelSize: T.fontSmall + 1
                        elide: Text.ElideRight
                    }
                }
                Keys.onReturnPressed: { const f = chooser.filter; chooser.close(); page.changed(f.key, f.options[currentIndex].id); }
                Keys.onEnterPressed: { const f = chooser.filter; chooser.close(); page.changed(f.key, f.options[currentIndex].id); }
                Keys.onPressed: {
                    if (event.key === Qt.Key_Back || event.key === Qt.Key_Backspace || event.key === Qt.Key_Escape) {
                        event.accepted = true;
                        chooser.close();
                    }
                }
            }
        }
    }
}
