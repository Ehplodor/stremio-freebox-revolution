import QtQuick 2.15
import "../js/theme.js" as T

// Compte Stremio : affiche le code de liaison et son QR code, ou le compte lie.
// OK : creer un nouveau code (non lie) ou se deconnecter (lie). Retour : accueil.
FocusScope {
    id: page

    property string email: ""           // compte lie
    property string code: ""
    property string link: ""
    property string qrcode: ""
    property string status: ""
    signal newCode()
    signal unlink()

    Rectangle {
        anchors.fill: parent
        color: T.bg
    }

    Column {
        anchors.centerIn: parent
        spacing: 24
        width: parent.width * 0.8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: T.text
            font.pixelSize: 38
            font.bold: true
            text: "Compte Stremio"
        }

        // Compte lie
        Text {
            visible: page.email !== ""
            anchors.horizontalCenter: parent.horizontalCenter
            color: T.text
            font.pixelSize: 26
            text: "Connecté : " + page.email + "\n\nOK pour se déconnecter de ce Player."
            horizontalAlignment: Text.AlignHCenter
        }

        // Liaison
        Row {
            visible: page.email === ""
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 50

            Rectangle {
                width: 260
                height: 260
                radius: T.radius
                color: "white"
                Image {
                    anchors { fill: parent; margins: 10 }
                    source: page.qrcode
                    sourceSize { width: 240; height: 240 }
                    smooth: false
                }
            }

            Column {
                spacing: 16
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    color: T.text
                    font.pixelSize: 22
                    text: "Sur ton téléphone ou ton PC, connecté à Stremio,\nscanne le QR code ou ouvre :"
                }
                Text {
                    color: T.accent
                    font.pixelSize: 26
                    text: page.link || "..."
                }
                Text {
                    color: T.text
                    font.pixelSize: 22
                    text: "Code :"
                }
                Text {
                    color: T.text
                    font.pixelSize: 64
                    font.bold: true
                    font.letterSpacing: 12
                    text: page.code || "...."
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: T.textMuted
            font.pixelSize: 20
            text: page.status
        }
    }

    focus: true
    Keys.onReturnPressed: page.email ? page.unlink() : page.newCode()
    Keys.onEnterPressed: page.email ? page.unlink() : page.newCode()
}
