// Tests du mini-core JS de l'appli : node --test tests/
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");
const fixture = load.fixture;

const addons = load("app/js/core/addons.js");
const playback = load("app/js/core/playback.js");
const vtt = load("app/js/core/vtt.js");

const CINEMETA = "https://v3-cinemeta.strem.io/manifest.json";
const OPENSUBS = "https://opensubtitles-v3.strem.io/manifest.json";
// Les tableaux crees dans le contexte vm ne sont pas du meme "realm" que ceux du test.
const plain = x => JSON.parse(JSON.stringify(x));
const SETTINGS = { server: "http://pc:11470", companion: "http://pc:11480" };

// Transport factice : repond avec les fixtures selon l'URL.
function fakeFetch(routes, log) {
    return url => {
        if (log)
            log.push(url);
        for (const prefix of Object.keys(routes)) {
            if (url === prefix || url.indexOf(prefix) === 0)
                return Promise.resolve(routes[prefix]);
        }
        return Promise.reject(new Error("404 " + url));
    };
}

const loadedAddons = [
    { transportUrl: CINEMETA, manifest: fixture("cinemeta-manifest.json") },
    { transportUrl: OPENSUBS, manifest: fixture("opensubtitles-manifest.json") }
];

test("URL des ressources selon le protocole", () => {
    assert.equal(addons.baseUrl(CINEMETA), "https://v3-cinemeta.strem.io");
    assert.equal(addons.resourceUrl(CINEMETA, "catalog", "movie", "top"),
        "https://v3-cinemeta.strem.io/catalog/movie/top.json");
    assert.equal(addons.resourceUrl(CINEMETA, "catalog", "series", "top", { search: "dark knight", skip: 0 }),
        "https://v3-cinemeta.strem.io/catalog/series/top/search=dark%20knight&skip=0.json");
    assert.equal(addons.resourceUrl(CINEMETA, "stream", "series", "tt5753856:1:1"),
        "https://v3-cinemeta.strem.io/stream/series/tt5753856%3A1%3A1.json");
    assert.equal(addons.resourceUrl("https://a.example/conf/manifest.json?key=K", "stream", "movie", "tt1"),
        "https://a.example/conf/stream/movie/tt1.json?key=K", "parametres apres manifest.json gardes");
});

test("ressources prises en charge par chaque addon", () => {
    const [cinemeta, opensubs] = loadedAddons.map(a => a.manifest);
    assert.ok(addons.supports(cinemeta, "meta", "series", "tt5753856"));
    assert.ok(!addons.supports(cinemeta, "stream", "movie", "tt0111161"));
    assert.ok(addons.supports(opensubs, "subtitles", "movie", "tt0111161"));
    assert.ok(!addons.supports(opensubs, "subtitles", "movie", "kitsu:1"), "idPrefixes respectes");
    assert.ok(addons.supports({ resources: [{ name: "stream", types: ["movie"], idPrefixes: ["tt"] }] },
        "stream", "movie", "tt1"));
});

test("catalogues d'accueil sans extra obligatoire, catalogues de recherche", () => {
    const home = addons.homeCatalogs(loadedAddons).map(c => c.type + "/" + c.id);
    assert.deepEqual(plain(home), ["movie/top", "series/top", "movie/imdbRating", "series/imdbRating"]);
    const search = addons.searchCatalogs(loadedAddons).map(c => c.type + "/" + c.id);
    assert.deepEqual(plain(search), ["movie/top", "series/top"]);
});

test("chargement des addons, catalogue, fiche, saisons", async () => {
    const calls = [];
    const client = addons.createClient(fakeFetch({
        [CINEMETA]: fixture("cinemeta-manifest.json"),
        [OPENSUBS]: fixture("opensubtitles-manifest.json"),
        "https://v3-cinemeta.strem.io/catalog/series/top/search=dark.json": fixture("cinemeta-catalog-series-search-dark.json"),
        "https://v3-cinemeta.strem.io/meta/series/tt5753856.json": fixture("cinemeta-meta-series-tt5753856.json")
    }, calls));

    const loaded = await client.loadAddons([CINEMETA, OPENSUBS, "https://absent.example/manifest.json"]);
    assert.equal(loaded.addons.length, 2);
    assert.equal(loaded.errors.length, 1);

    const ref = addons.searchCatalogs(loaded.addons).find(c => c.type === "series");
    const metas = await client.catalog(ref, { search: "dark" });
    assert.ok(metas.length > 0);
    assert.ok(metas.some(m => m.id === "tt5753856"));

    const meta = await client.meta(loaded.addons, "series", "tt5753856");
    assert.equal(meta.name, "Dark");
    const seasons = addons.seasons(meta);
    assert.deepEqual(plain(seasons.map(s => s.season).slice(0, 3)), [1, 2, 3]);
    assert.equal(seasons[0].episodes[0].id, "tt5753856:1:1");
});

test("flux agreges : un addon en erreur ne bloque pas les autres", async () => {
    const torrentio = { transportUrl: "https://t.example/manifest.json",
        manifest: { name: "T", resources: ["stream"], types: ["movie"], idPrefixes: ["tt"] } };
    const broken = { transportUrl: "https://b.example/manifest.json",
        manifest: { name: "B", resources: ["stream"], types: ["movie"] } };
    const client = addons.createClient(fakeFetch({
        "https://t.example/stream/movie/tt1.json": { streams: [{ url: "http://x/film.mp4" }] }
    }));
    const seen = [];
    const groups = await client.streams(loadedAddons.concat([torrentio, broken]), "movie", "tt1",
        (g, total) => seen.push(g.addon + "/" + total));
    assert.deepEqual(plain(seen.sort()), ["B/2", "T/2"], "chaque addon signale des sa reponse");
    assert.equal(groups.length, 2, "Cinemeta et OpenSubtitles n'ont pas de flux");
    assert.equal(groups[0].items.length, 1);
    assert.ok(groups[1].error);
});

test("resolution d'un flux : URL, proxy, torrent, magnet, externe", () => {
    let r = playback.resolve({ url: "https://cdn/film.mkv" }, SETTINGS);
    assert.equal(r.kind, "media");
    assert.equal(r.mediaUrl, "https://cdn/film.mkv");

    r = playback.resolve({ url: "https://cdn.example/a/b.mp4?t=1",
        behaviorHints: { proxyHeaders: { request: { Referer: "https://r" } } } }, SETTINGS);
    assert.equal(r.mediaUrl, "http://pc:11470/proxy/d=https%3A%2F%2Fcdn.example&h=Referer%3Ahttps%3A%2F%2Fr/a/b.mp4?t=1");

    r = playback.resolve({ infoHash: "ABCDEF", fileIdx: 2 }, SETTINGS);
    assert.equal(r.mediaUrl, "http://pc:11470/abcdef/2");

    r = playback.resolve({ infoHash: "abc", sources: ["udp://tr:80"] }, SETTINGS, { season: 1, episode: 3 });
    assert.equal(r.kind, "torrent");
    assert.equal(r.create.url, "http://pc:11470/abc/create");
    assert.deepEqual(plain(r.create.body), {
        torrent: { infoHash: "abc" },
        peerSearch: { sources: ["dht:abc", "tracker:udp://tr:80"], min: 40, max: 200 },
        guessFileIdx: { season: 1, episode: 3 }
    });
    assert.equal(playback.torrentMediaUrl(SETTINGS, r, { guessedFileIdx: 4 }),
        "http://pc:11470/abc/4?tr=dht%3Aabc&tr=tracker%3Audp%3A%2F%2Ftr%3A80");

    r = playback.resolve({ url: "magnet:?xt=urn:btih:ABC123&tr=udp%3A%2F%2Ft%3A1" }, SETTINGS);
    assert.equal(r.kind, "torrent");
    assert.equal(r.infoHash, "abc123");

    assert.equal(playback.resolve({ ytId: "x" }, SETTINGS).kind, "external");
    assert.equal(playback.resolve({}, SETTINGS).kind, "unsupported");
});

test("lecture directe ou transcodage selon le probe", () => {
    const h264 = { format: { name: "matroska,webm" },
        streams: [{ track: "video", codec: "h264", width: 1280 }, { track: "audio", codec: "ac3", channels: 6 }] };
    const hevc = { format: { name: "matroska,webm" },
        streams: [{ track: "video", codec: "hevc", width: 1920 }, { track: "audio", codec: "aac", channels: 2 }] };
    const twoAudio = { format: { name: "mov,mp4,m4a" },
        streams: [{ track: "video", codec: "h264" }, { track: "audio", codec: "aac" }, { track: "audio", codec: "aac" }] };
    assert.ok(playback.canPlayDirect(h264));
    assert.ok(!playback.canPlayDirect(hevc));
    assert.ok(!playback.canPlayDirect(twoAudio));
    assert.ok(!playback.canPlayDirect(null));

    const p = playback.playUrl(SETTINGS, "http://pc:11470/abc/1", hevc);
    assert.ok(p.transcoded);
    assert.match(p.url, /^http:\/\/pc:11480\/hlsv2\/fbx[a-z0-9]+\/master\.m3u8\?mediaURL=http%3A%2F%2Fpc%3A11470%2Fabc%2F1&videoCodecs=h264&audioCodecs=aac&audioCodecs=mp3&maxAudioChannels=2&maxWidth=1280$/);
});

test("plan complet : torrent sans fileIdx puis probe HEVC -> HLS", async () => {
    const posted = [];
    const transport = {
        postJson: (url, body) => { posted.push(url); return Promise.resolve({ guessedFileIdx: 0 }); },
        fetchJson: url => url.indexOf("/hlsv2/probe") !== -1
            ? Promise.resolve({ format: { name: "matroska" }, streams: [{ track: "video", codec: "hevc" }] })
            : Promise.reject(new Error(url))
    };
    const p = await playback.plan({ infoHash: "abc" }, SETTINGS, transport);
    assert.deepEqual(posted, ["http://pc:11470/abc/create"]);
    assert.equal(p.kind, "play");
    assert.equal(p.mediaUrl, "http://pc:11470/abc/0");
    assert.ok(p.transcoded);
});

test("plan : probe en echec -> transcodage par prudence", async () => {
    const transport = { fetchJson: () => Promise.reject(new Error("probe")), postJson: null };
    const p = await playback.plan({ url: "https://cdn/x.mp4" }, SETTINGS, transport);
    assert.ok(p.transcoded);
    assert.equal(p.probe, null);
});

test("sous-titres VTT", () => {
    const text = "WEBVTT\n\n0\n00:00:01.000 --> 00:00:10.000\nSous-titre <i>1</i>\n\n1\n00:00:12.000 --> 00:01:30.500\nDeuxieme\nligne\n";
    const cues = vtt.parse(text);
    assert.equal(cues.length, 2);
    assert.equal(cues[1].end, 90500);
    assert.equal(vtt.textAt(cues, 5000), "Sous-titre 1");
    assert.equal(vtt.textAt(cues, 11000), "");
    assert.equal(vtt.textAt(cues, 13000), "Deuxieme\nligne");
    assert.equal(playback.subtitlesVttUrl(SETTINGS, "http://x/a.srt"),
        "http://pc:11470/subtitles.vtt?from=http%3A%2F%2Fx%2Fa.srt");
});

test("addon local de Stremio Desktop redirige vers le PC", () => {
    assert.equal(addons.localToServer("http://127.0.0.1:11470/local-addon/manifest.json", "http://pc:11470"),
        "http://pc:11470/local-addon/manifest.json");
    assert.equal(addons.localToServer("https://v3-cinemeta.strem.io/manifest.json", "http://pc:11470"),
        "https://v3-cinemeta.strem.io/manifest.json");
});

test("pistes audio et sous-titres", () => {
    const probe = { format: { name: "matroska,webm" }, streams: [
        { id: 0, track: "video", codec: "h264" },
        { id: 0, track: "audio", codec: "aac", channels: 1, title: "Francais 440 Hz", language: "fre" },
        { id: 1, track: "audio", codec: "ac3", channels: 6, title: null, language: "eng" },
        { id: 0, track: "subtitle", codec: "subrip", language: "fre" },
        { id: 1, track: "subtitle", codec: "hdmv_pgs_subtitle", language: "eng" },
        { id: 2, track: "subtitle", codec: "ass", language: null } ] };
    const audio = playback.audioTracks(probe);
    assert.deepEqual(plain(audio.map(a => a.label)), ["Français - Francais 440 Hz (AAC 1 canaux)", "Anglais (AC3 6 canaux)"]);
    const subs = playback.embeddedSubtitles(probe);
    assert.deepEqual(plain(subs.map(s => s.id + ":" + s.label)), ["0:Français", "2:Piste 2"], "PGS (image) ignore");

    const master = "http://pc:11480/hlsv2/fbx1/master.m3u8?mediaURL=x&maxWidth=1280";
    assert.equal(playback.withAudio(master, 1), master + "&fbxAudio=1");
    assert.equal(playback.withAudio(master + "&fbxAudio=1", 0), master + "&fbxAudio=0");

    assert.equal(playback.embeddedSubtitleUrl(SETTINGS, "x", master, subs[0]),
        "http://pc:11480/subtitles/embedded.vtt?path=%2Fhlsv2%2Ffbx1%2Fmaster.m3u8%3FmediaURL%3Dx%26maxWidth%3D1280&id=0&codec=subrip");

    const options = [{ kind: "off" }, { kind: "embedded", language: "eng" }, { kind: "external", language: "fre" }];
    assert.equal(playback.defaultSubtitle(options, [{ language: "eng" }]), 2);
    assert.equal(playback.defaultSubtitle(options, [{ language: "fre" }]), 0);
});

test("transcodage force apres un echec de lecture directe", async () => {
    const transport = {
        fetchJson: () => Promise.resolve({ format: { name: "matroska" },
            streams: [{ track: "video", codec: "h264" }, { track: "audio", codec: "aac" }] }),
        postJson: null
    };
    const direct = await playback.plan({ url: "https://cdn/x.mkv" }, SETTINGS, transport);
    assert.equal(direct.transcoded, false);
    const forced = await playback.plan({ url: "https://cdn/x.mkv" }, SETTINGS, transport, null, true);
    assert.ok(forced.transcoded);
    assert.match(forced.url, /forceTranscoding=1/);
});

test("sous-titres integres en segments : URLs de la playlist", () => {
    const master = "http://pc:11480/hlsv2/fbx1/master.m3u8?mediaURL=x&maxWidth=1280&fbxAudio=1";
    const s = playback.embeddedSubtitleStream(SETTINGS, "x", master, { id: 2, codec: "subrip" });
    assert.equal(s.playlist, "http://pc:11480/hlsv2/fbx1/subtitle2.m3u8?mediaURL=x&maxWidth=1280");
    assert.equal(s.needsMaster, false);
    const d = playback.embeddedSubtitleStream(SETTINGS, "http://cdn/f.mkv", "", { id: 0, codec: "ass" });
    assert.ok(d.needsMaster);
    assert.match(d.playlist, /^http:\/\/pc:11480\/hlsv2\/fbx[a-z0-9]+\/subtitle0\.m3u8\?mediaURL=http%3A%2F%2Fcdn%2Ff\.mkv/);
});

test("encodeur materiel : choix et parametre de conversion", () => {
    assert.equal(playback.bestProfile(["amf", "nvenc-win"], "auto"), "nvenc-win");
    assert.equal(playback.bestProfile(["amf"], "auto"), "amf");
    assert.equal(playback.bestProfile([], "auto"), "");
    assert.equal(playback.bestProfile(["nvenc-win"], "cpu"), "");
    const url = playback.hlsUrl(Object.assign({ profile: "nvenc-win" }, SETTINGS), "http://x/f.mkv", false);
    assert.match(url, /&profile=nvenc-win$/);
    assert.doesNotMatch(playback.hlsUrl(SETTINGS, "http://x/f.mkv", false), /profile=/);
});

test("sans PC : lecture directe sans analyse, torrents et proxy refuses, sous-titres tels quels", async () => {
    const NOPC = { server: "", companion: "", maxWidth: 1280 };
    const transport = { fetchJson: () => { throw new Error("aucun appel sans PC"); },
                        postJson: () => { throw new Error("aucun appel sans PC"); } };
    const p = await playback.plan({ url: "https://cdn/film.mkv" }, NOPC, transport);
    assert.equal(p.kind, "play");
    assert.equal(p.url, "https://cdn/film.mkv");
    assert.equal(p.transcoded, false);
    assert.equal((await playback.plan({ infoHash: "abc" }, NOPC, transport)).kind, "unsupported");
    assert.equal((await playback.plan({ url: "magnet:?xt=urn:btih:abc" }, NOPC, transport)).kind, "unsupported");
    assert.equal(playback.resolve({ url: "https://x/y", behaviorHints: { proxyHeaders: { request: {} } } }, NOPC).kind,
                 "unsupported");
    assert.equal(playback.subtitlesVttUrl(NOPC, "http://x/a.srt"), "http://x/a.srt");
});

test("fiche : addon traduit prefere a Cinemeta si demande", async () => {
    const asked = [];
    const client = addons.createClient(url => { asked.push(url); return Promise.resolve({ meta: { id: "tt1", name: url.indexOf("tmdb") !== -1 ? "Le Film" : "The Movie" } }); });
    const list = [
        { transportUrl: "https://v3-cinemeta.strem.io/manifest.json", manifest: { id: "com.linvo.cinemeta", resources: ["meta"], types: ["movie"], idPrefixes: ["tt"] } },
        { transportUrl: "https://tmdb.example/%7B%22language%22%3A%22fr-FR%22%7D/manifest.json", manifest: { id: "tmdb", resources: ["meta"], types: ["movie"], idPrefixes: ["tt"] } }
    ];
    assert.equal((await client.meta(list, "movie", "tt1")).name, "The Movie");
    assert.equal((await client.meta(list, "movie", "tt1", true)).name, "Le Film");
});
