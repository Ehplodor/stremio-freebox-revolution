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
              + "   ·   Retour pour revenir"
        color: T.textDim
        font.pixelSize: T.fontSmall
    }

    PosterGrid {
        id: grid
        objectName: "grille"
        anchors { top: heading.bottom; topMargin: 44; bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        columns: page.columns
        focus: true
        metas: page.metas
        progressOf: page.progressOf
        canLoadMore: page.status === ""
        onActivated: page.activated(meta)
        onMoreWanted: page.moreWanted()
    }

    Text {
        anchors.centerIn: parent
        visible: !page.metas.length && page.status !== "chargement"
        text: page.status === "erreur" ? "Catalogue indisponible" : "Aucun titre"
        color: T.textMuted
        font.pixelSize: T.fontBody
    }
}
