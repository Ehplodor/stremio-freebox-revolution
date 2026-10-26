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
import "../js/core/library.js" as Library
import "../js/core/mkv.js" as Mkv
import "../js/core/discover.js" as Discover
import "../js/core/tmdb.js" as Tmdb
import "../js/core/lzstring.js" as LZ

// Racine de l'appli, embarquee dans le paquet FreeStore (main.qml) ; aussi chargeable depuis
// l'agent du PC (lanceur bootstrap/, developpement).
// Ecrans : accueil, recherche, reglages (barre du haut), fiche, lecteur, compte, tri.
// Le PC est facultatif : sans lui, lecture directe des liens HTTP H.264 (debrideurs, addons HTTP).
Item {
    id: app

    // Adresse du PC : tiree de l'URL de chargement (lanceur, developpement), sinon celle
    // memorisee. pcHost : PC essaye en dernier ; vide si aucun PC connu.
    property string launchHost: Config.hostFromUrl(Qt.resolvedUrl("."))
    property string pcHost: ""
    property var pcInfo: null            // derniere reponse de /fbx/api/status
    property bool pcOk: false
    // PC joignable et utilise : sinon tous les services du PC sont vides (lecture directe).
    readonly property bool pcActive: pcOk && pcInfo !== null && pcHost !== "" && settings.pcMode !== "off"
    property var modules: []             // sonde des modules de la box : [{ name, ok, error }]
    // Services du PC + qualite de conversion choisie dans les reglages.
    readonly property var cfg: {
        const c = Config.settingsFor(pcActive ? pcHost : "");
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
        if (!top || current.probed === top.stream)
            return;
        const r = Playback.resolve(top.stream, cfg, seriesInfo());
        if (r.kind !== "media")
            return;
        current.probed = top.stream;
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
            log("préférences de tri illisibles, valeurs par défaut");
        }
        try {
            positions = settings.positions ? JSON.parse(settings.positions) : {};
        } catch (e) {
            positions = {};
        }
        authKey = settings.authKey || "";
        accountId = settings.accountId || "";
        log("démarrage n" + settings.launches + ", PC " + (pcCandidate() || "aucun")
            + ", compte " + (authKey ? "lie" : "non lié"));
        readVersion();
        probeModules();
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
        // Aucun ecran n'attend le PC : addons tout de suite, le PC est verifie en parallele
        // (son eventuel addon de test recharge les addons quand il repond).
        loadAddons();
        // PC verifie apres le premier affichage : une adresse eteinte ne doit rien retarder.
        if (pcCandidate()) {
            pcTimer.interval = 8000;
            pcTimer.start();
        }
    }

    property string appVersion: "?"
    // Version de l'appli lue dans son manifest (embarque dans le paquet ou servi par le PC).
    function readVersion() {
        Http.fetchJson(Qt.resolvedUrl("../manifest.json")).then(m => {
            appVersion = m && m.version ? m.version : "?";
            refreshSettingsRows();
        }).catch(() => {});
    }

    // PC a essayer : lanceur / developpement, sinon adresse memorisee.
    function pcCandidate() {
        return settings.pcMode === "off" || Config.NO_PC ? "" : (Config.PC_OVERRIDE || launchHost || settings.pcHost || "");
    }

    // Etat de l'agent du PC : nom affiche, Stremio actif, changement de PC. Delai court :
    // une adresse sans machine ne repond jamais.
    function checkPc() {
        const host = pcCandidate();
        if (!host)
            pcTimer.stop();
        else if (!pcTimer.running)
            pcTimer.start();
        if (!host) {
            pcHost = "";
            pcOk = false;
            pcInfo = null;
            refreshSettingsRows();
            refreshStreams();
            return Promise.resolve();
        }
        return Http.request("GET", Config.settingsFor(host).agent + "/fbx/api/status", undefined, false, 2500).then(s => {
            pcFailures = 0;
            pcTimer.interval = 30000;
            if (!s || s.agent !== "stremio-fbx")
                throw new Error("pas un agent Revo Stream");
            const was = pcActive;
            const hadTestAddon = !!(pcInfo && pcInfo.testAddon);
            if (settings.pcId && s.pcId !== settings.pcId)
                toast("Connecté à un autre PC : " + s.pcName);
            else if (!was && pcHost)
                toast("PC « " + s.pcName + " » joignable : conversion et torrents disponibles");
            // Memorise le PC : retrouve au prochain demarrage.
            settings.pcId = s.pcId;
            settings.pcName = s.pcName;
            settings.pcHost = host;
            const stremioWasOk = !pcInfo || pcInfo.stremio.ok;
            pcHost = host;
            pcInfo = s;
            pcOk = true;
            if (!s.stremio.ok && stremioWasOk)
                toast("Stremio ne tourne pas sur « " + s.pcName + " » (Réglages > Démarrer Stremio)", "warn");
            else if (s.stremio.ok && !stremioWasOk)
                toast("Stremio est de nouveau actif");
            if (s.testAddon && !hadTestAddon)
                loadAddons();
            sendModulesToPc();
            refreshSettingsRows();
            refreshStreams();
        }).catch(e => {
            if (pcActive)
                toast("PC injoignable : lecture directe seulement", "warn");
            // PC eteint : essais de plus en plus espaces (1, 2, 4... 15 min).
            pcFailures++;
            pcTimer.interval = Math.min(15 * 60000, 60000 * Math.pow(2, pcFailures - 1));
            pcHost = host;
            pcOk = false;
            refreshSettingsRows();
            refreshStreams();
        });
    }

    // ===================== Sonde des modules de la box =====================

    // Modules reserves (fbx.media, fbx.os.mms : lecteur natif, pistes audio) : absents en mode
    // developpeur, peut-etre accordes a l'appli installee depuis le FreeStore.
    readonly property var probedModules: [
        "fbx.media 1.0", "fbx.os.mms 1.0", "fbx.cdm 1.0", "fbx.web 1.0", "fbx.ui.dialog 1.0",
        "fbx.ui.menu 1.0", "fbx.inapp 1.0", "QtMultimedia 5.15", "QtQuick.LocalStorage 2.0"
    ]

    function tryCreate(imports, body) {
        try {
            const o = Qt.createQmlObject("import QtQuick 2.15\n" + imports + "\n" + body + " {}", app, "sonde");
            o.destroy();
            return "";
        } catch (e) {
            return e.qmlErrors && e.qmlErrors.length ? e.qmlErrors[0].message : String(e);
        }
    }

    function probeModules() {
        const result = probedModules.map(m => {
            const err = tryCreate("import " + m, "Item");
            return { name: m, ok: !err, error: err };
        });
        // Types utiles de fbx.media (lecteur natif avec pistes audio et sous-titres).
        if (result[0].ok) {
            ["VideoPlayer", "PlayerTimeline"].forEach(t => {
                const err = tryCreate("import fbx.media 1.0", t);
                result.push({ name: "fbx.media." + t, ok: !err, error: err });
            });
        }
        modules = result;
        log("modules : " + result.map(r => r.name + (r.ok ? " ok" : " absent")).join(", "));
        result.filter(r => !r.ok).forEach(r => log("  " + r.name + " : " + r.error));
        refreshSettingsRows();
    }

    // Journal du PC (s'il est la) : resultat de la sonde, une fois par lancement.
    property bool modulesSent: false
    function sendModulesToPc() {
        if (modulesSent || !pcActive || !modules.length)
            return;
        modulesSent = true;
        Http.postJson(cfg.agent + "/fbx/api/log", {
            source: "Revo Stream " + appVersion + (launchHost ? " (chargée depuis le PC)" : " (installée)"),
            modules: modules
        }).catch(() => { modulesSent = false; });
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
                toast("Session Stremio expirée : reliez le compte dans Réglages", "warn");
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
        toast("Démarrage de Stremio sur le PC…");
        Http.request("POST", cfg.agent + "/fbx/api/start-stremio", {}, false, 90000).then(r => {
            toast(r.message || "Stremio démarre");
            checkPc();
        }).catch(e => toast("Impossible de démarrer Stremio : " + e.message, "error"));
    }

    // Addons et rangees : ceux du compte s'il est lie, sinon ceux par defaut.
    function loadAddons() {
        const fromAccount = authKey
            ? Promise.all([account.addons(authKey), account.libraryItems(authKey).catch(e => {
                log("bibliothèque indisponible : " + e);
                return [];
            })]).then(r => {
                log("compte : " + r[0].length + " addons, " + r[1].length + " éléments de bibliothèque");
                libraryItems = r[1];
                localRows = libraryRows();
                // Addon local de Stremio Desktop : seulement via le serveur du PC.
                return r[0].filter(d => cfg.server || !Addons.isLocalAddon(d.transportUrl))
                    .map(d => ({ transportUrl: Addons.localToServer(d.transportUrl, cfg.server), manifest: d.manifest }));
            }).catch(e => {
                log("compte inutilisable (" + e + "), addons par défaut");
                return null;
            })
            : Promise.resolve(null);

        fromAccount.then(accountAddons => {
            if (!accountAddons) {
                libraryItems = localLibrary();
                localRows = libraryRows();
            }
            const extra = pcActive && pcInfo.testAddon ? [pcInfo.testAddon] : [];
            const urls = (accountAddons ? [] : Config.DEFAULT_ADDONS).concat(extra);
            return client.loadAddons(urls).then(result => {
                result.errors.forEach(e => log("addon indisponible : " + e.transportUrl + " (" + e.error + ")"));
                return (accountAddons || []).concat(result.addons);
            });
        }).then(list => {
            addons = list;
            const rows = Addons.homeCatalogs(addons);
            if (!perf.addonsMs)
                perf.addonsMs = Date.now() - perf.startedAt;
            log(addons.length + " addons, " + rows.length + " rangées en " + fmtSeconds(Date.now() - perf.startedAt)
                + " : " + addons.map(a => a.manifest.name).join(", "));
            catalogCache = {};
            rowsModel.clear();
            if (!authKey) {
                localRows.link = [{ id: "__link", type: "", name: "Lier mon compte Stremio : bibliothèque, reprise et addons" }];
                rowsModel.append({ kind: "link", transportUrl: "", addonName: "", type: "", cid: "", name: "Votre compte", skip: false });
            }
            if ((localRows.continue || []).length)
                rowsModel.append({ kind: "continue", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Continuer à regarder", skip: false });
            if ((localRows.library || []).length)
                rowsModel.append({ kind: "library", transportUrl: "", addonName: "Compte", type: "", cid: "", name: "Ma bibliothèque", skip: false });
            rows.forEach(r => rowsModel.append({ kind: "catalog", transportUrl: r.transportUrl, addonName: r.addonName,
                                                 type: r.type, cid: r.id, name: r.name + " · " + typeLabel(r.type) , skip: !!r.skip}));
            if (screen === "home")
                home.forceActiveFocus();
            if (!linksMeasured) {
                // Plus tard : les 8 Mo de la mesure ralentiraient le chargement des affiches.
                linksMeasured = true;
                measureDelay.start();
            }
            if (Config.AUTOTEST && Config.AUTOTEST.id && !autotestDone) {
                autotestDone = true;
                openMeta(Config.AUTOTEST.type, Config.AUTOTEST.id);
            }
        }).catch(e => log("chargement des addons en échec : " + e));
    }
    property bool autotestDone: false
    property bool linksMeasured: false
    property bool prefetchWaiting: false   // ecran d'attente du prechargement affiche
    property bool loadCheck: false

    // Catalogue d'une rangee, une seule requete par session d'accueil.
    function catalog(ref, extra) {
        const key = ref.transportUrl + "|" + ref.type + "|" + ref.id + "|" + JSON.stringify(extra || {});
        if (!catalogCache[key]) {
            const t0 = Date.now();
            catalogCache[key] = client.catalog(ref, extra);
            if (!extra)
                catalogCache[key].then(() => {
                    perf.catalogs.push({ name: ref.addonName || ref.name, ms: Date.now() - t0 });
                }, () => {
                    perf.catalogs.push({ name: (ref.addonName || ref.name) + ", échec", ms: Date.now() - t0 });
                });
            catalogCache[key].catch(() => { delete catalogCache[key]; });
        }
        return catalogCache[key];
    }

    function typeLabel(type) {
        return type === "movie" ? "Films" : type === "series" ? "Séries" : type === "anime" ? "Anime" : type;
    }

    // ===================== Navigation =====================

    // Onglets de la barre du haut, dans l'ordre.
    readonly property var tabNames: ["home", "discover", "search", "settings"]

    function tab(name) {
        return tabNames.indexOf(name);
    }

    function showTab(index) {
        screen = tabNames[index];
        lastTab = screen;
        if (screen === "home")
            home.forceActiveFocus();
        else if (screen === "discover")
            openDiscover(null);
        else if (screen === "search")
            search.focusKeyboard();
        else {
            refreshSettingsRows();
            settingsPage.focusList();
        }
    }

    // ===================== Decouvrir =====================

    // type, maxAge, catalog (transportUrl|id), genre, decade, minRating, provider (TMDB)
    property var discoverState: ({ type: "movie", maxAge: "", catalog: "", genre: "", decade: "", minRating: 0, provider: "" })
    property var discoverRaw: []         // titres recus (avant filtres locaux)
    property var discoverToken: null
    property var discoverKnown: ({})     // cles des titres recus (doublons)
    property var discoverParts: []       // « Tous les catalogues » : [{ cat, skip, done }]
    property int discoverPage: 0         // catalogue TMDB complet : derniere page recue
    property int discoverAutoPages: 0
    // Addon TMDB public (filtre d'age sans cle), charge a la premiere ouverture de Decouvrir.
    property var tmdbAddon: null
    property bool tmdbLoading: false
    // Cle API TMDB lue dans l'addon TMDB du compte ; genres et services par type.
    property string tmdbKey: ""
    property var tmdbApi: ({})           // { movie: { genres, providers }, series: ... }

    // Catalogues proposes : TMDB complet (avec cle), « Tous les catalogues », TMDB public, addons.
    // Avec un age maximum : seulement TMDB, qui filtre lui-meme.
    function discoverCatalogs() {
        const type = discoverState.type;
        const api = tmdbKey && tmdbApi[type] ? [Discover.apiCatalog(type, tmdbApi[type].genres)] : [];
        const tmdb = api.length ? api : Discover.ageCatalogs(tmdbAddon).filter(c => c.type === type);
        if (discoverState.maxAge)
            return tmdb;
        const own = Discover.catalogs(addons).filter(c => c.type === type);
        const all = own.length > 1 ? [Discover.allCatalog(own, type)] : [];
        return (api.length ? api.concat(all) : all.concat(tmdb)).concat(own);
    }

    function loadTmdbAddon() {
        if (tmdbAddon || tmdbLoading)
            return;
        tmdbLoading = true;
        client.manifest(Discover.TMDB_URL).then(a => {
            tmdbAddon = a;
            if (screen === "discover")
                refreshDiscoverFilters();
        }).catch(e => {
            log("TMDB (filtre d'âge) indisponible : " + e);
            tmdbLoading = false;
        });
    }

    // Cle de l'addon TMDB du compte : genres et services de streaming (France) de chaque type.
    function loadTmdbKey() {
        const key = Tmdb.apiKey(addons, LZ.decompressFromEncodedURIComponent);
        if (key === tmdbKey)
            return;
        tmdbKey = key;
        tmdbApi = {};
        if (!key)
            return;
        log("TMDB : clé API trouvée dans l'addon TMDB du compte");
        ["movie", "series"].forEach(type => {
            Promise.all([Http.fetchJson(Tmdb.genresUrl(key, type)),
                         Http.fetchJson(Tmdb.providersUrl(key, type)).catch(() => null)]).then(r => {
                if (tmdbKey !== key)
                    return;
                const api = Object.assign({}, tmdbApi);
                api[type] = { genres: r[0].genres || [], providers: Tmdb.providers(r[1], 20) };
                tmdbApi = api;
                if (screen === "discover" && discoverState.type === type) {
                    refreshDiscoverFilters();
                    if (!discoverState.catalog)
                        loadDiscover(true);  // le catalogue par defaut devient TMDB complet
                }
            }).catch(e => log("TMDB : clé refusée ou service indisponible (" + e + ")"));
        });
    }

    // Titre TMDB : fiche et sources via son identifiant IMDb (Cinemeta, addons de sources).
    function openDiscovered(meta) {
        const type = meta.type || discoverState.type;
        if (!Discover.isTmdbId(meta.id) || (!tmdbKey && !tmdbAddon)) {
            openMeta(type, meta.id);
            return;
        }
        const imdb = tmdbKey
            ? Http.fetchJson(Tmdb.externalIdsUrl(tmdbKey, type, meta.id)).then(r => r.imdb_id)
            : client.meta([tmdbAddon], type, meta.id).then(m => m.imdb_id);
        imdb.then(id => {
            if (id)
                openMeta(type, id);
            else
                toast("« " + meta.name + " » : titre inconnu d'IMDb, sources introuvables", "error");
        }).catch(e => toast("Fiche TMDB indisponible : " + e.message, "error"));
    }

    function currentDiscoverCatalog() {
        const list = discoverCatalogs();
        return list.find(c => c.transportUrl + "|" + c.id === discoverState.catalog) || list[0] || null;
    }

    // opts (facultatif) : { type, genre } (genre d'une fiche) ; null : garder les filtres.
    function openDiscover(opts) {
        loadTmdbKey();
        if (opts) {
            const st = Object.assign({}, discoverState, { type: opts.type || discoverState.type, catalog: "", genre: "", provider: "" });
            discoverState = st;
            const cat = currentDiscoverCatalog();
            if (cat && opts.genre && cat.genres.indexOf(opts.genre) !== -1)
                discoverState = Object.assign({}, discoverState, { genre: opts.genre });
            screen = "discover";
            lastTab = "discover";
        }
        loadTmdbAddon();
        refreshDiscoverFilters();
        if (opts || !discoverRaw.length)
            loadDiscover(true);
        discover.focusFilters();
    }

    function refreshDiscoverFilters() {
        const all = Discover.catalogs(addons);
        const st = discoverState;
        const cat = currentDiscoverCatalog();
        const api = !!cat && cat.kind === "tmdbApi";
        const opt = (id, label) => ({ id: id, label: label });
        const filters = [
            { key: "type", label: "Type", value: st.type, options: Discover.types(all).map(t => opt(t, Discover.typeLabel(t))) }
        ];
        if (tmdbAddon || tmdbKey)
            filters.push({ key: "maxAge", label: "Âge max", value: st.maxAge, options: Discover.AGES.map(a => opt(a.id, a.label)) });
        filters.push(
            { key: "catalog", label: "Catalogue", value: cat ? cat.transportUrl + "|" + cat.id : "",
              options: discoverCatalogs().map(c => opt(c.transportUrl + "|" + c.id, c.name + "  ·  " + c.addonName)) });
        if (cat && cat.genres.length)
            filters.push({ key: "genre", label: /^\d{4}$/.test(cat.genres[0]) ? "Année" : "Genre",
                           value: st.genre || (cat.genreRequired ? cat.genres[0] : ""),
                           options: (cat.genreRequired ? [] : [opt("", "Tous")]).concat(cat.genres.map(g => opt(g, g))) });
        const providers = api && tmdbApi[st.type] ? tmdbApi[st.type].providers : [];
        if (providers.length)
            filters.push({ key: "provider", label: "Service", value: st.provider,
                           options: [opt("", "Tous")].concat(providers.map(p => opt(p.id, p.name))) });
        filters.push({ key: "decade", label: "Période", value: st.decade, options: Discover.DECADES.map(d => opt(d.id, d.label)) });
        filters.push({ key: "minRating", label: "Note", value: st.minRating,
                       options: Discover.RATINGS.map(r => opt(r.id, api ? r.label.replace("IMDb", "TMDB") : r.label)) });
        filters.forEach(f => {
            const o = f.options.find(x => x.id === f.value);
            f.valueLabel = o ? o.label.split("  ·  ")[0] : "—";
        });
        discover.filters = filters;
        discover.hint = api ? (st.maxAge ? "tout TMDB  ·  âge : classification française (séries : américaine)" : "tout TMDB")
                      : cat && cat.kind === "all" ? "fusion de " + cat.parts.length + " catalogues, sans doublons"
                      : st.maxAge ? "âge : classification américaine, catalogues TMDB" : "";
    }

    function discoverChanged(key, value) {
        const st = Object.assign({}, discoverState);
        st[key] = value;
        if (key === "type")
            st.catalog = "", st.genre = "", st.provider = "";
        if (key === "catalog")
            st.genre = "", st.provider = "";
        if (key === "maxAge" && !value !== !discoverState.maxAge && !tmdbKey)
            st.catalog = "", st.genre = "";  // catalogues TMDB publics <-> catalogues des addons
        discoverState = st;
        refreshDiscoverFilters();
        const cat = currentDiscoverCatalog();
        if ((key === "decade" || key === "minRating") && !(cat && cat.kind === "tmdbApi")) {
            showDiscover(true);
            return;
        }
        loadDiscover(true);
    }

    // Filtres locaux appliques (TMDB complet : deja filtre par TMDB) ; trop peu de titres :
    // pages suivantes chargees d'elles-memes.
    function showDiscover(fillUp) {
        const cat = currentDiscoverCatalog();
        const list = cat && cat.kind === "tmdbApi" ? discoverRaw : Discover.apply(discoverRaw, discoverState);
        discover.metas = list;
        if (fillUp && list.length < 24 && discover.status === "")
            loadDiscover(false, true);
    }

    // Une page du catalogue courant -> Promise<{ metas | lists, done }>.
    function fetchDiscoverPage(cat) {
        const st = discoverState;
        if (cat.kind === "tmdbApi") {
            const page = discoverPage + 1;
            return Http.fetchJson(Tmdb.discoverUrl(tmdbKey, st.type, Discover.apiOptions(cat, st, page))).then(r => {
                discoverPage = page;
                return { metas: Tmdb.metas(r, st.type), done: Tmdb.lastPage(r) };
            });
        }
        if (cat.kind === "all") {
            const active = discoverParts.filter(p => !p.done);
            return Promise.all(active.map(p => client.catalog(p.cat, Discover.request(p.cat, st.genre, p.skip)).then(metas => {
                p.skip += metas.length;
                p.done = !metas.length || !p.cat.skip;
                return metas;
            }, () => {
                p.done = true;
                return [];
            }))).then(lists => ({ lists: lists, done: discoverParts.every(p => p.done) }));
        }
        return client.catalog(Discover.withAge(cat, st.maxAge), Discover.request(cat, st.genre, discoverRaw.length))
            .then(metas => ({ metas: metas, done: !cat.skip }));
    }

    function loadDiscover(reset, auto) {
        const cat = currentDiscoverCatalog();
        if (reset) {
            discoverRaw = [];
            discoverKnown = {};
            discoverPage = 0;
            discoverParts = cat && cat.kind === "all"
                ? Discover.allParts(cat, discoverState.genre).map(c => ({ cat: c, skip: 0, done: false })) : [];
            discover.metas = [];
            discoverToken = {};
            discover.status = "";
            discoverAutoPages = 0;
        }
        if (!cat) {
            discover.status = "fin";
            return;
        }
        if (discover.status !== "")
            return;
        if (auto && ++discoverAutoPages > 6)
            return;                       // filtres tres selectifs : la suite en descendant
        const token = discoverToken;
        discover.status = "chargement";
        fetchDiscoverPage(cat).then(page => {
            if (discoverToken !== token)
                return;
            const fresh = Discover.mergeNew(page.lists || [page.metas], discoverKnown, !page.lists);
            discoverRaw = discoverRaw.concat(fresh);
            discover.status = page.done || (!fresh.length && cat.kind !== "all") ? "fin" : "";
            showDiscover(true);
        }).catch(e => {
            log("Découvrir : " + e);
            if (discoverToken === token)
                discover.status = discoverRaw.length ? "fin" : "erreur";
        });
    }

    // Fiche : acteur, realisateur, scenariste -> recherche ; genre -> Decouvrir.
    function openPerson(name) {
        showTab(tab("search"));
        search.setQuery(name);
    }

    // ===================== Grille « Tout voir » =====================

    property var gridRow: null           // rangee affichee en grille

    function openGrid(row) {
        gridRow = row;
        screen = "grid";
        grid.reset(row.kind === "catalog" ? row.name + "  ·  " + row.addonName : row.name);
        grid.metas = row.metas || [];
        grid.status = row.kind === "catalog" && row.skip ? "" : "fin";
        if (grid.metas.length < 30 && grid.status === "")
            loadGridPage();
    }

    function loadGridPage() {
        const row = gridRow;
        if (!row || grid.status !== "")
            return;
        grid.status = "chargement";
        const skip = grid.metas.length;
        client.catalog({ transportUrl: row.transportUrl, type: row.type, id: row.cid }, { skip: skip }).then(metas => {
            if (gridRow !== row)
                return;
            const known = {};
            grid.metas.forEach(m => { known[m.id] = true; });
            const fresh = metas.filter(m => !known[m.id]);
            grid.metas = grid.metas.concat(fresh);
            grid.status = fresh.length ? "" : "fin";
        }).catch(e => {
            if (gridRow === row)
                grid.status = grid.metas.length ? "fin" : "erreur";
        });
    }

    function back() {
        if (screen === "grid") {
            gridRow = null;
            showTab(0);
            return;
        }
        if (screen === "player") {
            stopPlayer();
        } else if (screen === "sort") {
            if (returnScreen === "details") {
                screen = "details";
                refreshStreams();
                details.forceActiveFocus();
            } else {
                showTab(tab("settings"));
            }
        } else if (screen === "details") {
            if (!details.back()) {
                if (gridRow) {
                    screen = "grid";
                    grid.forceActiveFocus();
                } else {
                    showTab(tab(lastTab));
                }
            }
        } else if (screen === "account") {
            linkTimer.stop();
            showTab(tab(returnScreen) === -1 ? 0 : tab(returnScreen));
        } else if (screen === "search" || screen === "settings" || screen === "discover") {
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
        client.meta(addons, type, id, settings.metaLang !== "cinemeta").then(meta => {
            if (current !== opened)
                return;
            current.meta = meta;
            details.meta = meta;
            const episodes = [];
            Addons.seasons(meta).forEach(s => s.episodes.forEach(v => episodes.push(v)));
            if (type === "series" && episodes.length) {
                details.episodes = episodes;
                // Reprendre la serie : episode en cours (ou suivant le dernier vu)
                const resumeVideo = Resume.seriesResume(meta, positions, accountId,
                                                        libraryItems.find(i => i._id === id));
                if (resumeVideo) {
                    details.showEpisode(resumeVideo.id);
                    selectEpisode(resumeVideo);
                }
                else if (Config.AUTOTEST && Config.AUTOTEST.episode)
                    selectEpisode(episodes.find(v => v.id === Config.AUTOTEST.episode) || episodes[0]);
            } else {
                loadStreams(type, id);
            }
        }).catch(e => {
            if (current !== opened)
                return;
            log("fiche en échec : " + e);
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
        details.resumeText = at > 0 ? "Reprendre à " + fmtTime(at) : "";
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
            log("flux " + g.addon + " : " + (g.error ? "échec (" + g.error + ")" : g.items.length));
            if (g.items.length) {
                items = items.concat(g.items.map(s => ({ addon: g.addon, stream: s })));
                current.rawStreams = items;
            }
            current.streamsProgress = answered < total ? "  ·  " + answered + "/" + total + " addons" : "";
            refreshStreams();
            const like = current.autoPlayLike;
            if (like && g.addon === like.addon && g.items.length)
                playClosest();
            // Pas pendant la lecture (episode suivant deja lance) : le lecteur garderait la main.
            if (items.length && screen === "details")
                details.focusStreams();
        }).then(() => {
            if (current.streamsRequest !== request)
                return;
            log("flux pour " + videoId + " : " + items.length);
            current.streamsProgress = "";
            refreshStreams();                  // aussi sans aucune reponse (aucun addon de sources)
            prefetchBest();
            if (current.autoPlayLike)
                playClosest();
        }).catch(e => log("flux en échec : " + e));
    }

    // Capacites du PC et du reseau, pour ecarter les sources qui ne passeraient pas.
    function streamContext() {
        return {
            pc: pcActive,
            capacity: pcActive ? pcInfo.capacity : null,
            encoderMode: settings.encoder,
            boxLinkMbps: settings.boxLinkMbps,
            boxInternetMbps: settings.boxInternetMbps,
            durationMin: current && current.meta ? Sorting.runtimeMinutes(current.meta.runtime) : 0,
            maxWidth: settings.maxWidth,
            prefetch: settings.prefetch && pcActive
        };
    }

    function refreshStreams() {
        if (!current)
            return;
        const raw = current.rawStreams || [];
        const r = Sorting.sortStreams(raw, sortPrefs, streamContext());
        details.setStreams(r.visible);
        details.streamsStatus = (r.visible.length ? r.visible.length + " sources" : raw.length ? "Aucune source affichable" : "")
            + (r.hidden ? "  ·  " + r.hidden + " masquées" + (!r.heavy ? ""
                : pcActive ? " (dont " + r.heavy + " trop lourdes pour ce PC/réseau)" : " (dont " + r.heavy + " illisibles sans PC)") : "")
            + (current.streamsProgress || "")
            + (!current.streamsProgress && !raw.length ? "Aucune source trouvée (installez un addon de sources)" : "");
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
        details.streamsStatus = "Préparation de la lecture…";
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
            log("préparation de la lecture en échec : " + e);
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
        if (!settings.prefetch || !pcActive || !/^https?:[/][/]/.test(media) || Config.hostFromUrl(media) === pcHost)
            return Promise.resolve(plain);
        const fraction = durationMs > 0 && startAtMs > 0 ? startAtMs / durationMs : 0;
        return Http.request("GET", cfg.agent + "/fbx/prefetch?start=" + fraction.toFixed(4) + "&url="
                            + encodeURIComponent(media), undefined, false, 30000).then(st => {
            const cached = cfg.agent + st.fileUrl;
            log("préchargement par le PC : " + Math.round(st.total / 1048576) + " Mo");
            return {
                url: p.transcoded ? Playback.hlsUrl(playCfg, cached, !!forceTranscoding) : cached,
                mediaUrl: cached,
                prefetch: { id: st.id, statusUrl: st.statusUrl, durationMs: durationMs, startAtMs: startAtMs, mode: "start",
                            targetS: 0, started: Date.now(), skipUntil: 0 }
            };
        }).catch(e => {
            log("préchargement impossible (" + e.message + "), lecture sans");
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
                bufferTitle: "Préchargement…",
                bufferDetail: "Le PC télécharge la vidéo en avance pour une lecture sans coupure.",
                title: current.meta ? current.meta.name : "",
                subtitleLine: [details.selectedTitle, (item.badges || "").split(" · ").slice(0, 3).join(" · "),
                               p.transcoded ? "converti par le PC" : "lecture directe"].filter(x => x).join("   ·   "),
                // Avec prechargement, la source est donnee au lecteur quand l'avance est suffisante.
                source: pf.prefetch ? "" : url,
                startAt: startAt,
                audioTracks: audio,
                audioIndex: audioIndex,
                audioSwitchable: p.transcoded && audio.length > 1,
                subtitleTracks: [{ label: "Désactivés", kind: "off" }],
                startTimeoutMs: p.transcoded ? 60000 : 15000,
                nextTitle: next ? "S" + next.season + " E" + (next.episode || next.number) + "  ·  " + (next.title || next.name || "") : "",
                autoNext: settings.autoNext,
                volume: settings.volume,
                muted: false
            });
            current.nextVideo = next;
            current.nextPrep = null;
            current.playUrl = url;
            screen = "player";
            playerLoader.forceActiveFocus();
            if (startAt > 0)
                toast("Reprise à " + fmtTime(startAt) + "  ·  ◀ pour reculer");
            loadSubtitles(item.stream, p, audio[audioIndex]);
            if (!p.probe)
                loadMkvTracks(p.mediaUrl);
    }

    // Sans PC (pas d'analyse par le serveur) : pistes audio lues dans l'en-tete du MKV (requete
    // Range sur 256 Ko, puis a l'endroit indique si les pistes sont plus loin). Affichage seul :
    // QtMultimedia lit la piste par defaut, sans choix possible.
    function loadMkvTracks(url) {
        const page = playerLoader.item;
        if (!page || !/^https?:/.test(String(url)))
            return;
        const head = 262144;
        Http.fetchBytes(url, 0, head).then(bytes => {
            const r = Mkv.parse(bytes);
            if (r.tracksAt)
                return Http.fetchBytes(url, r.tracksAt, 65536).then(more => Mkv.parse(more, r.tracksAt, r.segmentStart));
            return r;
        }).then(r => {
            if (playerLoader.item !== page)
                return;
            if (!r.tracks) {
                log("pistes du fichier : " + r.error);
                page.audioNote = "Pistes du fichier inconnues (pas un MKV).";
                return;
            }
            const audio = Mkv.audioTracks(r.tracks, Playback.trackLabel);
            log("pistes du fichier : " + audio.map(a => a.label).join(" | "));
            page.audioTracks = audio;
            page.audioIndex = Mkv.defaultIndex(audio);
            page.audioNote = audio.length > 1
                ? "La box lit la piste cochée. Pour en changer : choisir une source dans la bonne langue, ou utiliser le PC."
                : "";
        }).catch(e => log("pistes du fichier illisibles : " + e.message));
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
        Http.fetchJson(cfg.agent + pf.statusUrl).then(st => {
            if (current.prefetch !== pf || playerLoader.item !== page)
                return;
            page.bufferedFrom = st.total ? st.base / st.total : 0;
            page.bufferedTo = st.total ? st.end / st.total : 0;
            if (st.done || st.error)
                startNextPrefetch(current.nextPrep);
            if (st.error) {
                log("préchargement interrompu : " + st.error);
                if (pf.mode !== "play")
                    beginPlayback(page, pf, "lecture sans préchargement");
                current.prefetch = null;
                return;
            }
            const dur = pf.durationMs || page.durationMs;
            const pos = pf.mode === "start" ? pf.startAtMs : page.positionMs;
            const detail = "Téléchargement " + (st.rateBps * 8 / 1e6).toFixed(1) + " Mbit/s   ·   vidéo "
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
                    page.bufferDetail = "Mesure de la vitesse de téléchargement…";
                    return;
                }
                const pr = Buffer.progress(st, dur, pos, pf.targetS);
                page.bufferPercent = pr.percent;
                page.bufferEta = pr.etaS > 0 ? Buffer.formatEta(pr.etaS) : "";
                page.bufferDetail = detail + (pr.tooLong ? "\nAttente longue : la connexion est plus lente que la vidéo. OK pour lancer quand même." : "");
                if (pr.ready)
                    beginPlayback(page, pf, "");
            } else if (Date.now() > pf.skipUntil && page.playing && page.positionMs > 0
                       && Buffer.shouldStall(st, dur, page.positionMs)) {
                pf.mode = "stall";
                prefetchWaiting = true;
                pf.targetS = 0;
                pf.started = Date.now();
                page.pausePlayer();
                page.bufferTitle = "Mise en mémoire…";
                page.bufferPercent = 0;
                page.bufferVisible = true;
                log("avance épuisée : pause automatique");
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
            log("lecture après préchargement (" + Math.round((Date.now() - pf.started) / 1000) + " s)" + (reason ? " : " + reason : ""));
        } else {
            page.resumePlayer();
            log("reprise après mise en mémoire");
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
                log("épisode suivant préparé : " + prep.item.addon + " (" + (prep.item.badges || "") + ")");
                const r = Playback.resolve(prep.item.stream, cfg, { season: next.season, episode: next.episode || next.number });
                if (settings.prefetch && pcActive && r.kind === "media" && /^https?:[/][/]/.test(r.mediaUrl) && Config.hostFromUrl(r.mediaUrl) !== pcHost) {
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
        log("préchargement du début de l'épisode suivant");
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
            toast("Aucune source pour l'épisode suivant", "warn");
            return;
        }
        log("épisode suivant : source la plus proche " + pick.addon + " (" + (pick.badges || "") + ")");
        current.fallbacks = details.streams.filter(x => x !== pick).slice(0, 2);
        play(pick);
    }

    // Encodeur du PC pour cette source : le plus rapide mesure pour son type de video
    // (la carte graphique echoue par exemple sur le H.264 10 bits avec Stremio).
    function profileFor(item) {
        const info = item.info || Sorting.parse(item.stream);
        const key = Sorting.codecKey(info) || "hevc";
        const cap = pcActive ? pcInfo.capacity : null;
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
        const options = [{ label: "Désactivés", kind: "off" }];
        Playback.embeddedSubtitles(p.probe).forEach(s => options.push({
            label: s.label + "  (intégré)", kind: "embedded", language: s.language,
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
        }).catch(e => log("sous-titres des addons en échec : " + e)).then(() => {
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
            log("sous-titres " + option.label + " en échec : " + e.message);
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
            log("sous-titres intégrés : " + s.segments.length + " segments");
            if (!s.segments.length)
                toast("Piste de sous-titres vide", "warn");
            pumpSubtitles();
        }).catch(e => {
            log("sous-titres intégrés en échec : " + e.message);
            if (subStream === s)
                toast("Sous-titres intégrés indisponibles (" + e.message + ")", "warn");
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
                        log("sous-titres intégrés : premiers sous-titres reçus");
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
                log("segment de sous-titres " + i + " en échec (" + s.tries[i] + ") : " + e.message);
                // Alerte seulement si plus rien n'arrive depuis 30 s.
                if (!s.warned && subStream === s && Date.now() - s.lastCueAt > 30000) {
                    s.warned = true;
                    toast("Les sous-titres intégrés arrivent mal, le PC est peut-être occupé", "warn");
                }
            });
        });
    }

    // Position de reprise : enregistree regulierement et a l'arret.
    function savePosition(atStop) {
        const page = playerLoader.item;
        if (!page || !current || !current.videoId || current.id === "essai" || page.positionMs <= 0)
            return;
        positions = Resume.record(positions, accountId, current.videoId, page.positionMs, page.durationMs, Date.now());
        settings.positions = JSON.stringify(positions);
        trackLibrary(page, atStop);
    }

    // ===================== Bibliotheque (« Continuer a regarder ») =====================

    property var libraryItems: []        // LibraryItem du compte, ou copie locale sans compte
    property var libraryPending: ({})    // elements a envoyer au compte (echec reseau : nouvel essai)
    property var libraryTrack: null      // { videoId, pos, at } : dernier point de suivi
    property real libraryPushedAt: 0

    function localLibrary() {
        try {
            const list = JSON.parse(settings.localLibrary || "[]");
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }

    function libraryRows() {
        return {
            continue: Account.continueWatching(libraryItems).map(Account.toMeta),
            library: Account.library(libraryItems).map(Account.toMeta)
        };
    }

    // Progression ecrite comme Stremio : localement a chaque point (15 s), vers le compte toutes
    // les 2 min et a l'arret. Temps regarde : avance de la position, plafonnee par le temps ecoule
    // (un saut en avant ne compte pas comme regarde).
    function trackLibrary(page, atStop) {
        const now = Date.now();
        const meta = current.meta || { id: current.id, type: current.type, name: "" };
        const t = libraryTrack;
        const watched = t && t.videoId === current.videoId
            ? Math.max(0, Math.min(page.positionMs - t.pos, now - t.at + 2000)) : 0;
        libraryTrack = { videoId: current.videoId, pos: page.positionMs, at: now };
        const before = libraryItems.find(i => i._id === current.id)
            || Library.fromMeta({ id: current.id, type: current.type, name: meta.name, poster: meta.poster,
                                  posterShape: meta.posterShape }, now);
        // Film : l'identifiant de la video est celui du film (comme Stremio).
        const item = Library.updateProgress(before, current.videoId, page.positionMs, page.durationMs, watched, now);
        libraryItems = Library.upsert(libraryItems, item);
        if (!authKey) {
            settings.localLibrary = JSON.stringify(Library.trimLocal(libraryItems));
        } else {
            const pending = Object.assign({}, libraryPending);
            pending[item._id] = item;
            libraryPending = pending;
            if (atStop || now - libraryPushedAt > 120000)
                pushLibrary();
        }
        if (atStop) {
            libraryTrack = null;
            refreshContinueRow();
        }
    }

    function pushLibrary() {
        const items = Object.keys(libraryPending).map(k => libraryPending[k]);
        if (!items.length || !authKey)
            return;
        libraryPushedAt = Date.now();
        const sent = libraryPending;
        account.libraryPut(authKey, items).then(() => {
            // Seuls les elements envoyes sont retires (d'autres ont pu arriver entre-temps).
            const rest = Object.assign({}, libraryPending);
            Object.keys(sent).forEach(k => { if (rest[k] === sent[k]) delete rest[k]; });
            libraryPending = rest;
            log("compte : progression envoyée (" + items.length + ")");
        }).catch(e => log("compte : progression non envoyée (" + e.message + "), nouvel essai plus tard"));
    }

    // Rangee « Continuer a regarder » de l'accueil recreee avec la bibliotheque a jour.
    function refreshContinueRow() {
        localRows = libraryRows();
        let i = -1;
        for (let k = 0; k < rowsModel.count; k++) {
            if (rowsModel.get(k).kind === "continue")
                i = k;
        }
        if (i !== -1)
            rowsModel.remove(i);
        if (!localRows.continue.length)
            return;
        const at = rowsModel.count && rowsModel.get(0).kind === "link" ? 1 : 0;
        rowsModel.insert(i !== -1 ? i : at, { kind: "continue", transportUrl: "", addonName: "Compte", type: "", cid: "",
                                              name: "Continuer à regarder", skip: false });
    }

    function playbackFailed(reason) {
        const p = current.playback;
        log("échec de lecture (" + reason + ")");
        Qt.callLater(() => {
            stopPlayer();
            if (p && !p.transcoded && current.playingItem && pcActive)
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
            toast("Épisode suivant : S" + next.season + " E" + (next.episode || next.number));
            play(prep.item);
            return;
        }
        // Des que l'addon de l'episode precedent repond : la source qui lui ressemble le plus.
        current.autoPlayLike = !previous ? null
            : previous.info ? previous : (Sorting.sortStreams([previous], sortPrefs).visible[0] || null);
        toast("Épisode suivant : S" + next.season + " E" + (next.episode || next.number));
    }

    function stopPlayer() {
        subStream = null;
        prefetchWaiting = false;
        if (current)
            current.prefetch = null;           // l'agent arrete seul un prechargement abandonne
        savePosition(true);
        if (playerLoader.item)
            playerLoader.item.stop();
        playerLoader.source = "";
        if (current && current.id === "essai") {       // essai V2.1 : retour aux reglages
            showTab(tab("settings"));
            return;
        }
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

    // Resultats affiches au fur et a mesure des reponses (un addon lent ne bloque plus les autres),
    // dans l'ordre des addons. Pendant que l'utilisateur parcourt les resultats, la liste n'est
    // completee qu'a la fin (sinon la selection repartirait en haut).
    function runSearch(text) {
        const refs = Addons.searchCatalogs(addons);
        const token = {};
        search.token = token;
        const groups = refs.map(() => null);
        const started = Date.now();
        const times = [];
        let answered = 0;
        const show = () => {
            const list = groups.filter(g => g && g.metas.length);
            if (!search.resultsFocused || answered === refs.length)
                search.results = list;
            search.status = answered < refs.length
                ? (list.length ? "" : "Recherche… (" + answered + "/" + refs.length + " addons)")
                : list.length ? "" : "Aucun résultat pour « " + text + " »";
        };
        show();
        refs.forEach((ref, i) => {
            const t0 = Date.now();
            client.catalog(ref, { search: text }).then(metas => metas, () => []).then(metas => {
                if (search.token !== token)
                    return;
                times.push({ name: ref.addonName || ref.name, ms: Date.now() - t0 });
                groups[i] = { title: ref.name + " · " + typeLabel(ref.type), metas: metas };
                answered++;
                show();
                if (answered === refs.length) {
                    const slowest = times.slice().sort((a, b) => b.ms - a.ms)[0];
                    perf.search = { ms: Date.now() - started, slowest: slowest ? slowest.name + " " + fmtSeconds(slowest.ms) : "" };
                    log("recherche : " + fmtSeconds(perf.search.ms) + " (plus lent : " + perf.search.slowest + ")");
                    refreshSettingsRows();
                }
            });
        });
    }

    // ===================== Mesures de vitesse (Reglages > Diagnostic) =====================

    // startedAt : lancement ; addonsMs : addons charges ; catalogs : [{ name, ms }] des rangees.
    property var perf: ({ startedAt: Date.now(), addonsMs: 0, catalogs: [], search: null })

    function fmtSeconds(ms) {
        return (ms / 1000).toFixed(1).replace(".", ",") + " s";
    }

    function perfRows() {
        const rows = [];
        const s = "Diagnostic (vitesse)";
        rows.push({ section: s, key: "perfAddons", label: "Lancement → addons chargés", action: "info",
                    value: perf.addonsMs ? fmtSeconds(perf.addonsMs) : "—" });
        const c = perf.catalogs;
        if (c.length) {
            const slowest = c.slice().sort((a, b) => b.ms - a.ms)[0];
            const avg = c.reduce((t, x) => t + x.ms, 0) / c.length;
            rows.push({ section: s, key: "perfCatalogs", label: "Rangées de l'accueil (" + c.length + ")", action: "info",
                        value: "moyenne " + fmtSeconds(avg) + "  ·  plus lente " + fmtSeconds(slowest.ms) + " (" + slowest.name + ")" });
        }
        if (perf.search)
            rows.push({ section: s, key: "perfSearch", label: "Dernière recherche", action: "info",
                        value: fmtSeconds(perf.search.ms) + "  ·  plus lent : " + perf.search.slowest });
        return rows;
    }

    // ===================== Compte =====================

    function openAccount() {
        if (screen !== "account")
            returnScreen = screen;
        screen = "account";
        accountPage.forceActiveFocus();
        accountPage.status = "";
        if (authKey) {
            accountPage.email = settings.accountEmail || "compte lié";
        } else {
            accountPage.email = "";
            startLink();
        }
    }

    function startLink() {
        linkTimer.stop();
        accountPage.code = "";
        accountPage.status = "Création du code…";
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
                toast("Compte Stremio lié");
                checkAccount();
                showTab(0);
                loadAddons();
            });
        }).catch(e => accountPage.status = "Erreur : " + e.message);
    }

    function unlink() {
        forgetAccount();
        toast("Compte délié de ce Player");
        showTab(0);
        loadAddons();
    }

    // ===================== Reglages =====================

    function choice(list, value, step) {
        const i = list.indexOf(value);
        return list[((i === -1 ? 0 : i) + step + list.length) % list.length];
    }

    function refreshSettingsRows() {
        const pc = pcActive ? pcInfo : null;
        const langs = { auto: "Automatique", fr: "Français", en: "Anglais", vo: "Version originale", off: "Désactivés" };
        const pcState = settings.pcMode === "off" ? "Non utilisé (lecture directe seulement)"
            : !pcHost ? "Aucun PC connu (lecture directe seulement)"
            : !pcOk ? "Injoignable (lecture directe seulement)"
            : pc.stremio.ok ? "Stremio " + pc.stremio.version + " actif" : "Stremio arrêté";
        const rows = [
            { section: "PC (facultatif)", key: "pcMode", label: "Utiliser un PC", action: "choice",
              value: settings.pcMode === "off" ? "Jamais" : "S'il est allumé" },
            { section: "PC (facultatif)", key: "pcState", label: "État", action: "info", value: pcState,
              tone: pc && pc.stremio.ok ? "ok" : pcHost && settings.pcMode !== "off" ? "bad" : "" }
        ];
        if (pcHost && settings.pcMode !== "off") {
            rows.push({ section: "PC (facultatif)", key: "pcName", label: "Nom", value: pc ? pc.pcName : settings.pcName || "—", action: "info" });
            rows.push({ section: "PC (facultatif)", key: "pcIp", label: "Adresse", value: pcHost, action: "info" });
        }
        if (pc)
            rows.push({ section: "PC (facultatif)", key: "startStremio", label: "Démarrer Stremio sur le PC", value: "Démarrer", action: "button" });
        if (settings.pcMode !== "off")
            rows.push({ section: "PC (facultatif)", key: "recheck", label: "Vérifier la connexion", value: "Vérifier", action: "button" });
        rows.push(
            { section: "Compte Stremio", key: "account", label: authKey ? (settings.accountEmail || "Compte lié") : "Aucun compte lié",
              value: authKey ? "Gérer" : "Lier un compte", action: "button" },
            { section: "Lecture", key: "audioLang", label: "Langue audio préférée", value: langs[settings.audioLang] || settings.audioLang, action: "choice" },
            { section: "Lecture", key: "subLang", label: "Sous-titres par défaut", value: settings.subLang === "auto" ? "Français si audio étranger" : langs[settings.subLang], action: "choice" },
            { section: "Lecture", key: "autoNext", label: "Enchaîner l'épisode suivant", value: settings.autoNext ? "Oui" : "Non", action: "choice" },
            { section: "Lecture", key: "sort", label: "Tri des sources", value: "Ouvrir", action: "button" },
            { section: "Lecture", key: "metaLang", label: "Fiches (résumés, titres)", action: "choice",
              value: settings.metaLang === "cinemeta" ? "Cinemeta (anglais)" : addons.some(a => !Addons.isCinemeta(a) && Addons.supports(a.manifest, "meta", "", "tt0000001"))
                     ? "Addon traduit d'abord" : "Addon traduit d'abord (aucun installé)" },
            { section: "Lecture", key: "clearPositions", label: "Oublier les positions de lecture", value: "Effacer", action: "button" });
        if (pc) {
            rows.push(
                { section: "Lecture avec le PC", key: "quality", label: "Qualité en conversion par le PC", value: settings.maxWidth >= 1920 ? "1080p (réseau rapide)" : "720p (recommandé)", action: "choice" },
                { section: "Lecture avec le PC", key: "encoder", label: "Conversion sur le PC", action: "choice",
                  value: settings.encoder === "cpu" ? "Processeur (lent)"
                         : cfg.profile ? "Carte graphique (" + cfg.profile + ")" : "Processeur (aucune carte détectée)" },
                { section: "Lecture avec le PC", key: "prefetch", label: "Préchargement par le PC (anti-coupures)", action: "choice",
                  value: settings.prefetch ? "Oui" : "Non" },
                { section: "Capacités", key: "capConvert", label: "Conversion par le PC (HEVC 1080p)", action: "info",
                  value: capacityText() },
                { section: "Capacités", key: "capPcNet", label: "Internet vers le PC", action: "info",
                  value: pc.capacity && pc.capacity.pcInternetMbps ? pc.capacity.pcInternetMbps + " Mbit/s" : "non mesuré" },
                { section: "Capacités", key: "capLink", label: "PC vers le Player", action: "info",
                  value: settings.boxLinkMbps ? settings.boxLinkMbps + " Mbit/s" : "non mesuré" });
        }
        rows.push(
            { section: "Capacités", key: "capBoxNet", label: "Internet vers le Player", action: "info",
              value: settings.boxInternetMbps ? settings.boxInternetMbps + " Mbit/s" : "non mesuré" },
            { section: "Capacités", key: "speed", label: "Mesurer les débits du Player", value: measuring ? "mesure…" : "Mesurer", action: "button" },
            { section: "À propos", key: "version", label: "Version", action: "info",
              value: "appli " + appVersion + (pc ? "  ·  agent du PC " + pc.agentVersion : "") });
        rows.push(
            { section: "Essais « zéro PC » (V2.1)", key: "trialNative", label: "Lecteur natif du Player (vidéo de test)", value: "Essayer", action: "button" },
            { section: "Essais « zéro PC » (V2.1)", key: "trialYoutube", label: "Appli YouTube du Player (bande-annonce)", value: "Essayer", action: "button" },
            { section: "Essais « zéro PC » (V2.1)", key: "trialFbxAuth", label: settings.fbxAppToken ? "Freebox Server : appli autorisée" : "Autoriser l'appli sur la Freebox Server",
              value: settings.fbxAppToken ? "Refaire" : "Autoriser", action: "button" },
            { section: "Essais « zéro PC » (V2.1)", key: "trialFbxDownloads", label: "Lire l'aperçu du dernier téléchargement de la Server", value: "Lire", action: "button" });
        perfRows().forEach(r => rows.push(r));
        modules.forEach(m => rows.push({ section: "Diagnostic (modules de la box)", key: "module", label: m.name, action: "info",
                                         value: m.ok ? "présent" : "absent", tone: m.ok ? "ok" : "" }));
        settingsPage.setRows(rows);
    }
    function capacityText() {
        const cap = pcInfo ? pcInfo.capacity : null;
        if (!cap || !cap.encoders)
            return "non mesurée (relancer le lanceur du PC)";
        const best = Sorting.bestEncoder(cap, "hevc", settings.encoder);
        return best.factor.toFixed(1) + "x le temps réel" + (best.encoder ? " (" + best.encoder + ")" : " (processeur)")
            + "  ·  mesure du " + Qt.formatDate(new Date(cap.measuredAt * 1000), "dd/MM");
    }

    function settingAction(key, step) {
        switch (key) {
        case "startStremio": startStremioOnPc(); break;
        case "recheck": checkPc(); toast("Vérification…"); break;
        case "pcMode":
            settings.pcMode = settings.pcMode === "off" ? "auto" : "off";
            checkPc();
            loadAddons();
            break;
        case "account": openAccount(); return;
        case "audioLang": settings.audioLang = choice(["auto", "fr", "en", "vo"], settings.audioLang, step || 1); break;
        case "subLang": settings.subLang = choice(["auto", "fr", "en", "off"], settings.subLang, step || 1); break;
        case "autoNext": settings.autoNext = !settings.autoNext; break;
        case "metaLang": settings.metaLang = settings.metaLang === "cinemeta" ? "translated" : "cinemeta"; break;
        case "quality": settings.maxWidth = settings.maxWidth >= 1920 ? 1280 : 1920; break;
        case "encoder": settings.encoder = settings.encoder === "cpu" ? "auto" : "cpu"; break;
        case "prefetch": settings.prefetch = !settings.prefetch; break;
        case "sort": openSortSettings(); return;
        case "clearPositions":
            positions = {};
            settings.positions = "{}";
            toast("Positions de lecture effacées");
            break;
        case "speed": measureLinks(); break;
        case "trialNative":
        case "trialYoutube":
        case "trialFbxAuth":
        case "trialFbxDownloads":
            runTrial(key);
            return;
        }
        refreshSettingsRows();
    }

    // ===================== Essais « zero PC » (V2.1, docs/V2.1-ESSAIS.md) =====================

    // Video H.264 publique (Blender Foundation, Big Buck Bunny) et bande-annonce YouTube.
    readonly property string trialVideo: "http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
    readonly property string trialYoutube: "https://www.youtube.com/watch?v=aqz-KE-bpKQ"

    function runTrial(key) {
        try {
            if (key === "trialNative") {
                log("essai : App.urlOpen vers le lecteur natif (" + trialVideo + ")");
                App.urlOpen(trialVideo, "video/mp4");
                toast("Demandé au Player : la vidéo s'ouvre-t-elle dans son lecteur ?");
            } else if (key === "trialYoutube") {
                log("essai : App.urlOpen vers YouTube");
                App.urlOpen(trialYoutube, "");
                toast("Demandé au Player : l'appli YouTube s'ouvre-t-elle ?");
            } else {
                trialsLoader.active = true;
                if (trialsLoader.status !== Loader.Ready) {
                    toast("Essais Freebox Server indisponibles (fbx.web absent)", "error");
                    return;
                }
                if (key === "trialFbxAuth")
                    trialsLoader.item.authorize();
                else
                    trialsLoader.item.listDownloads();
            }
        } catch (e) {
            log("essai " + key + " en échec : " + e);
            toast("Essai en échec : " + e, "error");
        }
    }

    // Lecture d'une URL quelconque (aperçu de la Freebox Server), sans fiche ni addon.
    function playDirectUrl(url, title) {
        current = { type: "movie", id: "essai", videoId: "essai", meta: { name: title }, rawStreams: [] };
        const p = { kind: "play", url: url, mediaUrl: url, transcoded: false, probe: null };
        startPlayer({ addon: "Freebox Server", stream: { url: url, subtitles: [] }, badges: "aperçu Freebox Server" },
                    p, { url: url, mediaUrl: url, prefetch: null }, [], 0);
    }

    Loader {
        id: trialsLoader
        active: false
        source: "Trials.qml"
        onLoaded: {
            item.appToken = Qt.binding(() => settings.fbxAppToken);
            item.appVersion = Qt.binding(() => app.appVersion);
            item.tokenChanged.connect(t => { settings.fbxAppToken = t; app.refreshSettingsRows(); });
            item.status.connect((m, kind) => app.toast(m, kind || undefined));
            item.logMessage.connect(app.log);
            item.playRequested.connect(app.playDirectUrl);
        }
    }

    // Telecharge url et renvoie le debit en Mbit/s (0 si echec).
    function downloadMbps(url) {
        return new Promise(resolve => {
            const start = Date.now();
            const xhr = new XMLHttpRequest();
            let finished = false;
            // Sans reponse en 20 s (site bloque, reseau coupe) : mesure abandonnee.
            const timer = Http.startTimer(20000, () => {
                if (finished)
                    return;
                finished = true;
                xhr.abort();
                resolve(0);
            });
            xhr.responseType = "arraybuffer";
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE || finished)
                    return;
                finished = true;
                timer.stop();
                timer.destroy();
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
        const fromPc = pcActive ? downloadMbps(cfg.agent + "/fbx/api/speedtest?bytes=" + (4 * 1024 * 1024) + "&t=" + t)
                                : Promise.resolve(0);
        fromPc.then(link => {
            if (link > 0)
                settings.boxLinkMbps = Math.round(link * 10) / 10;
            return downloadMbps("https://speed.cloudflare.com/__down?bytes=4000000&t=" + t);
        }).then(net => {
            if (net > 0)
                settings.boxInternetMbps = Math.round(net * 10) / 10;
            measuring = false;
            log("débits : PC -> box " + settings.boxLinkMbps + " Mbit/s, Internet -> box " + settings.boxInternetMbps + " Mbit/s");
            refreshSettingsRows();
            refreshStreams();
        });
    }
    property bool measuring: false

    Timer {
        id: measureDelay
        interval: 45000
        onTriggered: if (app.screen !== "player") app.measureLinks()
    }

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
        property real volume: 1.0          // volume du lecteur (le volume du Player ne s'y applique pas)
        property string localLibrary: "[]" // sans compte : « Continuer a regarder » (LibraryItem)
        property string metaLang: "translated" // fiches : addon traduit (TMDB...) avant Cinemeta
        property string pcMode: "auto"     // auto : PC utilise s'il repond ; off : jamais
        property string fbxAppToken: ""    // jeton Freebox OS (essais V2.1), jamais dans les journaux
    }

    ListModel { id: rowsModel }

    property int pcFailures: 0
    Timer {
        // Surveillance du PC : nom, Stremio, coupure (rien a faire sans PC connu). Intervalle
        // regle par checkPc : 30 s si le PC repond, de plus en plus espace s'il est eteint.
        id: pcTimer
        interval: 30000
        repeat: true
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
        // Lecture en cours : le PC ne doit pas se mettre en veille (voir companion.keep_awake_loop).
        interval: 60000
        repeat: true
        triggeredOnStart: true
        running: app.screen === "player" && app.pcActive
        onTriggered: Http.request("GET", app.cfg.agent + "/fbx/api/keepalive").catch(() => {})
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
            onExpandRequested: app.openGrid(row)
            onUp: topBar.forceActiveFocus()
        }

        DiscoverPage {
            id: discover
            objectName: "decouvrir"
            anchors.fill: parent
            visible: app.screen === "discover"
            progressOf: app.metaProgress
            onChanged: app.discoverChanged(key, value)
            onActivated: app.openDiscovered(meta)
            onMoreWanted: { app.discoverAutoPages = 0; app.loadDiscover(false); }
            onUp: topBar.forceActiveFocus()
        }

        CatalogGridPage {
            id: grid
            objectName: "grille"
            anchors.fill: parent
            visible: app.screen === "grid"
            progressOf: app.metaProgress
            onActivated: app.openMeta(meta.type || (app.gridRow ? app.gridRow.type : ""), meta.id)
            onMoreWanted: app.loadGridPage()
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
            visible: app.tab(app.screen) !== -1
            current: app.tab(app.screen)
            // Pastille du PC seulement si un PC est connu (verte : utilise ; rouge : injoignable).
            pcName: settings.pcMode === "off" ? "" : app.pcActive ? app.pcInfo.pcName : app.pcHost
            pcOk: app.pcActive
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
            onPersonChosen: app.openPerson(name)
            onGenreChosen: app.openDiscover({ type: app.current ? app.current.type : "movie", genre: genre })
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
                    app.log("vérification : lecteur charge sans erreur");
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
                item.volumeAdjusted.connect(v => { settings.volume = v; });
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
                app.showTab(app.tab("settings"));
            } else if (event.key === Qt.Key_Search) {
                event.accepted = true;
                app.showTab(app.tab("search"));
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
