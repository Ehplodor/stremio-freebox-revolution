import QtQuick 2.15
import fbx.application 1.0
import "js/config.js" as Config
import "js/http.js" as Http
import "js/core/addons.js" as Addons
import "js/core/playback.js" as Playback
import "js/core/vtt.js" as Vtt

// Client compatible Stremio pour le Freebox Player.
// Accueil (rangees de catalogues) -> fiche -> choix du flux -> lecteur.
Application {
    id: app

    property var addons: []
    property string screen: "home"       // home | details | player
    property var current: null           // { type, id, videoId, meta }
    property var client: Addons.createClient(Http.fetchJson)
    readonly property var transport: ({ fetchJson: Http.fetchJson, postJson: Http.postJson })

    function log(msg) {
        console.log("[app] " + msg);
    }

    function loadAddons() {
        client.loadAddons(Config.ADDONS).then(result => {
            addons = result.addons;
            result.errors.forEach(e => log("addon indisponible : " + e.transportUrl + " (" + e.error + ")"));
            const rows = Addons.homeCatalogs(addons);
            log(addons.length + " addons, " + rows.length + " rangees : "
                + rows.map(r => r.addonName + "/" + r.name + "(" + r.type + ")").join(", "));
            rowsModel.clear();
            rows.forEach(r => rowsModel.append({ transportUrl: r.transportUrl, addonName: r.addonName,
                                                 type: r.type, cid: r.id, name: r.name }));
            home.forceActiveFocus();
            if (Config.AUTOTEST && Config.AUTOTEST.id)
                autotest.start();
        }).catch(e => log("chargement des addons en echec : " + e));
    }

    function typeLabel(type) {
        return type === "movie" ? "Films" : type === "series" ? "Series" : type;
    }

    // ----- Fiche -----

    function openMeta(type, id) {
        log("fiche " + type + "/" + id);
        current = { type: type, id: id, videoId: null, meta: null };
        details.meta = null;
        details.episodes = [];
        details.streams = [];
        details.streamsStatus = "";
        screen = "details";
        details.forceActiveFocus();
        client.meta(addons, type, id).then(meta => {
            current.meta = meta;
            details.meta = meta;
            const episodes = [];
            Addons.seasons(meta).forEach(s => s.episodes.forEach(v => episodes.push(v)));
            if (type === "series" && episodes.length) {
                details.episodes = episodes;
                log(meta.name + " : " + episodes.length + " episodes");
            } else {
                loadStreams(type, id);
            }
        }).catch(e => log("fiche en echec : " + e));
    }

    function loadStreams(type, videoId) {
        current.videoId = videoId;
        details.streams = [];
        details.streamsStatus = "chargement";
        client.streams(addons, type, videoId).then(groups => {
            const items = [];
            groups.forEach(g => {
                if (g.error)
                    log("flux " + g.addon + " en echec : " + g.error);
                g.items.forEach(s => items.push({ addon: g.addon, stream: s }));
            });
            details.streams = items;
            details.streamsStatus = items.length ? items.length + " flux" : "aucun flux (installer un addon de flux)";
            log("flux pour " + videoId + " : " + items.length);
            if (items.length)
                details.focusStreams();
            autotest.streamsLoaded(items);
        }).catch(e => log("flux en echec : " + e));
    }

    // ----- Lecture -----

    function seriesInfo() {
        const parts = (current.videoId || "").split(":");
        return parts.length === 3 ? { season: parseInt(parts[1], 10), episode: parseInt(parts[2], 10) } : null;
    }

    function play(item) {
        log("choix du flux " + item.addon + " : " + JSON.stringify(item.stream).slice(0, 200));
        Playback.plan(item.stream, Config.SETTINGS, transport, seriesInfo()).then(p => {
            if (p.kind === "external") {
                log("ouverture externe " + p.external);
                App.urlOpen(p.external, "");
                return;
            }
            if (p.kind !== "play") {
                log("flux non lisible : " + p.reason);
                return;
            }
            const probe = p.probe ? p.probe.streams.map(s => s.track + ":" + s.codec).join(" ") : "probe indisponible";
            log((p.transcoded ? "transcodage" : "lecture directe") + " (" + probe + ") -> " + p.url);
            const title = current.meta ? current.meta.name : "";
            playerLoader.setSource("qml/PlayerPage.qml", { title: title, source: p.url });
            screen = "player";
            playerLoader.forceActiveFocus();
            loadSubtitles(item.stream);
        }).catch(e => log("preparation de la lecture en echec : " + e));
    }

    // Sous-titres : ceux du flux, puis ceux des addons ; francais en priorite.
    function loadSubtitles(stream) {
        const own = (stream.subtitles || []).map(s => ({ addon: "flux", sub: s }));
        client.subtitles(addons, current.type, current.videoId).then(groups => {
            let all = own;
            groups.forEach(g => g.items.forEach(s => all.push({ addon: g.addon, sub: s })));
            log(all.length + " sous-titres disponibles");
            const pick = all.find(x => /^(fre|fra|fr)$/.test(x.sub.lang)) || all[0];
            if (!pick)
                return;
            const url = Playback.subtitlesVttUrl(Config.SETTINGS, pick.sub.url);
            Http.fetchText(url).then(text => {
                const cues = Vtt.parse(text);
                log("sous-titres " + pick.addon + " " + pick.sub.lang + " : " + cues.length + " lignes");
                if (playerLoader.item)
                    playerLoader.item.cues = cues;
            }).catch(e => log("sous-titres en echec : " + e));
        });
    }

    function stopPlayer() {
        if (playerLoader.item)
            playerLoader.item.stop();
        playerLoader.source = "";
        screen = "details";
        details.forceActiveFocus();
    }

    function back() {
        if (screen === "player") {
            stopPlayer();
        } else if (screen === "details") {
            screen = "home";
            home.forceActiveFocus();
        } else {
            Qt.quit();
        }
    }

    // ----- Interface -----

    ListModel { id: rowsModel }

    FocusScope {
        id: root
        anchors.fill: parent
        focus: true

        Rectangle {
            anchors.fill: parent
            color: "#0e1318"
        }

        ListView {
            id: home
            visible: app.screen === "home"
            anchors.fill: parent
            anchors.topMargin: 30
            focus: true
            clip: true
            model: rowsModel
            spacing: 10
            highlightMoveDuration: 150
            preferredHighlightBegin: 0
            preferredHighlightEnd: 340
            highlightRangeMode: ListView.ApplyRange
            cacheBuffer: 700

            header: Text {
                x: 40
                height: 60
                color: "white"
                font.pixelSize: 34
                font.bold: true
                text: "Accueil"
            }

            delegate: PosterRow {
                id: row
                width: home.width
                companion: Config.SETTINGS.companion
                title: model.addonName + " · " + model.name + " · " + app.typeLabel(model.type)
                focus: ListView.isCurrentItem
                onActivated: app.openMeta(meta.type || model.type, meta.id)
                Component.onCompleted: {
                    const ref = { transportUrl: model.transportUrl, type: model.type, id: model.cid, name: model.name };
                    row.status = "chargement";
                    app.client.catalog(ref).then(metas => {
                        row.metas = metas;
                        row.status = metas.length ? "" : "vide";
                        app.log("rangee " + ref.name + " (" + ref.type + ") : " + metas.length + " titres");
                    }).catch(e => {
                        row.status = "erreur";
                        app.log("rangee " + ref.name + " en echec : " + e);
                    });
                }
            }
        }

        DetailsPage {
            id: details
            anchors.fill: parent
            visible: app.screen === "details"
            onEpisodeChosen: app.loadStreams(app.current.type, video.id)
            onStreamChosen: app.play(item)
        }

        Loader {
            id: playerLoader
            anchors.fill: parent
            visible: app.screen === "player"
            onLoaded: {
                item.logMessage.connect(app.log);
                item.finished.connect(app.stopPlayer);
            }
        }

        Keys.onPressed: {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                event.accepted = true;
                app.back();
            }
        }
    }

    // ----- Scenario automatique (tests sans telecommande, voir js/config.js) -----

    QtObject {
        id: autotest
        property bool running: false

        function start() {
            running = true;
            app.log("autotest : ouverture de " + Config.AUTOTEST.id);
            stepTimer.interval = 8000;   // laisse l'accueil charger ses images
            stepTimer.step = "open";
            stepTimer.start();
        }

        function streamsLoaded(items) {
            if (!running || stepTimer.step !== "wait-streams")
                return;
            if (!items.length) {
                app.log("autotest : aucun flux, arret");
                running = false;
                return;
            }
            stepTimer.step = "stop";
            stepTimer.interval = Config.AUTOTEST.playSeconds * 1000;
            app.play(items[0]);
            stepTimer.start();
        }
    }

    Timer {
        id: stepTimer
        property string step: ""
        onTriggered: {
            if (step === "open") {
                let images = 0, failed = 0;
                for (let i = 0; i < home.count; i++) {
                    const row = home.itemAtIndex(i);
                    if (row) {
                        images += row.loadedImages;
                        failed += row.failedImages;
                    }
                }
                app.log("autotest : accueil " + home.count + " rangees, affiches chargees " + images + ", en echec " + failed);
                step = "wait-streams";
                app.openMeta(Config.AUTOTEST.type, Config.AUTOTEST.id);
            } else if (step === "stop") {
                app.log("autotest : arret de la lecture");
                app.back();
                step = "home";
                interval = 3000;
                start();
            } else if (step === "home") {
                app.back();
                app.log("autotest : termine, retour a l'accueil");
                autotest.running = false;
            }
        }
    }

    Component.onCompleted: {
        log("demarrage, ecran " + width + "x" + height);
        loadAddons();
    }
}
