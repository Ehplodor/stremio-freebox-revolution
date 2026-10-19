import QtQuick 2.15
import "../js/theme.js" as T

// Message bref en bas de l'ecran (reprise, erreur, PC deconnecte...).
Item {
    id: toast
    anchors.fill: parent

    function show(message, kind) {
        label.text = message;
        bubble.color = kind === "error" ? T.danger : kind === "warn" ? "#6b4a12" : T.surfaceHigh;
        bubble.opacity = 1;
        hideTimer.restart();
    }

    Rectangle {
        id: bubble
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 48 }
        width: Math.min(label.implicitWidth + 56, parent.width - 2 * T.margin)
        height: label.implicitHeight + 28
        radius: height / 2
        color: T.surfaceHigh
        opacity: 0
        visible: opacity > 0
        border.color: Qt.rgba(1, 1, 1, 0.08)
        Behavior on opacity { NumberAnimation { duration: 220 } }

        Text {
            id: label
            anchors.centerIn: parent
            width: Math.min(implicitWidth, toast.width - 2 * T.margin - 56)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: T.text
            font.pixelSize: T.fontBody
        }
    }

    Timer {
        id: hideTimer
        interval: 4200
        onTriggered: bubble.opacity = 0
    }
}
