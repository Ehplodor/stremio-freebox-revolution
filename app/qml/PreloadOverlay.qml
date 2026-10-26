import QtQuick 2.15
import "../js/theme.js" as T

// Preparation des catalogues du jour (premier demarrage du jour, ou apres « Vider la memoire ») :
// progression par catalogue. OK ou Retour : continuer, le chargement se poursuit en arriere-plan.
FocusScope {
    id: overlay
    anchors.fill: parent

    property int done: 0
    property int total: 0
    property string detail: ""
    signal dismissed()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.02, 0.03, 0.05, 0.88)
    }

    Rectangle {
        anchors.centerIn: parent
        width: 640
        height: 250
        radius: T.radius
        color: T.bgElevated
        border.color: T.line

        Text {
            id: title
            x: 40
            y: 34
            text: "Préparation des catalogues du jour"
            color: T.text
            font.pixelSize: T.fontHeading
            font.bold: true
        }
        Text {
            anchors { left: title.left; top: title.bottom; topMargin: 10 }
            width: 560
            text: "Une seule fois par jour : les menus s'ouvriront ensuite sans attendre."
            color: T.textMuted
            font.pixelSize: T.fontSmall
            wrapMode: Text.Wrap
        }
        Rectangle {
            id: track
            x: 40
            y: 132
            width: 560
            height: 12
            radius: 6
            color: T.surface
            Rectangle {
                width: overlay.total ? Math.max(12, parent.width * overlay.done / overlay.total) : 12
                height: parent.height
                radius: 6
                color: T.accent
                Behavior on width { NumberAnimation { duration: 250 } }
            }
        }
        Text {
            anchors { left: track.left; top: track.bottom; topMargin: 12 }
            text: overlay.total ? overlay.done + " / " + overlay.total + " catalogues" + (overlay.detail ? "  ·  " + overlay.detail : "")
                                : "Chargement des addons…"
            color: T.textMuted
            font.pixelSize: T.fontSmall
            width: 560
            elide: Text.ElideRight
        }
        Text {
            anchors { right: track.right; bottom: parent.bottom; bottomMargin: 22 }
            text: "OK : continuer pendant le chargement"
            color: T.textDim
            font.pixelSize: T.fontTiny + 1
        }
    }

    Keys.onPressed: {
        event.accepted = true;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Back
                || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace)
            overlay.dismissed();
    }
}
