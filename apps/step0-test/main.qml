import QtQuick 2.3
import fbx.application 1.0
import "js/config.js" as Config
import "js/probe.js" as Probe
import "js/net.js" as Net

// Etape 0 du plan : faisabilite sur le Freebox Player Revolution.
// Haut/Bas pour choisir un test, OK pour le lancer, Retour pour arreter la video ou quitter.
// Tout le JavaScript est en ES5 tant que la version du moteur n'est pas connue.
Application {
    id: app

    property bool playing: false

    function log(msg) {
        var d = new Date();
        var hh = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
                 + ":" + ("0" + d.getSeconds()).slice(-2);
        console.log("[step0] " + msg);
        logModel.append({ line: hh + "  " + msg });
        logView.positionViewAtEnd();
    }

    function runProbe() {
        var lines = Probe.run(app);
        for (var i = 0; i < lines.length; i++)
            log(lines[i]);
    }

    function runXhr(url, picker) {
        log("GET " + url);
        Net.get(url, function (err, status, text, ms) {
            if (err) {
                log("  ECHEC " + err + " apres " + ms + " ms");
                return;
            }
            log("  HTTP " + status + " en " + ms + " ms, " + text.length + " octets");
            if (status === 200)
                log("  " + Net.summarize(text, picker));
        });
    }

    function pickManifest(d) {
        return "manifest : " + d.name + " " + d.version + ", " + (d.catalogs ? d.catalogs.length : 0) + " catalogues";
    }

    function pickCatalog(d) {
        var metas = d.metas || [];
        return metas.length + " films, premier : " + (metas.length ? metas[0].name : "-");
    }

    function pickServer(d) {
        var v = d.values || {};
        return "serveur Stremio " + v.serverVersion + ", transcodage max " + v.transcodeMaxWidth + " px";
    }

    function play(file, url) {
        log("Lecture " + file + " : " + url);
        playing = true;
        playerLoader.setSource(file, { url: url });
        playerLoader.forceActiveFocus();
    }

    function stopPlayer() {
        if (playerLoader.item && playerLoader.item.stopPlayback)
            playerLoader.item.stopPlayback();
        playerLoader.source = "";
        playing = false;
        tests.forceActiveFocus();
        log("Lecture arretee");
    }

    function runTest(kind) {
        switch (kind) {
        case "probe": runProbe(); break;
        case "cinemeta": runXhr(Config.CINEMETA + "/manifest.json", pickManifest); break;
        case "cinemeta-http": runXhr(Config.CINEMETA_HTTP + "/manifest.json", pickManifest); break;
        case "catalog": runXhr(Config.CINEMETA + "/catalog/movie/top.json", pickCatalog); break;
        case "pc-server": runXhr(Config.PC_SERVER + "/settings", pickServer); break;
        case "qtmm-mp4": play("PlayerQtMultimedia.qml", Config.MP4_H264); break;
        case "qtmm-hls": play("PlayerQtMultimedia.qml", Config.HLS_HTTPS); break;
        case "qtmm-hls-http": play("PlayerQtMultimedia.qml", Config.HLS_HTTP); break;
        case "qtmm-mkv": play("PlayerQtMultimedia.qml", Config.MKV_H264); break;
        case "qtmm-local": play("PlayerQtMultimedia.qml", Qt.resolvedUrl(Config.LOCAL_MP4)); break;
        case "fbx-mp4": play("PlayerFbx.qml", Config.MP4_H264); break;
        case "fbx-hls": play("PlayerFbx.qml", Config.HLS_HTTPS); break;
        case "fbx-hls-prefix": play("PlayerFbx.qml", "hls+" + Config.HLS_HTTPS); break;
        case "fbx-mkv": play("PlayerFbx.qml", Config.MKV_H264); break;
        case "urlopen-mp4":
            log("App.urlOpen " + Config.MP4_H264);
            App.urlOpen(Config.MP4_H264, "video/mp4");
            break;
        default: log("Test inconnu : " + kind);
        }
    }

    ListModel {
        id: testModel
        ListElement { kind: "probe"; label: "Version Qt, modules et JavaScript" }
        ListElement { kind: "cinemeta"; label: "XHR HTTPS Cinemeta manifest.json" }
        ListElement { kind: "cinemeta-http"; label: "XHR HTTP Cinemeta manifest.json" }
        ListElement { kind: "catalog"; label: "XHR catalogue Cinemeta (redirection 307)" }
        ListElement { kind: "pc-server"; label: "XHR serveur Stremio du PC (11470)" }
        ListElement { kind: "qtmm-mp4"; label: "QtMultimedia : MP4 H.264 (HTTPS)" }
        ListElement { kind: "qtmm-hls"; label: "QtMultimedia : HLS (HTTPS)" }
        ListElement { kind: "qtmm-hls-http"; label: "QtMultimedia : HLS (HTTP)" }
        ListElement { kind: "qtmm-mkv"; label: "QtMultimedia : MKV H.264 (HTTPS)" }
        ListElement { kind: "qtmm-local"; label: "QtMultimedia : MP4 servi par le PC (HTTP)" }
        ListElement { kind: "fbx-mp4"; label: "fbx.media : MP4 H.264" }
        ListElement { kind: "fbx-hls"; label: "fbx.media : HLS" }
        ListElement { kind: "fbx-hls-prefix"; label: "fbx.media : HLS avec prefixe hls+" }
        ListElement { kind: "fbx-mkv"; label: "fbx.media : MKV H.264" }
        ListElement { kind: "urlopen-mp4"; label: "Lecteur systeme : App.urlOpen MP4" }
    }

    ListModel { id: logModel }

    Rectangle {
        anchors.fill: parent
        color: "#101418"
    }

    Text {
        id: title
        anchors { left: parent.left; top: parent.top; margins: 30 }
        color: "white"
        font.pixelSize: 30
        text: "Stremio Freebox, etape 0 : tests de faisabilite"
    }

    ListView {
        id: tests
        anchors { left: parent.left; top: title.bottom; bottom: parent.bottom; margins: 30 }
        width: parent.width * 0.38
        focus: true
        clip: true
        model: testModel
        highlightMoveDuration: 0
        highlight: Rectangle { color: "#2a6fdb"; radius: 4 }

        // Pas de leftPadding (Qt 5.6+) : le runtime de la box peut etre plus ancien.
        delegate: Item {
            width: tests.width
            height: 38
            Text {
                anchors { fill: parent; leftMargin: 10 }
                verticalAlignment: Text.AlignVCenter
                color: "white"
                font.pixelSize: 22
                elide: Text.ElideRight
                text: (index + 1) + ". " + label
            }
        }

        Keys.onReturnPressed: app.runTest(testModel.get(currentIndex).kind)
        Keys.onEnterPressed: app.runTest(testModel.get(currentIndex).kind)
    }

    ListView {
        id: logView
        anchors { left: tests.right; right: parent.right; top: title.bottom; bottom: parent.bottom; margins: 30 }
        clip: true
        model: logModel
        delegate: Text {
            width: logView.width
            wrapMode: Text.Wrap
            color: "#c8d0d8"
            font.pixelSize: 18
            text: line
        }
    }

    Loader {
        id: playerLoader
        anchors.fill: parent
        visible: app.playing
        focus: app.playing

        onStatusChanged: {
            if (status === Loader.Error)
                app.log("Impossible de charger le lecteur (module absent ?)");
        }
        onLoaded: item.logMessage.connect(app.log)

        Keys.onPressed: {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                event.accepted = true;
                app.stopPlayer();
            }
        }
    }

    Keys.onPressed: {
        if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape) {
            event.accepted = true;
            if (app.playing)
                app.stopPlayer();
            else
                Qt.quit();
        }
    }

    Component.onCompleted: {
        log("Demarrage. Haut/Bas pour choisir, OK pour lancer, Retour pour quitter.");
        log("Serveur PC configure : " + Config.PC_SERVER);
        runProbe();
    }
}
