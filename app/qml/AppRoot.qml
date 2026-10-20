import QtQuick 2.15
import QtQuick.Window 2.2
import fbx.application 1.0
import "../js/config.js" as Config
import "../js/http.js" as Http
import "../js/theme.js" as T
import "../js/core/addons.js" as Addons
import "../js/core/playback.js" as Playback
import "../js/core/vtt.js" as Vtt
import "../js/core/account.js" as Account
import "../js/core/sorting.js" as Sorting
import "../js/core/resume.js" as Resume
import "../js/core/subsegments.js" as SubSeg
import "../js/core/buffer.js" as Buffer

// Racine de l'appli, chargee depuis l'agent du PC (par le lanceur du Player ou par main.qml).
// Ecrans : accueil, recherche, reglages (barre du haut), fiche, lecteur, compte, tri.
Item {
    id: app

    // Adresse du PC : fournie par le lanceur, sinon tiree de l'URL de chargement.
    property string pcHost: Config.hostFromUrl(Qt.resolvedUrl("."))
    property var pcInfo: null            // derniere reponse de /fbx/api/status
    property bool pcOk: true
    // Services du PC + qualite de conversion choisie dans les reglages.
    readonly property var cfg: {
        const c = Config.settingsFor(pcHost);
        c.maxWidth = settings.maxWidth;
        c.profile = Playback.bestProfile(pcInfo && pcInfo.stremio ? pcInfo.stremio.profiles : [], settings.encoder);
        return c;
    }
    property var probeCache: ({})      // analyses du serveur deja demandees (mediaURL -> Promise)

    property var addons: []
    property string screen: "home"       // home | search | settings | details | player | account | sort
    property string lastTab: "home"
    property string returnScreen: "home"   // ecran a retrouver en quittant le tri ou le compte
    property var sortPrefs: Sorting.normalize(null)
    property string authKey: ""
    property string accountId: ""
    property var positions: ({})
    property var localRows: ({})
    property var catalogCache: ({})
    property var playToken: null
    property var pendingSubtitles: null
    property var subStream: null         // sous-titres integres en cours de chargement par segments
    property var current: null           // fiche ouverte : { type, id, videoId, meta, ... }
    property var client: Addons.createClient(Http.fetchJson)
    // Les analyses (/hlsv2/probe) sont gardees : celle de la meilleure source est demandee
    // a l'avance, pendant que la fiche est affichee.
    readonly property var transport: ({ fetchJson: app.fetchJsonCached, postJson: Http.postJson })

    function fetchJsonCached(url) {
        if (url.indexOf("/hlsv2/probe?") === -1)
            return Http.fetchJson(url);
        if (!probeCache[url]) {
            probeCache[url] = Http.fetchJson(url);
            probeCache[url].catch(() => { delete probeCache[url]; });
        }
        return probeCache[url];
    }

    // Analyse anticipee de la meilleure source (lien direct : debrideur, HTTP).
    function prefetchBest() {
        const top = details.streams[0];
        if (!top || current.prefetched === top.stream)
            return;
        const r = Playback.resolve(top.stream, cfg, seriesInfo());
        if (r.kind !== "media")
            return;
        current.prefetched = top.stream;
        fetchJsonCached(Playback.probeUrl(cfg, r.mediaUrl)).catch(() => {});
    }
    property var account: Account.createAccount(transport)

    function log(msg) {
        console.log("[app] " + msg);
    }

    function toast(msg, kind) {
        toaster.show(msg, kind);
    }

    // ===================== Demarrage, PC, compte =====================

    function startApp() {
        settings.launches = settings.launches + 1;
        try {
            sortPrefs = Sorting.normalize(settings.sortPrefs ? JSON.parse(settings.sortPrefs) : null);
        } catch (e) {
            log("preferences de tri illisibles, valeurs par defaut");
        }
        try {
            positions = settings.positions ? JSON.parse(settings.positions) : {};
        } catch (e) {
            positions = {};
        }
        authKey = settings.authKey || "";
        accountId = settings.accountId || "";
        log("demarrage n" + settings.launches + ", PC " + pcHost + ", compte " + (authKey ? "lie" : "non lie"));
        checkAccount();
        // Verification de chargement du lecteur, sans lecture (developpement).
        if (Config.AUTOTEST && Config.AUTOTEST.loadPlayer) {
            playerLoader.setSource("PlayerPage.qml", { source: "" });
            loadCheck = true;
        }
        // Premier lancement sans compte : proposer tout de suite la liaison.
        if (!authKey && !settings.accountOffered) {
            settings.accountOffered = true;
            Qt.callLater(openAccount);
        }
        // L'agent annonce l'eventuel addon de test : on attend sa reponse avant les addons.
        checkPc().then(loadAddons, loadAddons);
    }

    // Etat de l'agent du PC : nom affiche, Stremio actif, changement de PC.
    function checkPc() {
        if (!pcHost)
            return Promise.resolve();
        return Http.fetchJson(cfg.agent + "/fbx/api/status").then(s => {
            const was = pcOk;
            pcOk = true;
            if (settings.pcId && s.pcId !== settings.pcId)
                toast("Connecte a un autre PC : " + s.pcName);
            else if (!was)
                toast("PC « " + s.pcName + " » de nouveau joignable");
            // Memorise le PC : le lanceur du Player le retrouve au prochain demarrage.
            settings.pcId = s.pcId;
            settings.pcName = s.pcName;
            settings.pcHost = pcHost;
            const stremioWasOk = !pcInfo || pcInfo.stremio.ok;
            pcInfo = s;
            if (!s.stremio.ok && stremioWasOk)
                toast("Stremio ne tourne pas sur « " + s.pcName + " » (Reglages > Demarrer Stremio)", "warn");
            else if (s.stremio.ok && !stremioWasOk)
                toast("Stremio est de nouveau actif");
            refreshSettingsRows();
        }).catch(e => {
            if (pcOk)
                toast("PC injoignable : laissez la fenetre du lanceur ouverte sur le PC", "error");
            pcOk = false;
            refreshSettingsRows();
        });
    }

    // Compte : session toujours valide ? meme compte qu'avant ?
    function checkAccount() {
        if (!authKey) {
            refreshSettingsRows();
            return;
        }
        account.user(authKey).then(u => {
            settings.accountEmail = u.email || "";
            if (accountId && u._id && u._id !== accountId)
                toast("Autre compte Stremio : " + (u.email || u._id));
            accountId = u._id || u.email || "";
            settings.accountId = accountId;
            refreshSettingsRows();
        }).catch(e => {
            if (/Session does not exist/.test(String(e))) {
                toast("Session Stremio expiree : reliez le compte dans Reglages", "warn");
                forgetAccount();
                loadAddons();
            }
        });
    }

    function forgetAccount() {
        settings.authKey = "";
        settings.accountEmail = "";
        authKey = "";
        refreshSettingsRows();
    }

    function startStremioOnPc() {
        toast("Demarrage de Stremio sur le PC…");
        Http.request("POST", cfg.agent + "/fbx/api/start-stremio", {}, false, 90000).then(r => {
            toast(r.message || "Stremio demarre");
            checkPc();
        }).catch(e => toast("Impossible de demarrer Stremio : " + e.message, "error"));
    }

    // Addons et rangees : ceux du compte s'il est lie, sinon ceux par defaut.
    function loadAddons() {
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
                return r[0].map(d => ({ transportUrl: Addons.localToServer(d.transportUrl, cfg.server), manifest: d.manifest }));
            }).catch(e => {
                log("compte inutilisable (" + e + "), addons par defaut");
                return null;
            })
            : Promise.resolve(null);

        fromAccount.then(accountAddons => {
            if (!accountAddons)
                localRows = {};
            const extra = pcInfo && pcInfo.testAddon ? [pcInfo.testAddon] : [];
            const urls = (accountAddons ? [] : Config.DEFAULT_ADDONS).concat(extra);
            return client.loadAddons(urls).then(result => {
                result.errors.forEach(e => log("addon indisponible : " + e.transportUrl + " (" + e.error + ")"));
                return (accountAddons || []).concat(result.addons);
            });
        }).then(list => {
            addons = list;
            const rows = Addons.homeCatalogs(addons);
            log(addons.length + " addons, " + rows.length + " rangees");
            catalogCache = {};
            rowsModel.clear();
            if (!authKey) {
                localRows.link = [{ id: "__link", type: "", name: "Lier mon compte Stremio : bibliotheque, reprise et addons" }];
                rowsModel.append({ kind: "link", transportUrl: "", addonName: "", type: "", cid: "", name: "Votre compte" });
            }
            if ((localRows.continue || []).length)
                rowsModel.append({ kind: "continue", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Continuer a regarder" });
            if ((localRows.library || []).length)
                rowsModel.append({ kind: "library", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Ma bibliotheque" });
            rows.forEach(r => rowsModel.append({ kind: "catalog", transportUrl: r.transportUrl, addonName: r.addonName,
                                                 type: r.type, cid: r.id, name: r.name + " · " + typeLabel(r.type) }));
            if (screen === "home")
                home.forceActiveFocus();
            if (!linksMeasured) {
                linksMeasured = true;
                measureLinks();
            }
            if (Config.AUTOTEST && Config.AUTOTEST.id && !autotestDone) {
                autotestDone = true;
                openMeta(Config.AUTOTEST.type, Config.AUTOTEST.id);
            }
        }).catch(e => log("chargement des addons en echec : " + e));
    }
    property bool autotestDone: false
    property bool linksMeasured: false
    property bool prefetchWaiting: false   // ecran d'attente du prechargement affiche
    property bool loadCheck: false

    // Catalogue d'une rangee, une seule requete par session d'accueil.
    function catalog(ref, extra) {
        const key = ref.transportUrl + "|" + ref.type + "|" + ref.id + "|" + JSON.stringify(extra || {});
        if (!catalogCache[key]) {
            catalogCache[key] = client.catalog(ref, extra);
            catalogCache[key].catch(() => { delete catalogCache[key]; });
        }
        return catalogCache[key];
    }

    function typeLabel(type) {
        return type === "movie" ? "Films" : type === "series" ? "Series" : type === "anime" ? "Anime" : type;
    }

    // ===================== Navigation =====================

    function showTab(index) {
        const tabs = ["home", "search", "settings"];
        screen = tabs[index];
        lastTab = screen;
        if (screen === "home")
            home.forceActiveFocus();
        else if (screen === "search")
            search.focusKeyboard();
        else {
            refreshSettingsRows();
            settingsPage.focusList();
        }
    }

    function back() {
        if (screen === "player") {
            stopPlayer();
        } else if (screen === "sort") {
            if (returnScreen === "details") {
                screen = "details";
                refreshStreams();
                details.forceActiveFocus();
            } else {
                showTab(2);
            }
        } else if (screen === "details") {
            if (!details.back())
                showTab(["home", "search", "settings"].indexOf(lastTab));
        } else if (screen === "account") {
            linkTimer.stop();
            showTab(["home", "search", "settings"].indexOf(returnScreen) === -1 ? 0
                    : ["home", "search", "settings"].indexOf(returnScreen));
        } else if (screen === "search" || screen === "settings") {
            showTab(0);
        } else {
            Qt.quit();
        }
    }

    // ===================== Fiche et flux =====================

    function openMeta(type, id) {
        log("fiche " + type + "/" + id);
        const opened = { type: type, id: id, videoId: null, meta: null, rawStreams: [], streamsProgress: "" };
        current = opened;
        details.meta = null;
        details.episodes = [];
        details.streams = [];
        details.streamsStatus = "";
        details.reset();
        screen = "details";
        details.forceActiveFocus();
        client.meta(addons, type, id).then(meta => {
            if (current !== opened)
                return;
            current.meta = meta;
            details.meta = meta;
            const episodes = [];
            Addons.seasons(meta).forEach(s => s.episodes.forEach(v => episodes.push(v)));
            if (type === "series" && episodes.length) {
                details.episodes = episodes;
                // Reprendre la serie : episode en cours (ou suivant le dernier vu)
                const resumeVideo = Resume.seriesResume(meta, positions, accountId);
                if (resumeVideo)
                    selectEpisode(resumeVideo);
                else if (Config.AUTOTEST && Config.AUTOTEST.episode)
                    selectEpisode(episodes.find(v => v.id === Config.AUTOTEST.episode) || episodes[0]);
            } else {
                loadStreams(type, id);
            }
        }).catch(e => {
            if (current !== opened)
                return;
            log("fiche en echec : " + e);
            details.streamsStatus = "Fiche indisponible (" + e.message + ")";
        });
    }

    function selectEpisode(video) {
        details.selectedTitle = "S" + video.season + " E" + (video.episode || video.number) + "  ·  " + (video.title || video.name || "");
        loadStreams(current.type, video.id);
    }

    function loadStreams(type, videoId) {
        current.videoId = videoId;
        const at = Resume.resumeAt(positions, accountId, videoId);
        details.resumeText = at > 0 ? "Reprendre a " + fmtTime(at) : "";
        details.streams = [];
        details.streamsStatus = "Recherche des sources…";
        const request = {};
        current.streamsRequest = request;
        current.rawStreams = [];
        let answered = 0;
        let items = [];
        client.streams(addons, type, videoId, (g, total) => {
            if (current.streamsRequest !== request)
                return;
            answered++;
            log("flux " + g.addon + " : " + (g.error ? "echec (" + g.error + ")" : g.items.length));
            if (g.items.length) {
                items = items.concat(g.items.map(s => ({ addon: g.addon, stream: s })));
                current.rawStreams = items;
            }
            current.streamsProgress = answered < total ? "  ·  " + answered + "/" + total + " addons" : "";
            refreshStreams();
            const like = current.autoPlayLike;
            if (like && g.addon === like.addon && g.items.length)
                playClosest();
            if (items.length)
                details.focusStreams();
        }).then(() => {
            if (current.streamsRequest !== request)
                return;
            log("flux pour " + videoId + " : " + items.length);
            prefetchBest();
            if (current.autoPlayLike)
                playClosest();
        }).catch(e => log("flux en echec : " + e));
    }

    // Capacites du PC et du reseau, pour ecarter les sources qui ne passeraient pas.
    function streamContext() {
        return {
            capacity: pcInfo ? pcInfo.capacity : null,
            encoderMode: settings.encoder,
            boxLinkMbps: settings.boxLinkMbps,
            boxInternetMbps: settings.boxInternetMbps,
            durationMin: current && current.meta ? Sorting.runtimeMinutes(current.meta.runtime) : 0,
            maxWidth: settings.maxWidth
        };
    }

    function refreshStreams() {
        if (!current)
            return;
        const raw = current.rawStreams || [];
        const r = Sorting.sortStreams(raw, sortPrefs, streamContext());
        details.setStreams(r.visible);
        details.streamsStatus = (r.visible.length ? r.visible.length + " sources" : raw.length ? "Aucune source affichable" : "")
            + (r.hidden ? "  ·  " + r.hidden + " masquees" + (r.heavy ? " (dont " + r.heavy + " trop lourdes pour ce PC/reseau)" : "") : "")
            + (current.streamsProgress || "")
            + (!current.streamsProgress && !raw.length ? "Aucune source trouvee (installez un addon de sources)" : "");
    }

    // Noms des addons qui fournissent des sources (pour leur ordre de priorite).
    function streamAddonNames() {
        return addons.filter(a => Addons.supports(a.manifest, "stream")).map(a => a.manifest.name)
            .filter((n, i, list) => n && list.indexOf(n) === i);
    }

    function openSortSettings() {
        returnScreen = screen;
        screen = "sort";
        sortPage.addonNames = streamAddonNames();
        sortPage.prefs = sortPrefs;
        sortPage.forceActiveFocus();
    }

    function saveSortPrefs(prefs) {
        sortPrefs = prefs;
        settings.sortPrefs = JSON.stringify(prefs);
    }

    // ===================== Lecture =====================

    function seriesInfo() {
        const parts = (current.videoId || "").split(":");
        return parts.length === 3 ? { season: parseInt(parts[1], 10), episode: parseInt(parts[2], 10) } : null;
    }

    function fmtTime(ms) {
        const s = Math.floor(ms / 1000);
        const h = Math.floor(s / 3600);
        const m = Math.floor(s / 60) % 60;
        return (h ? h + ":" + ("0" + m).slice(-2) : m) + ":" + ("0" + (s % 60)).slice(-2);
    }

    // Bouton Lecture : meilleure source selon le tri ; en cas d'echec, les suivantes (3 au plus).
    function playBest() {
        const list = details.streams.slice(0, 3);
        if (!list.length)
            return;
        current.fallbacks = list.slice(1);
        play(list[0]);
    }

    function play(item, forceTranscoding) {
        if (playToken)
            return;
        const token = {};
        playToken = token;
        const opened = current;
        details.streamsStatus = "Preparation de la lecture…";
        log("choix du flux " + item.addon + " : " + (item.badges || item.stream.name || ""));
        const playCfg = Object.assign({}, cfg, { profile: profileFor(item) });
        Playback.plan(item.stream, playCfg, transport, seriesInfo(), forceTranscoding).then(p => {
            playToken = null;
            if (current !== opened || screen !== "details")
                return;
            refreshStreams();
            if (p.kind === "external") {
                App.urlOpen(p.external, "");
                return;
            }
            if (p.kind !== "play") {
                details.streamsStatus = "Source illisible : " + p.reason;
                return;
            }
            const probe = p.probe ? p.probe.streams.map(s => s.track + ":" + s.codec).join(" ") : "probe indisponible";
            log((p.transcoded ? "transcodage par " + (playCfg.profile || "le processeur") : "lecture directe") + " (" + probe + ")");
            const audio = Playback.audioTracks(p.probe);
            const audioIndex = p.transcoded ? Resume.pickAudio(audio, settings.audioLang) : 0;
            const durationMs = p.probe && p.probe.format && p.probe.format.duration > 0 ? p.probe.format.duration * 1000
                : Sorting.runtimeMinutes(current.meta ? current.meta.runtime : "") * 60000;
            const startAtMs = Resume.resumeAt(positions, accountId, current.videoId);
            preparePrefetch(p, durationMs, startAtMs, playCfg, forceTranscoding).then(pf => {
                if (current !== opened || screen !== "details")
                    return;
                startPlayer(item, p, pf, audio, audioIndex);
            });
        }).catch(e => {
            playToken = null;
            log("preparation de la lecture en echec : " + e);
            if (current === opened)
                tryNextSource("lecture impossible : " + e.message);
        });
    }

    // Prechargement par le PC : la source est telechargee par l'agent, Stremio ou la box la lisent
    // depuis son cache. Renvoie { url, mediaUrl, prefetch } (prefetch null si non utilise).
    function preparePrefetch(p, durationMs, startAtMs, playCfg, forceTranscoding) {
        const plain = { url: p.url, mediaUrl: p.mediaUrl, prefetch: null };
        const media = String(p.mediaUrl || "");
        // Sources du PC lui-meme (addon de test) ou du serveur Stremio (torrents, deja en cache) : inutile.
        if (!settings.prefetch || !/^https?:[/][/]/.test(media) || Config.hostFromUrl(media) === pcHost)
            return Promise.resolve(plain);
        const fraction = durationMs > 0 && startAtMs > 0 ? startAtMs / durationMs : 0;
        return Http.request("GET", cfg.agent + "/fbx/prefetch?start=" + fraction.toFixed(4) + "&url="
                            + encodeURIComponent(media), undefined, false, 30000).then(st => {
            const cached = cfg.agent + st.fileUrl;
            log("prechargement par le PC : " + Math.round(st.total / 1048576) + " Mo");
            return {
                url: p.transcoded ? Playback.hlsUrl(playCfg, cached, !!forceTranscoding) : cached,
                mediaUrl: cached,
                prefetch: { id: st.id, durationMs: durationMs, startAtMs: startAtMs, mode: "start",
                            targetS: 0, started: Date.now(), skipUntil: 0 }
            };
        }).catch(e => {
            log("prechargement impossible (" + e.message + "), lecture sans");
            return plain;
        });
    }

    function startPlayer(item, p, pf, audio, audioIndex) {
            const url = audioIndex > 0 ? Playback.withAudio(pf.url, audio[audioIndex].id) : pf.url;
            p.url = pf.url;
            p.mediaUrl = pf.mediaUrl;
            current.playback = p;
            current.playingItem = item;
            pendingSubtitles = null;
            const next = current.type === "series" ? Resume.nextEpisode(current.meta, current.videoId) : null;
            const startAt = Resume.resumeAt(positions, accountId, current.videoId);
            current.prefetch = pf.prefetch;
            prefetchWaiting = !!pf.prefetch;
            playerLoader.setSource("PlayerPage.qml", {
                bufferVisible: !!pf.prefetch,
                bufferTitle: "Prechargement…",
                bufferDetail: "Le PC telecharge la video en avance pour une lecture sans coupure.",
                title: current.meta ? current.meta.name : "",
                subtitleLine: [details.selectedTitle, (item.badges || "").split(" · ").slice(0, 3).join(" · "),
                               p.transcoded ? "converti par le PC" : "lecture directe"].filter(x => x).join("   ·   "),
                // Avec prechargement, la source est donnee au lecteur quand l'avance est suffisante.
                source: pf.prefetch ? "" : url,
                startAt: startAt,
                audioTracks: audio,
                audioIndex: audioIndex,
                audioSwitchable: p.transcoded && audio.length > 1,
                subtitleTracks: [{ label: "Desactives", kind: "off" }],
                startTimeoutMs: p.transcoded ? 60000 : 15000,
                nextTitle: next ? "S" + next.season + " E" + (next.episode || next.number) + "  ·  " + (next.title || next.name || "") : "",
                autoNext: settings.autoNext
            });
            current.nextVideo = next;
            current.nextPrep = null;
            current.playUrl = url;
            screen = "player";
            playerLoader.forceActiveFocus();
            if (startAt > 0)
                toast("Reprise a " + fmtTime(startAt) + "  ·  ◀ pour reculer");
            loadSubtitles(item.stream, p, audio[audioIndex]);
    }

    // Suivi du prechargement : attente au demarrage, pause automatique si l'avance s'epuise.
    function pollPrefetch() {
        const pf = current ? current.prefetch : null;
        const page = playerLoader.item;
        if (!page || screen !== "player")
            return;
        maybePrepareNext(page);
        if (!pf)
            return;
        Http.fetchJson(cfg.agent + "/fbx/prefetch/" + pf.id + "/status").then(st => {
            if (current.prefetch !== pf || playerLoader.item !== page)
                return;
            page.bufferedFrom = st.total ? st.base / st.total : 0;
            page.bufferedTo = st.total ? st.end / st.total : 0;
            if (st.done || st.error)
                startNextPrefetch(current.nextPrep);
            if (st.error) {
                log("prechargement interrompu : " + st.error);
                if (pf.mode !== "play")
                    beginPlayback(page, pf, "lecture sans prechargement");
                current.prefetch = null;
                return;
            }
            const dur = pf.durationMs || page.durationMs;
            const pos = pf.mode === "start" ? pf.startAtMs : page.positionMs;
            const detail = "Telechargement " + (st.rateBps * 8 / 1e6).toFixed(1) + " Mbit/s   ·   video "
                + (Buffer.bytesPerSecond(st.total, dur) * 8 / 1e6).toFixed(1) + " Mbit/s";
            if (pf.mode === "start" || pf.mode === "stall") {
                // Objectif recalcule a chaque mesure de vitesse ; sans mesure (debut du
                // telechargement), on attend jusqu'a 10 s avant de se contenter du minimum.
                if (st.rateBps > 0)
                    pf.targetS = pf.mode === "start" ? Buffer.startTarget(st, dur, pos) : Buffer.resumeTarget(st, dur, pos);
                else if (!pf.targetS && Date.now() - pf.started > 10000)
                    pf.targetS = Buffer.defaultTarget(pf.mode);
                if (!pf.targetS && !st.done) {
                    page.bufferPercent = 0;
                    page.bufferEta = "";
                    page.bufferDetail = "Mesure de la vitesse de telechargement…";
                    return;
                }
                const pr = Buffer.progress(st, dur, pos, pf.targetS);
                page.bufferPercent = pr.percent;
                page.bufferEta = pr.etaS > 0 ? Buffer.formatEta(pr.etaS) : "";
                page.bufferDetail = detail + (pr.tooLong ? "\nAttente longue : la connexion est plus lente que la video. OK pour lancer quand meme." : "");
                if (pr.ready)
                    beginPlayback(page, pf, "");
            } else if (Date.now() > pf.skipUntil && page.positionMs > 0 && Buffer.shouldStall(st, dur, page.positionMs)) {
                pf.mode = "stall";
                prefetchWaiting = true;
                pf.targetS = 0;
                pf.started = Date.now();
                page.pausePlayer();
                page.bufferTitle = "Mise en memoire…";
                page.bufferPercent = 0;
                page.bufferVisible = true;
                log("avance epuisee : pause automatique");
            }
        }).catch(() => {});
    }

    function beginPlayback(page, pf, reason) {
        const wasStart = pf.mode === "start";
        pf.mode = "play";
        prefetchWaiting = false;
        page.bufferVisible = false;
        if (wasStart) {
            page.source = current.playUrl;
            log("lecture apres prechargement (" + Math.round((Date.now() - pf.started) / 1000) + " s)" + (reason ? " : " + reason : ""));
        } else {
            page.resumePlayer();
            log("reprise apres mise en memoire");
        }
    }

    // OK sur l'ecran d'attente : lancer tout de suite, sans pause automatique pendant 1 min.
    function skipBuffering() {
        const pf = current ? current.prefetch : null;
        const page = playerLoader.item;
        if (!pf || !page)
            return;
        pf.skipUntil = Date.now() + 60000;
        beginPlayback(page, pf, "lance par l'utilisateur");
    }

    // Episode suivant : a 4 min de la fin, choix de la source la plus proche et prechargement
    // de son debut. L'enchainement est alors quasi immediat.
    function maybePrepareNext(page) {
        const next = current.nextVideo;
        if (!next || current.nextPrep || !page.durationMs || page.durationMs - page.positionMs > 240000)
            return;
        const prep = { video: next, item: null, list: [] };
        current.nextPrep = prep;
        const opened = current;
        const items = [];
        client.streams(addons, current.type, next.id, g => g.items.forEach(s => items.push({ addon: g.addon, stream: s })))
            .then(() => {
                if (current !== opened)
                    return;
                const ctx = streamContext();
                const visible = Sorting.sortStreams(items, sortPrefs, ctx).visible;
                prep.list = visible;
                prep.item = Sorting.closest(current.playingItem, visible) || visible[0] || null;
                if (!prep.item)
                    return;
                log("episode suivant prepare : " + prep.item.addon + " (" + (prep.item.badges || "") + ")");
                const r = Playback.resolve(prep.item.stream, cfg, { season: next.season, episode: next.episode || next.number });
                if (settings.prefetch && r.kind === "media" && /^https?:[/][/]/.test(r.mediaUrl) && Config.hostFromUrl(r.mediaUrl) !== pcHost) {
                    prep.prefetchUrl = r.mediaUrl;
                    // Pas de concurrence avec le telechargement de l'episode en cours : il attend la fin.
                    if (!current.prefetch)
                        startNextPrefetch(prep);
                }
            }).catch(() => {});
    }

    function startNextPrefetch(prep) {
        if (!prep || !prep.prefetchUrl || prep.prefetchStarted)
            return;
        prep.prefetchStarted = true;
        log("prechargement du debut de l'episode suivant");
        Http.request("GET", cfg.agent + "/fbx/prefetch?maxMb=200&url=" + encodeURIComponent(prep.prefetchUrl),
                     undefined, false, 30000).catch(() => {});
    }

    // Episode suivant : source la plus proche de celle de l'episode precedent
    // (meme addon, meme equipe de sortie, resolution, langues, codec...).
    function playClosest() {
        const prev = current.autoPlayLike;
        current.autoPlayLike = null;
        const pick = Sorting.closest(prev, details.streams);
        if (!pick) {
            toast("Aucune source pour l'episode suivant", "warn");
            return;
        }
        log("episode suivant : source la plus proche " + pick.addon + " (" + (pick.badges || "") + ")");
        current.fallbacks = details.streams.filter(x => x !== pick).slice(0, 2);
        play(pick);
    }

    // Encodeur du PC pour cette source : le plus rapide mesure pour son type de video
    // (la carte graphique echoue par exemple sur le H.264 10 bits avec Stremio).
    function profileFor(item) {
        const info = item.info || Sorting.parse(item.stream);
        const key = Sorting.codecKey(info) || "hevc";
        const cap = pcInfo ? pcInfo.capacity : null;
        if (cap && cap.encoders)
            return Sorting.bestEncoder(cap, key === "h264" ? "hevc" : key, settings.encoder).encoder;
        return key === "h264x10" ? "" : cfg.profile;     // sans mesure : prudence sur le 10 bits
    }

    // Source suivante de la liste (bouton Lecture), ou message d'echec.
    function tryNextSource(reason) {
        const next = (current.fallbacks || []).shift();
        if (next) {
            toast("Source indisponible, essai de la suivante…", "warn");
            play(next);
        } else {
            details.streamsStatus = reason;
            toast(reason, "error");
        }
    }

    function chooseAudio(index) {
        const p = current.playback;
        const track = playerLoader.item.audioTracks[index];
        log("piste audio : " + track.label);
        playerLoader.item.audioIndex = index;
        playerLoader.item.reload(Playback.withAudio(p.url, track.id));
        const lang = (track.language || "").toLowerCase();
        settings.audioLang = /^(fre|fra|fr)$/.test(lang) ? "fr" : /^(eng|en)$/.test(lang) ? "en" : settings.audioLang;
    }

    function loadSubtitles(stream, p, audioTrack) {
        const options = [{ label: "Desactives", kind: "off" }];
        Playback.embeddedSubtitles(p.probe).forEach(s => options.push({
            label: s.label + "  (integre)", kind: "embedded", language: s.language,
            stream: Playback.embeddedSubtitleStream(cfg, p.mediaUrl, p.transcoded ? p.url : "", s)
        }));
        const external = (stream.subtitles || []).map(s => ({ addon: "source", sub: s }));
        client.subtitles(addons, current.type, current.videoId).then(groups => {
            groups.forEach(g => g.items.forEach(s => external.push({ addon: g.addon, sub: s })));
            const rank = x => Playback.isFrench(x.sub.lang) ? 0 : /^(eng|en)$/i.test(x.sub.lang || "") ? 1 : 2;
            external.sort((a, b) => rank(a) - rank(b)).slice(0, 40).forEach(x => options.push({
                label: (Playback.languageName(x.sub.lang) || "?") + "  ·  " + x.addon, kind: "external",
                language: x.sub.lang, url: Playback.subtitlesVttUrl(cfg, x.sub.url)
            }));
        }).catch(e => log("sous-titres des addons en echec : " + e)).then(() => {
            pendingSubtitles = { options: options,
                                 first: Resume.pickSubtitle(options, settings.subLang, audioTrack ? audioTrack.language : "") };
            applySubtitles();
        }).catch(e => log("sous-titres : erreur " + e));
    }

    function applySubtitles() {
        const page = playerLoader.item;
        if (!page || !pendingSubtitles)
            return;
        const pending = pendingSubtitles;
        pendingSubtitles = null;
        page.subtitleTracks = pending.options;
        if (pending.first > 0)
            chooseSubtitle(pending.first, true);
    }

    function chooseSubtitle(index, automatic) {
        const page = playerLoader.item;
        const option = page.subtitleTracks[index];
        page.subtitleIndex = index;
        page.cues = [];
        page.subDelay = 0;                 // autre fichier de sous-titres : autre decalage
        if (!automatic) {
            const lang = (option.language || "").toLowerCase();
            settings.subLang = option.kind === "off" ? "off" : /^(fre|fra|fr)$/.test(lang) ? "fr"
                             : /^(eng|en)$/.test(lang) ? "en" : settings.subLang;
        }
        subStream = null;
        if (option.kind === "off")
            return;
        if (option.kind === "embedded") {
            startSegmentedSubtitles(page, option, index);
            return;
        }
        log("sous-titres " + option.label + " : chargement");
        Http.fetchText(option.url, 60000).then(text => {
            if (playerLoader.item !== page || page.subtitleIndex !== index)
                return;
            page.cues = Vtt.parse(text);
            log("sous-titres " + option.label + " : " + page.cues.length + " lignes");
            if (!page.cues.length)
                toast("Ce fichier de sous-titres est vide ou illisible, essayez-en un autre", "warn");
        }).catch(e => {
            log("sous-titres " + option.label + " en echec : " + e.message);
            if (playerLoader.item === page && page.subtitleIndex === index)
                toast("Sous-titres indisponibles (" + e.message + "), essayez-en un autre", "warn");
        });
    }

    // Sous-titres integres : segments de quelques secondes autour de la position de lecture,
    // comme un lecteur HLS (extraire toute la piste obligerait le PC a lire tout le fichier).
    function startSegmentedSubtitles(page, option, index) {
        const s = { page: page, index: index, segments: [], done: {}, busy: 0, failures: 0, shown: false,
                    retryAt: {}, lastCueAt: Date.now(), warned: false };
        subStream = s;
        log("sous-titres " + option.label + " : segments");
        const ready = option.stream.needsMaster ? Http.fetchText(option.stream.master, 60000) : Promise.resolve();
        ready.then(() => Http.fetchText(option.stream.playlist, 60000)).then(text => {
            if (subStream !== s)
                return;
            s.segments = SubSeg.parsePlaylist(text, option.stream.playlist);
            log("sous-titres integres : " + s.segments.length + " segments");
            if (!s.segments.length)
                toast("Piste de sous-titres vide", "warn");
            pumpSubtitles();
        }).catch(e => {
            log("sous-titres integres en echec : " + e.message);
            if (subStream === s)
                toast("Sous-titres integres indisponibles (" + e.message + ")", "warn");
        });
    }

    // Charge les segments utiles (3 a la fois) ; rappele regulierement et apres chaque segment.
    function pumpSubtitles() {
        const s = subStream;
        if (!s || !s.segments.length || playerLoader.item !== s.page || s.page.subtitleIndex !== s.index)
            return;
        const position = Math.max(0, s.page.positionMs - s.page.subDelay);
        const now = Date.now();
        SubSeg.needed(s.segments, position, s.done).filter(i => !(s.retryAt[i] > now))
            .slice(0, Math.max(0, 3 - s.busy)).forEach(i => {
            s.done[i] = true;
            s.busy++;
            Http.fetchText(s.segments[i].url, 45000).then(text => {
                s.busy--;
                if (subStream !== s || playerLoader.item !== s.page)
                    return;
                const cues = Vtt.parse(text);
                s.tries = s.tries || {};
                delete s.tries[i];
                s.lastCueAt = Date.now();
                if (cues.length) {
                    s.page.cues = SubSeg.merge(s.page.cues, cues);
                    if (!s.shown) {
                        s.shown = true;
                        log("sous-titres integres : premiers sous-titres recus");
                    }
                }
                pumpSubtitles();
            }).catch(e => {
                s.busy--;
                delete s.done[i];
                // Nouvel essai avec un delai croissant (2, 4, 8... 30 s) : le serveur refuse
                // temporairement des segments quand il est occupe a convertir la video.
                s.tries = s.tries || {};
                s.tries[i] = (s.tries[i] || 0) + 1;
                s.retryAt[i] = Date.now() + Math.min(30000, 1000 * Math.pow(2, s.tries[i]));
                s.failures++;
                log("segment de sous-titres " + i + " en echec (" + s.tries[i] + ") : " + e.message);
                // Alerte seulement si plus rien n'arrive depuis 30 s.
                if (!s.warned && subStream === s && Date.now() - s.lastCueAt > 30000) {
                    s.warned = true;
                    toast("Les sous-titres integres arrivent mal, le PC est peut-etre occupe", "warn");
                }
            });
        });
    }

    // Position de reprise : enregistree regulierement et a l'arret.
    function savePosition() {
        const page = playerLoader.item;
        if (!page || !current || !current.videoId || page.positionMs <= 0)
            return;
        positions = Resume.record(positions, accountId, current.videoId, page.positionMs, page.durationMs, Date.now());
        settings.positions = JSON.stringify(positions);
    }

    function playbackFailed(reason) {
        const p = current.playback;
        log("echec de lecture (" + reason + ")");
        Qt.callLater(() => {
            stopPlayer();
            if (p && !p.transcoded && current.playingItem)
                play(current.playingItem, true);       // direct impossible : conversion par le PC
            else
                tryNextSource("Lecture impossible : " + reason);
        });
    }

    function playNext() {
        const next = current.nextVideo;
        const previous = current.playingItem;
        savePosition();
        stopPlayer();
        if (!next)
            return;
        const prep = current.nextPrep;
        selectEpisode(next);
        if (prep && prep.video === next && prep.item) {
            // Source choisie et prechargee pendant l'episode precedent : on lance tout de suite.
            current.fallbacks = prep.list.filter(x => x !== prep.item).slice(0, 2);
            toast("Episode suivant : S" + next.season + " E" + (next.episode || next.number));
            play(prep.item);
            return;
        }
        // Des que l'addon de l'episode precedent repond : la source qui lui ressemble le plus.
        current.autoPlayLike = !previous ? null
            : previous.info ? previous : (Sorting.sortStreams([previous], sortPrefs).visible[0] || null);
        toast("Episode suivant : S" + next.season + " E" + (next.episode || next.number));
    }

    function stopPlayer() {
        subStream = null;
        savePosition();
        if (playerLoader.item)
            playerLoader.item.stop();
        playerLoader.source = "";
        screen = "details";
        details.forceActiveFocus();
        // Barres de progression a jour
        details.progressOf = null;
        details.progressOf = videoProgress;
    }

    function videoProgress(videoId) {
        return Resume.progress(positions, accountId, videoId);
    }

    function metaProgress(meta) {
        return meta.progress || Resume.progress(positions, accountId, meta.videoId || meta.id);
    }

    // ===================== Recherche =====================

    function runSearch(text) {
        const refs = Addons.searchCatalogs(addons);
        search.status = "Recherche…";
        const token = {};
        search.token = token;
        Promise.all(refs.map(ref => client.catalog(ref, { search: text })
            .then(metas => ({ title: ref.name + " · " + typeLabel(ref.type), metas: metas }), () => null)))
            .then(groups => {
                if (search.token !== token)
                    return;
                search.results = groups.filter(g => g && g.metas.length);
                search.status = search.results.length ? "" : "Aucun resultat pour « " + text + " »";
            });
    }

    // ===================== Compte =====================

    function openAccount() {
        if (screen !== "account")
            returnScreen = screen;
        screen = "account";
        accountPage.forceActiveFocus();
        accountPage.status = "";
        if (authKey) {
            accountPage.email = settings.accountEmail || "compte lie";
        } else {
            accountPage.email = "";
            startLink();
        }
    }

    function startLink() {
        linkTimer.stop();
        accountPage.code = "";
        accountPage.status = "Creation du code…";
        account.createLink().then(l => {
            accountPage.code = l.code;
            accountPage.link = l.link;
            accountPage.qrcode = l.qrcode;
            accountPage.status = "En attente de validation  ·  OK : nouveau code";
            log("code de liaison " + l.code);
            const code = l.code;
            return Account.pollLink(account, code, (fn, ms) => {
                if (screen !== "account" || accountPage.code !== code)
                    return;
                linkTimer.callback = fn;
                linkTimer.interval = ms;
                linkTimer.start();
            }, 3000, 100).then(key => {
                settings.authKey = key;
                authKey = key;
                toast("Compte Stremio lie");
                checkAccount();
                showTab(0);
                loadAddons();
            });
        }).catch(e => accountPage.status = "Erreur : " + e.message);
    }

    function unlink() {
        forgetAccount();
        toast("Compte delie de ce Player");
        showTab(0);
        loadAddons();
    }

    // ===================== Reglages =====================

    function choice(list, value, step) {
        const i = list.indexOf(value);
        return list[((i === -1 ? 0 : i) + step + list.length) % list.length];
    }

    function refreshSettingsRows() {
        const pc = pcInfo;
        const langs = { auto: "Automatique", fr: "Francais", en: "Anglais", vo: "Version originale", off: "Desactives" };
        settingsPage.setRows([
            { section: "PC connecte", key: "pcName", label: "Nom", value: pc ? pc.pcName : "—", action: "info" },
            { section: "PC connecte", key: "pcIp", label: "Adresse", value: pcHost || "—", action: "info" },
            { section: "PC connecte", key: "pcState", label: "Etat", action: "info",
              value: !pcOk ? "Injoignable (lancer Lancer-Stremio-Freebox sur le PC)" : pc ? (pc.stremio.ok ? "Stremio " + pc.stremio.version + " actif" : "Stremio arrete") : "…",
              tone: pcOk && pc && pc.stremio.ok ? "ok" : "bad" },
            { section: "PC connecte", key: "startStremio", label: "Demarrer Stremio sur le PC", value: "Demarrer", action: "button" },
            { section: "PC connecte", key: "recheck", label: "Verifier la connexion", value: "Verifier", action: "button" },
            { section: "Compte Stremio", key: "account", label: authKey ? (settings.accountEmail || "Compte lie") : "Aucun compte lie",
              value: authKey ? "Gerer" : "Lier un compte", action: "button" },
            { section: "Lecture", key: "audioLang", label: "Langue audio preferee", value: langs[settings.audioLang] || settings.audioLang, action: "choice" },
            { section: "Lecture", key: "subLang", label: "Sous-titres par defaut", value: settings.subLang === "auto" ? "Francais si audio etranger" : langs[settings.subLang], action: "choice" },
            { section: "Lecture", key: "autoNext", label: "Enchainer l'episode suivant", value: settings.autoNext ? "Oui" : "Non", action: "choice" },
            { section: "Lecture", key: "quality", label: "Qualite en conversion par le PC", value: settings.maxWidth >= 1920 ? "1080p (reseau rapide)" : "720p (recommande)", action: "choice" },
            { section: "Lecture", key: "encoder", label: "Conversion sur le PC", action: "choice",
              value: settings.encoder === "cpu" ? "Processeur (lent)"
                     : cfg.profile ? "Carte graphique (" + cfg.profile + ")" : "Processeur (aucune carte detectee)" },
            { section: "Lecture", key: "prefetch", label: "Prechargement par le PC (anti-coupures)", action: "choice",
              value: settings.prefetch ? "Oui" : "Non" },
            { section: "Lecture", key: "sort", label: "Tri des sources", value: "Ouvrir", action: "button" },
            { section: "Lecture", key: "clearPositions", label: "Oublier les positions de lecture", value: "Effacer", action: "button" },
            { section: "A propos", key: "version", label: "Version", action: "info",
              value: "appli " + (pc ? pc.appVersion : "?") + "  ·  agent " + (pc ? pc.agentVersion : "?") },
            { section: "Capacites", key: "capConvert", label: "Conversion par le PC (HEVC 1080p)", action: "info",
              value: capacityText() },
            { section: "Capacites", key: "capPcNet", label: "Internet vers le PC", action: "info",
              value: pc && pc.capacity && pc.capacity.pcInternetMbps ? pc.capacity.pcInternetMbps + " Mbit/s" : "non mesure" },
            { section: "Capacites", key: "capLink", label: "PC vers le Player", action: "info",
              value: settings.boxLinkMbps ? settings.boxLinkMbps + " Mbit/s" : "non mesure" },
            { section: "Capacites", key: "capBoxNet", label: "Internet vers le Player", action: "info",
              value: settings.boxInternetMbps ? settings.boxInternetMbps + " Mbit/s" : "non mesure" },
            { section: "Capacites", key: "speed", label: "Mesurer les debits du Player", value: measuring ? "mesure…" : "Mesurer", action: "button" }
        ]);
    }
    function capacityText() {
        const cap = pcInfo ? pcInfo.capacity : null;
        if (!cap || !cap.encoders)
            return "non mesuree (relancer le lanceur du PC)";
        const best = Sorting.bestEncoder(cap, "hevc", settings.encoder);
        return best.factor.toFixed(1) + "x le temps reel" + (best.encoder ? " (" + best.encoder + ")" : " (processeur)")
            + "  ·  mesure du " + Qt.formatDate(new Date(cap.measuredAt * 1000), "dd/MM");
    }

    function settingAction(key, step) {
        switch (key) {
        case "startStremio": startStremioOnPc(); break;
        case "recheck": checkPc(); toast("Verification…"); break;
        case "account": openAccount(); return;
        case "audioLang": settings.audioLang = choice(["auto", "fr", "en", "vo"], settings.audioLang, step || 1); break;
        case "subLang": settings.subLang = choice(["auto", "fr", "en", "off"], settings.subLang, step || 1); break;
        case "autoNext": settings.autoNext = !settings.autoNext; break;
        case "quality": settings.maxWidth = settings.maxWidth >= 1920 ? 1280 : 1920; break;
        case "encoder": settings.encoder = settings.encoder === "cpu" ? "auto" : "cpu"; break;
        case "prefetch": settings.prefetch = !settings.prefetch; break;
        case "sort": openSortSettings(); return;
        case "clearPositions":
            positions = {};
            settings.positions = "{}";
            toast("Positions de lecture effacees");
            break;
        case "speed": measureLinks(); break;
        }
        refreshSettingsRows();
    }

    // Telecharge url et renvoie le debit en Mbit/s (0 si echec).
    function downloadMbps(url) {
        return new Promise(resolve => {
            const start = Date.now();
            const xhr = new XMLHttpRequest();
            xhr.responseType = "arraybuffer";
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                const got = xhr.status === 200 && xhr.response ? xhr.response.byteLength : 0;
                resolve(got ? got * 8 / 1000 / Math.max(1, Date.now() - start) : 0);
            };
            xhr.open("GET", url);
            xhr.send();
        });
    }

    // Debits vus par la box : depuis le PC (sources converties) et depuis Internet (lecture
    // directe). Mesures au demarrage, hors lecture, puis utilisees par le tri.
    function measureLinks() {
        if (measuring || screen === "player")
            return;
        measuring = true;
        refreshSettingsRows();
        const t = Date.now();
        downloadMbps(cfg.agent + "/fbx/api/speedtest?bytes=" + (4 * 1024 * 1024) + "&t=" + t).then(link => {
            if (link > 0)
                settings.boxLinkMbps = Math.round(link * 10) / 10;
            return downloadMbps("https://speed.cloudflare.com/__down?bytes=4000000&t=" + t);
        }).then(net => {
            if (net > 0)
                settings.boxInternetMbps = Math.round(net * 10) / 10;
            measuring = false;
            log("debits : PC -> box " + settings.boxLinkMbps + " Mbit/s, Internet -> box " + settings.boxInternetMbps + " Mbit/s");
            refreshSettingsRows();
            refreshStreams();
        });
    }
    property bool measuring: false

    // ===================== Interface =====================

    Settings {
        id: settings
        property string authKey: ""
        property string accountId: ""
        property string accountEmail: ""
        property int launches: 0
        property string sortPrefs: ""
        property string positions: "{}"
        property string audioLang: "auto"
        property string subLang: "auto"
        property bool autoNext: true
        property int maxWidth: 1280
        property string encoder: "auto"   // auto : carte graphique si disponible ; cpu : processeur
        property bool prefetch: true       // prechargement par le PC
        property real boxLinkMbps: 0       // debit PC -> Player mesure
        property real boxInternetMbps: 0   // debit Internet -> Player mesure
        // PC utilise (lu aussi par le lanceur du Player, bootstrap/main.qml)
        property string pcHost: ""
        property string pcId: ""
        property string pcName: ""
        property bool accountOffered: false
    }

    ListModel { id: rowsModel }

    Timer {
        // Surveillance du PC : nom, Stremio, coupure.
        interval: 30000
        repeat: true
        running: true
        onTriggered: checkPc()
    }

    Timer {
        // Position de reprise toutes les 15 s pendant la lecture.
        interval: 15000
        repeat: true
        running: app.screen === "player"
        onTriggered: savePosition()
    }

    Timer {
        // Prechargement : 1 s pendant l'attente, 3 s pendant la lecture.
        interval: app.prefetchWaiting ? 1000 : 3000
        repeat: true
        running: app.screen === "player"
        onTriggered: app.pollPrefetch()
    }

    Timer {
        // Sous-titres integres : suit la position (lecture, sauts avant/arriere).
        interval: 2000
        repeat: true
        running: app.subStream !== null && app.screen === "player"
        onTriggered: app.pumpSubtitles()
    }

    Timer {
        id: linkTimer
        property var callback: null
        onTriggered: if (callback) callback()
    }

    FocusScope {
        id: root
        anchors.fill: parent
        focus: true

        Rectangle {
            anchors.fill: parent
            color: T.bg
        }

        HomePage {
            id: home
            objectName: "accueil"
            anchors.fill: parent
            visible: app.screen === "home"
            focus: true
            model: rowsModel
            loadCatalog: app.catalog
            localRows: app.localRows
            companion: app.cfg.companion
            progressOf: app.metaProgress
            onActivated: meta.id === "__link" ? app.openAccount() : app.openMeta(meta.type || fallbackType, meta.id)
            onUp: topBar.forceActiveFocus()
        }

        SearchPage {
            id: search
            objectName: "recherche"
            property var token: null
            anchors.fill: parent
            visible: app.screen === "search"
            companion: app.cfg.companion
            progressOf: app.metaProgress
            onSearch: app.runSearch(text)
            onActivated: app.openMeta(meta.type, meta.id)
            onUp: topBar.forceActiveFocus()
        }

        SettingsPage {
            id: settingsPage
            objectName: "reglages"
            anchors.fill: parent
            visible: app.screen === "settings"
            onActivated: app.settingAction(key, step)
            onUp: topBar.forceActiveFocus()
        }

        TopBar {
            id: topBar
            objectName: "barre"
            anchors { left: parent.left; right: parent.right; top: parent.top }
            visible: app.screen === "home" || app.screen === "search" || app.screen === "settings"
            current: ["home", "search", "settings"].indexOf(app.screen)
            pcName: app.pcInfo ? app.pcInfo.pcName : app.pcHost
            pcOk: app.pcOk
            account: app.authKey ? (settings.accountEmail || "C") : ""
            onTabChosen: app.showTab(index)
            onLeave: app.showTab(current)
        }

        DetailsPage {
            id: details
            objectName: "fiche"
            anchors.fill: parent
            visible: app.screen === "details"
            progressOf: app.videoProgress
            onEpisodeChosen: app.selectEpisode(video)
            onStreamChosen: { app.current.fallbacks = []; app.play(item); }
            onPlayBest: app.playBest()
            onSortRequested: app.openSortSettings()
        }

        SortSettingsPage {
            id: sortPage
            objectName: "tri"
            anchors.fill: parent
            visible: app.screen === "sort"
            onChanged: app.saveSortPrefs(prefs)
        }

        AccountPage {
            id: accountPage
            objectName: "compte"
            anchors.fill: parent
            visible: app.screen === "account"
            onNewCode: app.startLink()
            onUnlink: app.unlink()
        }

        Loader {
            id: playerLoader
            objectName: "lecteur"
            anchors.fill: parent
            visible: app.screen === "player"
            onLoaded: {
                if (app.loadCheck) {
                    app.loadCheck = false;
                    app.log("verification : lecteur charge sans erreur");
                    Qt.callLater(() => { playerLoader.source = ""; });
                    return;
                }
                item.logMessage.connect(app.log);
                item.finished.connect(() => Qt.callLater(app.stopPlayer));
                item.failed.connect(app.playbackFailed);
                item.audioChosen.connect(app.chooseAudio);
                item.subtitleChosen.connect(index => app.chooseSubtitle(index, false));
                item.nextRequested.connect(() => Qt.callLater(app.playNext));
                item.skipBuffering.connect(app.skipBuffering);
                app.applySubtitles();
            }
        }

        Toast {
            id: toaster
        }

        Keys.onPressed: {
            if (event.key === Qt.Key_Back || event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                event.accepted = true;
                app.back();
            } else if (event.key === Qt.Key_Menu && app.screen === "details") {
                event.accepted = true;
                app.openSortSettings();
            } else if (event.key === Qt.Key_Menu && (app.screen === "home" || app.screen === "search")) {
                event.accepted = true;
                app.showTab(2);
            } else if (event.key === Qt.Key_Search) {
                event.accepted = true;
                app.showTab(1);
            }
        }
    }

    // Diagnostic : element sous le focus (noms des parents + position dans les listes).
    function describeFocus(item) {
        const names = [];
        for (let it = item; it; it = it.parent) {
            if (it.objectName)
                names.unshift(it.objectName + (it.currentIndex !== undefined ? "[" + it.currentIndex + "]" : ""));
        }
        return names.join(" > ") || String(item);
    }

    Connections {
        target: Config.DEBUG_FOCUS ? app.Window.window : null
        function onActiveFocusItemChanged() {
            const w = app.Window.window;
            if (w && w.activeFocusItem)
                app.log("focus : " + app.screen + " | " + app.describeFocus(w.activeFocusItem));
        }
    }

    Component.onCompleted: Qt.callLater(startApp)
}
