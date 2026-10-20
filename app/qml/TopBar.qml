import QtQuick 2.15
import "../js/theme.js" as T

// Barre du haut : nom de l'appli, onglets, PC connecte, compte, heure.
// Gauche/Droite : onglet ; OK : ouvrir ; Bas : revenir au contenu.
FocusScope {
    id: bar
    height: 72

    property int current: 0
    property var tabs: ["Accueil", "Recherche", "Réglages"]
    property string pcName: ""
    property bool pcOk: true
    property string account: ""          // initiale ou "" si pas de compte
    signal tabChosen(int index)
    signal leave()

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.04, 0.05, 0.07, 0.95) }
            GradientStop { position: 1.0; color: Qt.rgba(0.04, 0.05, 0.07, 0.0) }
        }
    }

    Row {
        x: T.margin
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Rectangle {
            width: 34
            height: 34
            radius: 9
            anchors.verticalCenter: parent.verticalCenter
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#9a7bff" }
                GradientStop { position: 1.0; color: T.accent }
            }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 2
                text: "▶"
                color: "white"
                font.pixelSize: 16
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Revo Stream"
            color: T.text
            font.pixelSize: 24
            font.bold: true
            font.letterSpacing: 0.5
        }
        Item { width: 24; height: 1 }
        Repeater {
            model: bar.tabs
            delegate: Rectangle {
                readonly property bool selected: index === bar.current
                readonly property bool focused: bar.activeFocus && index === nav.currentIndex
                anchors.verticalCenter: parent.verticalCenter
                height: 40
                width: tabLabel.implicitWidth + 36
                radius: 20
                color: focused ? T.text : selected ? T.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: T.anim } }
                Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: parent.focused ? T.bg : parent.selected ? T.text : T.textMuted
                    font.pixelSize: T.fontSmall + 2
                    font.bold: parent.selected || parent.focused
                }
            }
        }
    }

    // Index de l'onglet sous le focus (independant de l'onglet affiche).
    QtObject {
        id: nav
        property int currentIndex: bar.current
    }

    Row {
        anchors { right: parent.right; rightMargin: T.margin; verticalCenter: parent.verticalCenter }
        spacing: 18
        Rectangle {
            visible: bar.pcName !== ""
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            width: pcLabel.implicitWidth + 40
            radius: 16
            color: T.surface
            Rectangle {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 9
                height: 9
                radius: 5
                color: bar.pcOk ? T.ok : T.danger
            }
            Text {
                id: pcLabel
                x: 28
                anchors.verticalCenter: parent.verticalCenter
                text: bar.pcName
                color: T.textMuted
                font.pixelSize: T.fontSmall
            }
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 17
            color: bar.account ? T.accent : T.surface
            Text {
                anchors.centerIn: parent
                text: bar.account ? bar.account.charAt(0).toUpperCase() : "?"
                color: "white"
                font.pixelSize: T.fontSmall
                font.bold: true
            }
        }
        Text {
            id: clock
            anchors.verticalCenter: parent.verticalCenter
            color: T.text
            font.pixelSize: T.fontBody
            function update() {
                const d = new Date();
                text = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
            }
            Component.onCompleted: update()
            Timer { interval: 20000; running: true; repeat: true; onTriggered: clock.update() }
        }
    }

    Keys.onLeftPressed: nav.currentIndex = Math.max(0, nav.currentIndex - 1)
    Keys.onRightPressed: nav.currentIndex = Math.min(bar.tabs.length - 1, nav.currentIndex + 1)
    Keys.onReturnPressed: bar.tabChosen(nav.currentIndex)
    Keys.onEnterPressed: bar.tabChosen(nav.currentIndex)
    Keys.onDownPressed: bar.leave()
    onActiveFocusChanged: if (activeFocus) nav.currentIndex = bar.current
}
