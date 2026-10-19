import QtQuick 2.15
import fbx.application 1.0

// Lanceur installe sur le Player (icone du menu principal).
// 1. Trouve le PC : adresse memorisee, sinon recherche sur le reseau local (l'adresse peut changer).
// 2. Le reconnait par son identifiant ; s'il y en a plusieurs, propose le choix.
// 3. Charge l'appli depuis le PC (mises a jour sans reinstaller) ; sinon ecran d'attente.
Application {
    id: win

    readonly property int agentPort: 11480
    property string phase: "search"      // search | wait | choose | ready
    property var found: []               // [{ host, status }]
    property string message: ""
    property int scanned: 0
    property int scanTotal: 0
    property var scanToken: null

    // Lance depuis le PC (developpement) : l'URL du lanceur donne l'adresse du PC.
    readonly property string launchHost: {
        const m = /^https?:\/\/([^\/:]+)/.exec(String(Qt.resolvedUrl(".")));
        return m ? m[1] : "";
    }

    // PC memorise. Lecture seule ici : un seul objet Settings doit ecrire (celui de l'appli),
    // car chacun remplace tout le stockage par sa copie (libfbxqml, settings.js).
    QtObject {
        id: settings
        property string pcHost: ""
        property string pcId: ""
        property string pcName: ""
        function load() {
            try {
                const s = App.settings || {};
                pcHost = s.pcHost || "";
                pcId = s.pcId || "";
                pcName = s.pcName || "";
            } catch (e) {
                pcHost = pcId = pcName = "";
            }
        }
    }

    function log(msg) {
        console.log("[lanceur] " + msg);
    }

    // GET JSON avec delai (les adresses sans machine ne repondent jamais).
    function probe(host, timeoutMs) {
        return new Promise(resolve => {
            const xhr = new XMLHttpRequest();
            let done = false;
            const timer = Qt.createQmlObject("import QtQuick 2.0; Timer { repeat: false }", win, "probeTimer");
            const finish = value => {
                if (done)
                    return;
                done = true;
                timer.stop();
                timer.destroy();
                resolve(value);
            };
            timer.interval = timeoutMs;
            timer.triggered.connect(() => { xhr.abort(); finish(null); });
            timer.start();
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                try {
                    const s = xhr.status === 200 ? JSON.parse(xhr.responseText) : null;
                    finish(s && s.agent === "stremio-fbx" ? { host: host, status: s } : null);
                } catch (e) {
                    finish(null);
                }
            };
            xhr.open("GET", "http://" + host + ":" + agentPort + "/fbx/api/status");
            xhr.send();
        });
    }

    function start() {
        settings.load();
        phase = "search";
        message = "";
        const first = launchHost || settings.pcHost;
        if (!first) {
            scan();
            return;
        }
        probe(first, 3000).then(r => {
            if (r && (!settings.pcId || r.status.pcId === settings.pcId || launchHost))
                ready(r);
            else
                scan();
        });
    }

    // Recherche des PC sur les reseaux locaux probables, par lots.
    function scan() {
        phase = "search";
        found = [];
        const prefixes = [];
        const add = p => { if (p && prefixes.indexOf(p) === -1) prefixes.push(p); };
        add(settings.pcHost.replace(/\.\d+$/, "."));
        add("192.168.0.");
        add("192.168.1.");
        add("192.168.27.");
        const hosts = [];
        prefixes.forEach(p => { for (let i = 1; i < 255; i++) hosts.push(p + i); });
        const token = {};
        scanToken = token;
        scanned = 0;
        scanTotal = hosts.length;
        log("recherche sur " + prefixes.join("x, ") + "x");
        const batch = 48;
        const next = from => {
            if (scanToken !== token)
                return;
            const slice = hosts.slice(from, from + batch);
            if (!slice.length) {
                finishScan();
                return;
            }
            Promise.all(slice.map(h => probe(h, 1500))).then(results => {
                if (scanToken !== token)
                    return;
                scanned = Math.min(scanTotal, from + batch);
                results.forEach(r => { if (r) found = found.concat([r]); });
                // Le PC habituel est trouve : inutile de continuer.
                if (found.some(f => f.status.pcId === settings.pcId))
                    finishScan();
                else
                    next(from + batch);
            });
        };
        next(0);
    }

    function finishScan() {
        scanToken = null;
        const known = found.find(f => f.status.pcId === settings.pcId);
        if (known)
            ready(known);
        else if (found.length === 1)
            ready(found[0]);
        else if (found.length > 1) {
            phase = "choose";
            choices.forceActiveFocus();
        } else {
            phase = "wait";
            retry.restart();
        }
    }

    function ready(r) {
        const changed = settings.pcId && r.status.pcId !== settings.pcId;
        settings.pcHost = r.host;
        settings.pcId = r.status.pcId;
        settings.pcName = r.status.pcName;
        phase = "ready";
        log("PC " + r.status.pcName + " (" + r.host + ")" + (changed ? " : nouveau PC" : ""));
        appLoader.setSource("http://" + r.host + ":" + agentPort + "/fbx/app/qml/AppRoot.qml",
                            { pcHost: r.host, pcInfo: r.status });
    }

    Loader {
        id: appLoader
        anchors.fill: parent
        focus: win.phase === "ready"
        onStatusChanged: {
            if (status === Loader.Ready) {
                item.forceActiveFocus();
            } else if (status === Loader.Error) {
                win.message = "L'appli n'a pas pu etre chargee depuis le PC.";
                win.phase = "wait";
                retry.restart();
            }
        }
    }

    // Nouvel essai regulier tant que le PC est absent.
    Timer {
        id: retry
        interval: 10000
        repeat: true
        running: win.phase === "wait"
        onTriggered: {
            if (!settings.pcHost)
                return;
            probe(settings.pcHost, 2500).then(r => { if (r && win.phase === "wait") win.ready(r); });
        }
    }

    // ===================== Ecrans d'attente =====================

    Rectangle {
        anchors.fill: parent
        visible: win.phase !== "ready"
        color: "#0a0d12"

        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 90 }
            width: 96
            height: 96
            radius: 26
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#9a7bff" }
                GradientStop { position: 1.0; color: "#7c5cff" }
            }
            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 5
                text: "▶"
                color: "white"
                font.pixelSize: 44
            }
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: win.phase === "search"
                NumberAnimation { from: 1; to: 1.08; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.08; to: 1; duration: 700; easing.type: Easing.InOutQuad }
            }
        }

        Column {
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 220 }
            width: 900
            spacing: 18

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.phase === "search" ? "Recherche du PC…"
                      : win.phase === "choose" ? "Plusieurs PC trouves"
                      : "Pret — en attente du PC"
                color: "#f3f5f8"
                font.pixelSize: 40
                font.bold: true
            }
            Text {
                visible: win.phase === "search"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: win.scanTotal ? "Reseau local : " + win.scanned + " / " + win.scanTotal + " adresses"
                                    : settings.pcName ? "Connexion a « " + settings.pcName + " »…" : ""
                color: "#9aa6b6"
                font.pixelSize: 20
            }

            // Instructions
            Rectangle {
                visible: win.phase === "wait"
                width: parent.width
                height: steps.implicitHeight + 48
                radius: 14
                color: "#121821"
                border.color: "#2c394d"
                Column {
                    id: steps
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                    spacing: 14
                    Text {
                        width: parent.width
                        text: (win.message ? win.message + "\n" : "")
                              + (settings.pcName ? "Le PC « " + settings.pcName + " » (" + settings.pcHost + ") ne repond pas."
                                                 : "Aucun PC trouve sur le reseau.")
                        color: "#ffb547"
                        font.pixelSize: 20
                        wrapMode: Text.Wrap
                    }
                    Repeater {
                        model: [
                            "1.  Allumez le PC, sur le meme reseau que la Freebox.",
                            "2.  Double-cliquez sur « Lancer-Stremio-Freebox » (dossier du projet) et laissez la fenetre ouverte.",
                            "3.  L'appli s'ouvre ici toute seule (nouvel essai toutes les 10 s).",
                            "Astuce : sur le PC, « Lancer-Stremio-Freebox --demarrage-auto oui » le lance a chaque ouverture de session."
                        ]
                        delegate: Text {
                            width: steps.width
                            text: modelData
                            color: index === 3 ? "#67748a" : "#f3f5f8"
                            font.pixelSize: index === 3 ? 16 : 20
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            ListView {
                id: choices
                visible: win.phase === "choose"
                width: parent.width
                height: Math.min(4, count) * 72
                spacing: 10
                model: win.found
                focus: win.phase === "choose"
                delegate: Rectangle {
                    readonly property bool focused: choices.activeFocus && ListView.isCurrentItem
                    width: choices.width
                    height: 62
                    radius: 10
                    color: focused ? "#243044" : "#121821"
                    border.color: focused ? "white" : "#2c394d"
                    border.width: 2
                    Text {
                        anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                        text: modelData.status.pcName + "    " + modelData.host
                              + (modelData.status.stremio.ok ? "    ·  Stremio actif" : "    ·  Stremio arrete")
                        color: "#f3f5f8"
                        font.pixelSize: 22
                    }
                }
                Keys.onReturnPressed: win.ready(win.found[currentIndex])
                Keys.onEnterPressed: win.ready(win.found[currentIndex])
            }

            Text {
                visible: win.phase === "wait"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "OK : rechercher un PC sur le reseau     ·     Retour : quitter"
                color: "#9aa6b6"
                font.pixelSize: 18
            }
        }
    }

    // Touches tant que l'appli n'est pas chargee
    Item {
        id: keys
        focus: win.phase === "wait" || win.phase === "search"
        Keys.onReturnPressed: if (win.phase === "wait") win.scan()
        Keys.onEnterPressed: if (win.phase === "wait") win.scan()
        Keys.onPressed: {
            if ((event.key === Qt.Key_Back || event.key === Qt.Key_Escape) && win.phase !== "ready") {
                event.accepted = true;
                Qt.quit();
            }
        }
    }

    Component.onCompleted: Qt.callLater(start)
}
