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
    property string current: ""

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
            if (status === 200 && picker === pickText)
                log("  " + text.replace(/\n/g, " | ").substring(0, 300));
            else if (status === 200)
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

    function media(name) {
        return Qt.resolvedUrl("media/" + name).toString();
    }

    function pickProbe(d) {
        var parts = [];
        for (var i = 0; i < d.streams.length; i++)
            parts.push(d.streams[i].track + " " + d.streams[i].codec);
        return "probe : " + d.format.name + ", " + parts.join(", ");
    }

    function pickText(d) {
        return "inattendu : JSON";
    }

    function play(file, url) {
        current = file + " " + url;
        log("Lecture " + file + " : " + url);
        playing = true;
        playerLoader.setSource(file, { url: url });
        playerLoader.forceActiveFocus();
    }

    function stopPlayer() {
        log("Arret de la lecture demande");
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
        case "direct-ac3": play("PlayerQtMultimedia.qml", media("h264_ac3.mkv")); break;
        case "direct-eac3": play("PlayerQtMultimedia.qml", media("h264_eac3.mkv")); break;
        case "direct-dts": play("PlayerQtMultimedia.qml", media("h264_dts.mkv")); break;
        case "direct-hevc": play("PlayerQtMultimedia.qml", media("hevc_ac3_srt.mkv")); break;
        case "probe-hevc": runXhr(Config.PC_SERVER + "/hlsv2/probe?mediaURL=" + encodeURIComponent(media("hevc_ac3_srt.mkv")), pickProbe); break;
        case "tc-hevc": play("PlayerQtMultimedia.qml", Config.hlsv2(media("hevc_ac3_srt.mkv"), false)); break;
        case "tc-ac3": play("PlayerQtMultimedia.qml", Config.hlsv2(media("h264_ac3.mkv"), true)); break;
        case "tc-hevc-web": play("PlayerQtMultimedia.qml", Config.hlsv2(Config.HEVC_1080_WEB, false)); break;
        case "subs-vtt": runXhr(Config.PC_SERVER + "/subtitles.vtt?from=" + encodeURIComponent(media("test.srt")), pickText); break;
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
        ListElement { kind: "direct-ac3"; label: "Direct : H.264 + AC3 5.1 (MKV)" }
        ListElement { kind: "direct-eac3"; label: "Direct : H.264 + E-AC3 5.1 (MKV)" }
        ListElement { kind: "direct-dts"; label: "Direct : H.264 + DTS 5.1 (MKV)" }
        ListElement { kind: "direct-hevc"; label: "Direct : HEVC + AC3 (MKV)" }
        ListElement { kind: "probe-hevc"; label: "Serveur PC : probe du MKV HEVC" }
        ListElement { kind: "tc-hevc"; label: "Transcodage PC : HEVC vers HLS H.264/AAC" }
        ListElement { kind: "tc-ac3"; label: "Transcodage PC : AC3 force vers AAC" }
        ListElement { kind: "tc-hevc-web"; label: "Transcodage PC : HEVC 1080p internet" }
        ListElement { kind: "subs-vtt"; label: "Serveur PC : SRT vers VTT" }
        ListElement { kind: "urlopen-mp4"; label: "Lecteur systeme : App.urlOpen MP4" }
    }

    ListModel { id: logModel }

    // Mode automatique : enchaine les tests pour qu'on puisse tout suivre depuis la console du PC.
    property var autoQueue: []

    Timer {
        id: autoTimer
        repeat: false
        onTriggered: app.autoNext()
    }

    function autoNext() {
        if (playing)
            stopPlayer();
        var q = autoQueue;
        if (!q.length) {
            log("== Fin des tests automatiques");
            return;
        }
        var kind = q.shift();
        autoQueue = q;
        log("== Auto : " + kind);
        runTest(kind);
        var isVideo = /^(qtmm|fbx|direct|tc-)/.test(kind);
        autoTimer.interval = isVideo ? 30000 : 6000;
        autoTimer.start();
    }

    // Application est une fenetre : Keys ne s'y attache pas, d'ou ce FocusScope.
    FocusScope {
        id: ui
        anchors.fill: parent
        focus: true

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
                autoTimer.stop();
                event.accepted = true;
                if (app.playing)
                    app.stopPlayer();
                else
                    Qt.quit();
            }
        }
    }

    Component.onCompleted: {
        log("Demarrage. Haut/Bas pour choisir, OK pour lancer, Retour pour quitter.");
        log("Serveur PC configure : " + Config.PC_SERVER);
        runProbe();
        // Serie courante : transcodage par le serveur du PC (etape 0 bis).
        autoQueue = ["pc-server", "qtmm-local", "direct-ac3", "direct-eac3", "direct-dts",
                     "direct-hevc", "probe-hevc", "tc-hevc", "tc-ac3", "tc-hevc-web", "subs-vtt"];
        autoTimer.interval = 2000;
        autoTimer.start();
    }
}
