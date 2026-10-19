import QtQuick 2.15
import fbx.application 1.0
import "js/config.js" as Config
import "js/http.js" as Http
import "js/core/addons.js" as Addons
import "js/core/playback.js" as Playback
import "js/core/vtt.js" as Vtt
import "js/core/account.js" as Account
import "js/core/sorting.js" as Sorting

// Client compatible Stremio pour le Freebox Player.
// Accueil (rangees de catalogues) -> fiche -> choix du flux -> lecteur.
Application {
    id: app

    property var addons: []
    property string screen: "home"       // home | details | player | account | sort
    property var sortPrefs: Sorting.normalize(null)
    property string authKey: ""
    property var localRows: ({})         // rangees issues du compte : { continue: [...], library: [...] }
    property var catalogCache: ({})      // transportUrl|type|id -> Promise des metas (delegues recrees en defilant)
    property var playToken: null         // lecture en preparation (ignore un second OK)
    property var current: null           // { type, id, videoId, meta }
    property var client: Addons.createClient(Http.fetchJson)
    readonly property var transport: ({ fetchJson: Http.fetchJson, postJson: Http.postJson })
    property var account: Account.createAccount(transport)

    function log(msg) {
        console.log("[app] " + msg);
    }

    // Addons et rangees : ceux du compte s'il est lie, sinon ceux par defaut.
    function loadAddons() {
        authKey = settings.authKey || "";
        const fromAccount = authKey
            ? Promise.all([account.addons(authKey), account.libraryItems(authKey).catch(e => {
                log("bibliotheque indisponible : " + e);
                return [];
            })]).then(r => {
                log("compte : " + r[0].length + " addons, " + r[1].length + " elements de bibliotheque");
                localRows = {
                    continue: Account.continueWatching(r[1]).map(Account.toMeta),
                    library: Account.library(r[1]).map(Account.toMeta)
                };
                return r[0].map(d => ({ transportUrl: Addons.localToServer(d.transportUrl, Config.SETTINGS.server),
                                        manifest: d.manifest }));
            }).catch(e => {
                log("compte inutilisable (" + e + "), addons par defaut");
                if (/Session does not exist/.test(String(e))) {
                    settings.authKey = "";
                    authKey = "";
                }
                return null;
            })
            : Promise.resolve(null);

        fromAccount.then(accountAddons => {
            if (!accountAddons)
                localRows = {};
            const urls = (accountAddons ? [] : Config.DEFAULT_ADDONS).concat(Config.DEV_ADDONS);
            return client.loadAddons(urls).then(result => {
                result.errors.forEach(e => log("addon indisponible : " + e.transportUrl + " (" + e.error + ")"));
                return (accountAddons || []).concat(result.addons);
            });
        }).then(list => {
            addons = list;
            const rows = Addons.homeCatalogs(addons);
            log(addons.length + " addons, " + rows.length + " rangees : "
                + rows.map(r => r.addonName + "/" + r.name + "(" + r.type + ")").join(", "));
            catalogCache = {};
            rowsModel.clear();
            if ((localRows.continue || []).length)
                rowsModel.append({ kind: "continue", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Continuer a regarder" });
            if ((localRows.library || []).length)
                rowsModel.append({ kind: "library", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Bibliotheque" });
            rows.forEach(r => rowsModel.append({ kind: "catalog", transportUrl: r.transportUrl, addonName: r.addonName,
                                                 type: r.type, cid: r.id, name: r.name }));
            if (screen === "home")
                home.forceActiveFocus();
            if (Config.AUTOTEST && (Config.AUTOTEST.id || Config.AUTOTEST.linkOnly) && !autotest.done)
                autotest.start();
        }).catch(e => log("chargement des addons en echec : " + e));
    }

    // ----- Compte -----

    function openAccount() {
        screen = "account";
        accountPage.forceActiveFocus();
        accountPage.status = "";
        if (authKey) {
            accountPage.email = "...";
            account.user(authKey).then(u => accountPage.email = u.email || "compte lie")
                .catch(e => accountPage.email = "compte lie (" + e + ")");
        } else {
            accountPage.email = "";
            startLink();
        }
    }

    function startLink() {
        linkTimer.stop();
        accountPage.code = "";
        accountPage.status = "Creation du code...";
        account.createLink().then(l => {
            accountPage.code = l.code;
            accountPage.link = l.link;
            accountPage.qrcode = l.qrcode;
            accountPage.status = "En attente de validation (OK pour un nouveau code)";
            log("code de liaison " + l.code + " : " + l.link);
            const code = l.code;
            // 100 essais toutes les 3 s : le code reste valable quelques minutes.
            return Account.pollLink(account, code, (fn, ms) => {
                if (screen !== "account" || accountPage.code !== code)
                    return;                       // ecran quitte ou nouveau code : on arrete
                linkTimer.callback = fn;
                linkTimer.interval = ms;
                linkTimer.start();
            }, 3000, 100).then(key => {
                settings.authKey = key;
                log("compte lie");
                accountPage.status = "Compte lie !";
                screen = "home";
                loadAddons();
            });
        }).catch(e => {
            accountPage.status = "Erreur : " + e;
            log("liaison en echec : " + e);
        });
    }

    function unlink() {
        settings.authKey = "";
        log("compte delie de ce Player");
        screen = "home";
        loadAddons();
    }

    // Catalogue d'une rangee, une seule requete par session d'accueil.
    function catalog(ref) {
        const key = ref.transportUrl + "|" + ref.type + "|" + ref.id;
        if (!catalogCache[key]) {
            catalogCache[key] = client.catalog(ref);
            catalogCache[key].catch(() => { delete catalogCache[key]; });   // reessai au prochain affichage
        }
        return catalogCache[key];
    }

    function typeLabel(type) {
        return type === "movie" ? "Films" : type === "series" ? "Series" : type;
    }

    // ----- Fiche -----

    function openMeta(type, id) {
        log("fiche " + type + "/" + id);
        const opened = { type: type, id: id, videoId: null, meta: null };
        current = opened;
        details.meta = null;
        details.episodes = [];
        details.streams = [];
        details.streamsStatus = "";
        screen = "details";
        details.forceActiveFocus();
        client.meta(addons, type, id).then(meta => {
            if (current !== opened)
                return;                          // une autre fiche a ete ouverte entre-temps
            current.meta = meta;
            details.meta = meta;
            const episodes = [];
            Addons.seasons(meta).forEach(s => s.episodes.forEach(v => episodes.push(v)));
            if (type === "series" && episodes.length) {
                details.episodes = episodes;
                log(meta.name + " : " + episodes.length + " episodes");
                if (autotest.running && Config.AUTOTEST.episode)
                    loadStreams(type, Config.AUTOTEST.episode);
            } else {
                loadStreams(type, id);
            }
        }).catch(e => {
            if (current !== opened)
                return;
            log("fiche en echec : " + e);
            details.streamsStatus = "fiche indisponible (" + e.message + ")";
        });
    }

    function loadStreams(type, videoId) {
        current.videoId = videoId;
        details.streams = [];
        details.streamsStatus = "chargement";
        const request = {};                  // ignore les reponses d'un chargement precedent
        current.streamsRequest = request;
        let answered = 0;
        let items = [];
        current.rawStreams = [];
        current.streamsProgress = "";
        client.streams(addons, type, videoId, (g, total) => {
            if (current.streamsRequest !== request)
                return;
            answered++;
            log("flux " + g.addon + " : " + (g.error ? "echec (" + g.error + ")" : g.items.length));
            if (g.items.length) {
                const hadNone = current.rawStreams.length === 0;
                items = items.concat(g.items.map(s => ({ addon: g.addon, stream: s })));
                current.rawStreams = items;
                if (hadNone)
                    details.focusStreams();
            }
            current.streamsProgress = answered < total ? " (" + answered + "/" + total + " addons)" : "";
            refreshStreams();
        }).then(() => {
            if (current.streamsRequest !== request)
                return;
            log("flux pour " + videoId + " : " + items.length);
            autotest.streamsLoaded(details.streams);
        }).catch(e => log("flux en echec : " + e));
    }

    // Liste affichee : flux tries et filtres selon les preferences.
    function refreshStreams() {
        const raw = current.rawStreams || [];
        const r = Sorting.sortStreams(raw, sortPrefs);
        details.setStreams(r.visible);
        details.streamsStatus = r.visible.length + " flux" + (r.hidden ? ", " + r.hidden + " masques" : "")
            + (current.streamsProgress || "")
            + (!current.streamsProgress && !raw.length ? " - aucun flux trouve" : "");
    }

    function openSortSettings() {
        screen = "sort";
        sortPage.prefs = sortPrefs;
        sortPage.forceActiveFocus();
    }

    function saveSortPrefs(prefs) {
        sortPrefs = prefs;
        settings.sortPrefs = JSON.stringify(prefs);
        log("tri : " + JSON.stringify(prefs));
    }

    // ----- Lecture -----

    function seriesInfo() {
        const parts = (current.videoId || "").split(":");
        return parts.length === 3 ? { season: parseInt(parts[1], 10), episode: parseInt(parts[2], 10) } : null;
    }

    function play(item, forceTranscoding) {
        if (playToken)
            return;                              // deja en preparation
        const token = {};
        playToken = token;
        const opened = current;
        details.streamsStatus = "preparation de la lecture...";
        log("choix du flux " + item.addon + " : " + (item.stream.name || "") + " " + (item.stream.title || "").split("\n")[0]);
        Playback.plan(item.stream, Config.SETTINGS, transport, seriesInfo(), forceTranscoding).then(p => {
            playToken = null;
            if (current !== opened || screen !== "details")
                return;                          // l'utilisateur est parti entre-temps
            refreshStreams();
            if (p.kind === "external") {
                log("ouverture externe " + p.external);
                App.urlOpen(p.external, "");
                return;
            }
            if (p.kind !== "play") {
                log("flux non lisible : " + p.reason);
                details.streamsStatus = "flux non lisible : " + p.reason;
                return;
            }
            const probe = p.probe ? p.probe.streams.map(s => s.track + ":" + s.codec).join(" ") : "probe indisponible";
            log((p.transcoded ? "transcodage" : "lecture directe") + " (" + probe + ") via " + p.url.split("?")[0]);
            const audio = Playback.audioTracks(p.probe);
            current.playback = p;
            current.playingItem = item;
            pendingSubtitles = null;
            playerLoader.setSource("qml/PlayerPage.qml", {
                title: current.meta ? current.meta.name : "",
                source: p.url,
                audioTracks: audio,
                audioSwitchable: p.transcoded && audio.length > 1,
                // Transcodage : le PC peut mettre du temps a preparer le debut (torrent, 4K).
                startTimeoutMs: p.transcoded ? 60000 : 15000,
                subtitleTracks: [{ label: "Desactives", kind: "off" }]
            });
            screen = "player";
            playerLoader.forceActiveFocus();
            loadSubtitles(item.stream, p, audio);
        }).catch(e => {
            playToken = null;
            log("preparation de la lecture en echec : " + e);
            if (current === opened)
                details.streamsStatus = "lecture impossible : " + e.message;
        });
    }

    // Echec du lecteur : en lecture directe, on retente en transcodage par le PC
    // (ex. H.264 10 bits que le probe ne distingue pas) ; sinon retour a la fiche.
    function playbackFailed(reason) {
        const p = current.playback;
        log("echec de lecture (" + reason + ")" + (p && !p.transcoded ? ", nouvel essai en transcodage" : ""));
        Qt.callLater(() => {
            stopPlayer();
            if (p && !p.transcoded && current.playingItem)
                play(current.playingItem, true);
            else
                details.streamsStatus = "lecture impossible : " + reason;
        });
    }

    // Piste audio choisie dans le lecteur : on recharge le flux HLS avec cette seule piste.
    function chooseAudio(index) {
        const p = current.playback;
        const track = playerLoader.item.audioTracks[index];
        log("piste audio : " + track.label);
        playerLoader.item.audioIndex = index;
        playerLoader.item.reload(Playback.withAudio(p.url, track.id));
    }

    // Sous-titres proposes : integres a la video, puis ceux du flux et des addons.
    function loadSubtitles(stream, p, audio) {
        const options = [{ label: "Desactives", kind: "off" }];
        Playback.embeddedSubtitles(p.probe).forEach(s => options.push({
            label: s.label + " (integre)", kind: "embedded", language: s.language,
            url: Playback.embeddedSubtitleUrl(Config.SETTINGS, p.mediaUrl, p.transcoded ? p.url : "", s)
        }));
        const external = (stream.subtitles || []).map(s => ({ addon: "flux", sub: s }));
        log("sous-titres integres : " + (options.length - 1) + ", recherche dans les addons");
        client.subtitles(addons, current.type, current.videoId).then(groups => {
            log("sous-titres des addons : " + groups.map(g => g.addon + "=" + (g.error ? "echec" : g.items.length)).join(", "));
            groups.forEach(g => g.items.forEach(s => external.push({ addon: g.addon, sub: s })));
            // Francais puis anglais d'abord, 40 au plus : la liste des addons peut etre tres longue.
            const rank = x => Playback.isFrench(x.sub.lang) ? 0 : /^(eng|en)$/i.test(x.sub.lang || "") ? 1 : 2;
            external.sort((a, b) => rank(a) - rank(b)).slice(0, 40).forEach(x => options.push({
                label: (Playback.languageName(x.sub.lang) || "?") + " - " + x.addon, kind: "external",
                language: x.sub.lang, url: Playback.subtitlesVttUrl(Config.SETTINGS, x.sub.url)
            }));
        }).catch(e => log("sous-titres des addons en echec : " + e)).then(() => {
            log(options.length - 1 + " sous-titres proposes");
            // Le lecteur se charge de facon asynchrone : on lui passe la liste des qu'il est pret.
            pendingSubtitles = { options: options, first: Playback.defaultSubtitle(options, audio) };
            applySubtitles();
        }).catch(e => log("sous-titres : erreur " + e));
    }

    property var pendingSubtitles: null

    function applySubtitles() {
        const page = playerLoader.item;
        if (!page || !pendingSubtitles)
            return;
        const pending = pendingSubtitles;
        pendingSubtitles = null;
        page.subtitleTracks = pending.options;
        if (pending.first > 0)
            chooseSubtitle(pending.first);
    }

    function chooseSubtitle(index) {
        const page = playerLoader.item;
        const option = page.subtitleTracks[index];
        page.subtitleIndex = index;
        page.cues = [];
        if (option.kind === "off") {
            log("sous-titres desactives");
            return;
        }
        // Sous-titres integres : le compagnon lit toute la piste, ce qui peut prendre plusieurs minutes.
        Http.fetchText(option.url, option.kind === "embedded" ? 300000 : 0).then(text => {
            if (playerLoader.item !== page || page.subtitleIndex !== index)
                return;
            page.cues = Vtt.parse(text);
            log("sous-titres " + option.label + " : " + page.cues.length + " lignes");
        }).catch(e => log("sous-titres en echec : " + e));
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
        } else if (screen === "sort") {
            screen = "details";
            refreshStreams();
            details.focusStreams();
        } else if (screen === "details" || screen === "account") {
            linkTimer.stop();
            screen = "home";
            home.forceActiveFocus();
        } else {
            Qt.quit();
        }
    }

    // ----- Interface -----

    // Reglages persistants du runtime Freebox (App.settings) ; LocalStorage est refuse
    // aux applis en mode developpeur.
    Settings {
        id: settings
        property string authKey: ""
        property int launches: 0
        property string sortPrefs: ""   // JSON des preferences de tri
    }

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

            header: Item {
                width: home.width
                height: 60
                Text {
                    x: 40
                    color: "white"
                    font.pixelSize: 34
                    font.bold: true
                    text: "Accueil"
                }
                Text {
                    anchors { right: parent.right; rightMargin: 40; top: parent.top; topMargin: 10 }
                    color: "#9aa7b4"
                    font.pixelSize: 18
                    text: (app.authKey ? "Compte lie" : "Pas de compte") + "  ·  touche Menu : compte"
                }
            }

            delegate: PosterRow {
                id: row
                width: home.width
                companion: Config.SETTINGS.companion
                title: model.kind === "catalog" ? model.addonName + " · " + model.name + " · " + app.typeLabel(model.type) : model.name
                focus: ListView.isCurrentItem
                onActivated: app.openMeta(meta.type || model.type, meta.id)
                Component.onCompleted: {
                    if (model.kind !== "catalog") {
                        row.metas = app.localRows[model.kind] || [];
                        return;
                    }
                    const ref = { transportUrl: model.transportUrl, type: model.type, id: model.cid, name: model.name };
                    row.status = "chargement";
                    app.catalog(ref).then(metas => {
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

        SortSettingsPage {
            id: sortPage
            anchors.fill: parent
            visible: app.screen === "sort"
            onChanged: app.saveSortPrefs(prefs)
        }

        DetailsPage {
            id: details
            anchors.fill: parent
            visible: app.screen === "details"
            onEpisodeChosen: app.loadStreams(app.current.type, video.id)
            onStreamChosen: app.play(item)
        }

        AccountPage {
            id: accountPage
            anchors.fill: parent
            visible: app.screen === "account"
            onNewCode: app.startLink()
            onUnlink: app.unlink()
        }

        Timer {
            id: linkTimer
            property var callback: null
            onTriggered: if (callback) callback()
        }

        Loader {
            id: playerLoader
            anchors.fill: parent
            visible: app.screen === "player"
            onLoaded: {
                item.logMessage.connect(app.log);
                item.finished.connect(() => Qt.callLater(app.stopPlayer));
                item.failed.connect(app.playbackFailed);
                item.audioChosen.connect(app.chooseAudio);
                item.subtitleChosen.connect(app.chooseSubtitle);
                app.applySubtitles();
            }
        }

        Keys.onPressed: {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                event.accepted = true;
                app.back();
            } else if (event.key === Qt.Key_Menu && app.screen === "home") {
                event.accepted = true;
                app.openAccount();
            } else if (event.key === Qt.Key_Menu && app.screen === "details") {
                event.accepted = true;
                app.openSortSettings();
            }
        }
    }

    // ----- Scenario automatique (tests sans telecommande, voir js/config.js) -----

    QtObject {
        id: autotest
        property bool running: false
        property bool done: false

        function start() {
            done = true;
            if (Config.AUTOTEST.linkOnly) {
                // Ouvre seulement l'ecran Compte (liaison a distance : le code part dans la console).
                if (!app.authKey)
                    app.openAccount();
                return;
            }
            running = true;
            stepTimer.interval = 8000;   // laisse l'accueil charger ses images
            stepTimer.step = Config.AUTOTEST.account && !app.authKey ? "account" : "open";
            stepTimer.start();
        }

        function streamsLoaded(items) {
            if (!running || stepTimer.step !== "wait-streams")
                return;
            if (Config.AUTOTEST.sort) {
                app.log("autotest : " + details.streamsStatus + " ; en tete : "
                        + JSON.stringify(items.slice(0, 5).map(i => i.badges)));
                stepTimer.step = "sort";
                stepTimer.interval = 3000;
                stepTimer.start();
                return;
            }
            if (!items.length || Config.AUTOTEST.noPlay) {
                app.log("autotest : " + items.length + " flux, arret sans lecture");
                running = false;
                return;
            }
            stepTimer.step = Config.AUTOTEST.tracks ? "audio" : "stop";
            stepTimer.interval = Config.AUTOTEST.tracks ? 20000 : Config.AUTOTEST.playSeconds * 1000;
            app.play(items[0]);
            stepTimer.start();
        }
    }

    Timer {
        id: stepTimer
        property string step: ""
        onTriggered: {
            if (step === "account") {
                app.log("autotest : ecran Compte");
                app.openAccount();
                step = "account-close";
                interval = 15000;
                start();
            } else if (step === "account-close") {
                app.log("autotest : code affiche " + accountPage.code + ", statut \"" + accountPage.status + "\", fermeture");
                app.back();
                step = "open";
                interval = 2000;
                start();
            } else if (step === "open") {
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
            } else if (step === "sort") {
                // Modifie les preferences comme a la telecommande : ecran de tri, langue anglaise,
                // taille en premier critere, puis retour a la fiche.
                const saved = app.sortPrefs;
                app.openSortSettings();
                sortPage.apply("languages", 1);
                sortPage.apply("languages", 1);
                for (let k = 0; k < 4; k++)
                    sortPage.apply("order:size", -1);
                app.back();
                app.log("autotest : apres modification : " + details.streamsStatus + " ; en tete : "
                        + JSON.stringify(details.streams.slice(0, 5).map(i => i.badges)));
                app.saveSortPrefs(saved);       // remet les preferences de Rod
                app.refreshStreams();
                autotest.running = false;
            } else if (step === "audio") {
                const page = playerLoader.item;
                app.log("autotest : pistes audio " + JSON.stringify(page.audioTracks.map(a => a.label))
                        + ", sous-titres " + JSON.stringify(page.subtitleTracks.map(s => s.label)));
                if (page.audioTracks.length > 1)
                    app.chooseAudio(1);
                step = "subtitle";
                interval = 20000;
                start();
            } else if (step === "subtitle") {
                const page = playerLoader.item;
                const i = page.subtitleTracks.findIndex(s => s.kind === "embedded" && !Playback.isFrench(s.language));
                if (i > 0)
                    app.chooseSubtitle(i);
                step = "stop";
                interval = 20000;
                start();
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

    Component.onCompleted: Qt.callLater(startApp)

    function startApp() {
        settings.launches = settings.launches + 1;
        try {
            sortPrefs = Sorting.normalize(settings.sortPrefs ? JSON.parse(settings.sortPrefs) : null);
        } catch (e) {
            log("preferences de tri illisibles, valeurs par defaut");
        }
        log("demarrage n" + settings.launches + ", ecran " + width + "x" + height + ", compte " + (settings.authKey ? "lie" : "non lie"));
        loadAddons();
    }
}
