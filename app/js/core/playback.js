.pragma library
// Choix de la facon de lire un flux Stremio sur le Freebox Player Revolution.
//
// Logique transposee de stremio-video (src/withStreamingServer : convertStream,
// createTorrent, buildProxyUrl, canPlayProbe), licence MIT,
// Copyright (c) 2018 Smart Code OOD. Voir NOTICE.md.
//
// Adaptations Freebox (docs/ETAPE0-RESULTATS.md) :
// - le Player decode H.264 seulement (pas de HEVC/VP9/AV1) ;
// - les flux HLS transcodes passent par le service compagnon du PC, qui retire la piste
//   de sous-titres du master.m3u8 (le lecteur HLS du Player se bloque dessus) ;
// - maxWidth=1280 par defaut : ecran 720p et environ 9 Mbit/s entre le PC et la box.

const BOX = {
    formats: ["mp4", "mov", "matroska", "mpegts", "avi"],
    videoCodecs: ["h264"],
    // AC3/E-AC3/DTS sont lus en direct (image OK) ; le son reste a confirmer a l'oreille.
    // Par prudence le transcodage les convertit en AAC stereo.
    audioCodecs: ["aac", "mp3"],
    directAudioCodecs: ["aac", "mp3", "ac3", "eac3"],
    maxAudioChannels: 2,
    maxWidth: 1280
};

// settings : { server: "http://pc:11470", companion: "http://pc:11480", maxWidth }

function randomId() {
    return "fbx" + Math.floor(Math.random() * 1e12).toString(36);
}

function query(pairs) {
    return pairs.map(p => encodeURIComponent(p[0]) + "=" + encodeURIComponent(String(p[1]))).join("&");
}

function torrentUrl(server, infoHash, fileIdx, sources) {
    const tr = (sources || []).map(s => ["tr", s]);
    return server + "/" + encodeURIComponent(infoHash) + "/" + encodeURIComponent(fileIdx)
        + (tr.length ? "?" + query(tr) : "");
}

function proxyUrl(server, streamUrl, requestHeaders, responseHeaders) {
    const m = /^(https?:\/\/[^\/?#]+)([^?#]*)(\?[^#]*)?/.exec(streamUrl);
    if (!m)
        throw new Error("URL de flux invalide : " + streamUrl);
    const opts = [["d", m[1]]];
    Object.keys(requestHeaders || {}).forEach(k => opts.push(["h", k + ":" + requestHeaders[k]]));
    Object.keys(responseHeaders || {}).forEach(k => opts.push(["r", k + ":" + responseHeaders[k]]));
    return server + "/proxy/" + query(opts) + (m[2] || "/") + (m[3] || "");
}

// URL HLS H.264/AAC produite par le serveur de streaming, via le compagnon.
function hlsUrl(settings, mediaUrl, force) {
    const pairs = [["mediaURL", mediaUrl]];
    if (force)
        pairs.push(["forceTranscoding", "1"]);
    BOX.videoCodecs.forEach(c => pairs.push(["videoCodecs", c]));
    BOX.audioCodecs.forEach(c => pairs.push(["audioCodecs", c]));
    pairs.push(["maxAudioChannels", BOX.maxAudioChannels]);
    pairs.push(["maxWidth", settings.maxWidth || BOX.maxWidth]);
    // Encodeur materiel (carte graphique) : 6x plus rapide que le processeur sur le PC de Rod.
    if (settings.profile)
        pairs.push(["profile", settings.profile]);
    return (settings.companion || settings.server) + "/hlsv2/" + randomId() + "/master.m3u8?" + query(pairs);
}

function probeUrl(settings, mediaUrl) {
    return settings.server + "/hlsv2/probe?" + query([["mediaURL", mediaUrl]]);
}

// Le Player peut-il lire ce fichier tel quel ? (d'apres /hlsv2/probe)
function canPlayDirect(probe) {
    if (!probe || !probe.format || !Array.isArray(probe.streams))
        return false;
    const formatOk = BOX.formats.some(f => probe.format.name.indexOf(f) !== -1);
    const audio = probe.streams.filter(s => s.track === "audio");
    const streamsOk = probe.streams.every(s => {
        if (s.track === "video")
            return BOX.videoCodecs.indexOf(s.codec) !== -1 && !s.isHdr && !(s.width > 1920);
        if (s.track === "audio")
            return BOX.directAudioCodecs.indexOf(s.codec) !== -1;
        return true;
    });
    // Plusieurs pistes audio : QtMultimedia ne permet pas de choisir, on transcode la premiere.
    return formatOk && streamsOk && audio.length < 2;
}

// Premiere etape : ce qu'il faut demander au serveur pour obtenir une URL de media.
// Renvoie { kind, mediaUrl?, create?, external?, reason? }
//   kind "media"   : mediaUrl est lisible par le serveur (HTTP direct, proxy ou torrent connu)
//   kind "torrent" : il faut d'abord POST create (create = { url, body }) puis torrentUrl
//   kind "external": a ouvrir hors de l'appli (externalUrl, YouTube)
function resolve(stream, settings, seriesInfo) {
    if (typeof stream.url === "string" && stream.url.indexOf("magnet:") === 0) {
        const m = /xt=urn:btih:([a-zA-Z0-9]+)/.exec(stream.url);
        if (!m)
            return { kind: "unsupported", reason: "lien magnet illisible" };
        const trackers = [];
        stream.url.replace(/[?&]tr=([^&]+)/g, (all, tr) => { trackers.push("tracker:" + decodeURIComponent(tr)); });
        return torrent(settings, m[1].toLowerCase(), null, trackers, seriesInfo);
    }
    if (typeof stream.url === "string") {
        const hints = stream.behaviorHints || {};
        const headers = hints.proxyHeaders;
        if (headers)
            return { kind: "media", mediaUrl: proxyUrl(settings.server, stream.url, headers.request, headers.response),
                     notWebReady: true };
        return { kind: "media", mediaUrl: stream.url, notWebReady: !!hints.notWebReady };
    }
    if (typeof stream.infoHash === "string")
        return torrent(settings, stream.infoHash.toLowerCase(), stream.fileIdx, stream.sources, seriesInfo);
    if (typeof stream.externalUrl === "string")
        return { kind: "external", external: stream.externalUrl };
    if (typeof stream.ytId === "string")
        return { kind: "external", external: "https://www.youtube.com/watch?v=" + stream.ytId };
    return { kind: "unsupported", reason: "flux sans url, infoHash ni lien externe" };
}

function torrent(settings, infoHash, fileIdx, sources, seriesInfo) {
    const hasIdx = fileIdx !== null && fileIdx !== undefined && isFinite(fileIdx);
    if (hasIdx && !(sources && sources.length))
        return { kind: "media", mediaUrl: torrentUrl(settings.server, infoHash, fileIdx), torrent: true };

    const body = { torrent: { infoHash: infoHash } };
    if (sources && sources.length) {
        const all = ["dht:" + infoHash].concat(sources.map(s =>
            s.indexOf("tracker:") === 0 || s.indexOf("dht:") === 0 ? s : "tracker:" + s));
        body.peerSearch = { sources: all.filter((s, i) => all.indexOf(s) === i), min: 40, max: 200 };
    }
    if (hasIdx) {
        body.guessFileIdx = false;
    } else {
        body.guessFileIdx = {};
        if (seriesInfo && isFinite(seriesInfo.season))
            body.guessFileIdx.season = seriesInfo.season;
        if (seriesInfo && isFinite(seriesInfo.episode))
            body.guessFileIdx.episode = seriesInfo.episode;
    }
    return {
        kind: "torrent",
        infoHash: infoHash,
        fileIdx: hasIdx ? fileIdx : null,
        create: { url: settings.server + "/" + encodeURIComponent(infoHash) + "/create", body: body }
    };
}

// URL du torrent une fois create fait (reponse du serveur : { guessedFileIdx, ... }).
function torrentMediaUrl(settings, resolved, createResponse) {
    const idx = resolved.fileIdx !== null ? resolved.fileIdx : createResponse.guessedFileIdx;
    const sources = resolved.create.body.peerSearch ? resolved.create.body.peerSearch.sources : [];
    return torrentUrl(settings.server, resolved.infoHash, idx, sources);
}

// Derniere etape : URL a donner au lecteur, d'apres le probe (null si probe en echec).
function playUrl(settings, mediaUrl, probe, forceTranscoding) {
    if (!forceTranscoding && canPlayDirect(probe))
        return { url: mediaUrl, transcoded: false };
    return { url: hlsUrl(settings, mediaUrl, !!forceTranscoding), transcoded: true };
}

// Chaine complete avec un transport : fetchJson(url) et postJson(url, body) -> Promise.
function plan(stream, settings, transport, seriesInfo, forceTranscoding) {
    const r = resolve(stream, settings, seriesInfo);
    if (r.kind === "external" || r.kind === "unsupported")
        return Promise.resolve(r);
    const media = r.kind === "torrent"
        ? transport.postJson(r.create.url, r.create.body).then(resp => torrentMediaUrl(settings, r, resp))
        : Promise.resolve(r.mediaUrl);
    return media.then(mediaUrl =>
        transport.fetchJson(probeUrl(settings, mediaUrl))
            .catch(() => null)
            .then(probe => {
                const p = playUrl(settings, mediaUrl, probe, forceTranscoding);
                p.kind = "play";
                p.mediaUrl = mediaUrl;
                p.probe = probe;
                return p;
            }));
}

// Sous-titres externes (SRT, VTT...) convertis en VTT par le serveur.
function subtitlesVttUrl(settings, url) {
    return settings.server + "/subtitles.vtt?" + query([["from", url]]);
}

// ----- Pistes audio et sous-titres -----

const LANGUAGES = {
    fre: "Francais", fra: "Francais", fr: "Francais", eng: "Anglais", en: "Anglais",
    spa: "Espagnol", es: "Espagnol", ger: "Allemand", deu: "Allemand", de: "Allemand",
    ita: "Italien", it: "Italien", por: "Portugais", pt: "Portugais", jpn: "Japonais", ja: "Japonais",
    dut: "Neerlandais", nld: "Neerlandais", ara: "Arabe", rus: "Russe", chi: "Chinois", zho: "Chinois",
    kor: "Coreen", pol: "Polonais", tur: "Turc", swe: "Suedois", dan: "Danois", nor: "Norvegien"
};

function languageName(code) {
    if (!code)
        return "";
    return LANGUAGES[String(code).toLowerCase()] || code;
}

function isFrench(code) {
    return /^(fre|fra|fr)$/i.test(code || "");
}

function trackLabel(s, index) {
    const parts = [];
    if (s.language)
        parts.push(languageName(s.language));
    if (s.title && s.title !== s.language)
        parts.push(s.title);
    if (!parts.length)
        parts.push("Piste " + (index + 1));
    const tech = [s.codec ? String(s.codec).toUpperCase() : "", s.channels ? s.channels + " canaux" : ""]
        .filter(x => x).join(" ");
    return parts.join(" - ") + (tech ? " (" + tech + ")" : "");
}

// Pistes audio du probe : [{ id, label, language }]
function audioTracks(probe) {
    if (!probe || !Array.isArray(probe.streams))
        return [];
    return probe.streams.filter(s => s.track === "audio")
        .map((s, i) => ({ id: s.id, label: trackLabel(s, i), language: s.language || "" }));
}

// Sous-titres integres du probe : [{ id, codec, label, language }]
function embeddedSubtitles(probe) {
    if (!probe || !Array.isArray(probe.streams))
        return [];
    return probe.streams.filter(s => s.track === "subtitle" && /^(subrip|srt|ass|ssa|webvtt|mov_text|text)$/.test(s.codec))
        .map((s, i) => ({ id: s.id, codec: s.codec, label: trackLabel({ language: s.language, title: s.title }, i),
                          language: s.language || "" }));
}

// Master HLS avec une seule piste audio (filtre du service compagnon).
function withAudio(masterUrl, audioId) {
    const clean = masterUrl.replace(/&fbxAudio=[^&]*/, "");
    return audioId === null || audioId === undefined ? clean : clean + "&fbxAudio=" + encodeURIComponent(audioId);
}

// VTT complet d'une piste integree, assemble par le service compagnon.
// masterUrl : URL HLS en cours (transcodage) ; sinon on en fabrique une pour le serveur.
function embeddedSubtitleUrl(settings, mediaUrl, masterUrl, sub) {
    const master = masterUrl || hlsUrl(settings, mediaUrl, false);
    const path = master.replace(/^https?:\/\/[^\/]+/, "");
    return (settings.companion || settings.server) + "/subtitles/embedded.vtt?" + query([
        ["path", path], ["id", sub.id], ["codec", sub.codec]
    ]);
}

// Piste integree en segments HLS : { master, playlist, needsMaster }.
// En transcodage, le master en cours de lecture a deja cree le convertisseur sur le serveur ;
// en lecture directe, il faut d'abord demander un master (sans le lire) pour le creer.
function embeddedSubtitleStream(settings, mediaUrl, masterUrl, sub) {
    const master = masterUrl || hlsUrl(settings, mediaUrl, false);
    const parts = master.split("?");
    const folder = parts[0].replace(/\/master\.m3u8$/, "");
    const query = (parts[1] || "").replace(/&?fbxAudio=[^&]*/, "");
    return {
        master: master,
        playlist: folder + "/subtitle" + encodeURIComponent(sub.id) + ".m3u8" + (query ? "?" + query : ""),
        needsMaster: !masterUrl
    };
}

// Choix des sous-titres au demarrage : francais si la premiere piste audio n'est pas en francais.
function defaultSubtitle(options, audio) {
    if (audio.length && isFrench(audio[0].language))
        return 0;
    const i = options.findIndex(o => o.kind !== "off" && isFrench(o.language));
    return i === -1 ? 0 : i;
}

// Encodeur a demander au serveur : NVIDIA, puis AMD, puis Intel ; "" = processeur.
// profiles : liste annoncee par le serveur (allTranscodeProfiles).
function bestProfile(profiles, mode) {
    if (mode === "cpu" || !Array.isArray(profiles))
        return "";
    const order = ["nvenc-win", "nvenc", "amf", "qsv-win", "qsv", "vaapi", "videotoolbox"];
    for (let i = 0; i < order.length; i++) {
        if (profiles.indexOf(order[i]) !== -1)
            return order[i];
    }
    return profiles.length ? profiles[0] : "";
}
