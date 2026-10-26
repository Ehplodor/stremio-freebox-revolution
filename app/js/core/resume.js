.pragma library
// Reprise de lecture, episode suivant et langues preferees. Fonctions pures (testees sous Node).

const MAX_ENTRIES = 300;
const MIN_RESUME_MS = 30000;       // en dessous : on repart du debut
const DONE_RATIO = 0.93;           // au-dela : considere comme vu

// positions : { cle: { t, d, at } } ; cle = compte + identifiant de la video.
function key(accountId, videoId) {
    return (accountId || "local") + "|" + videoId;
}

function record(positions, accountId, videoId, timeMs, durationMs, now) {
    const out = Object.assign({}, positions || {});
    const k = key(accountId, videoId);
    if (durationMs > 0 && timeMs / durationMs >= DONE_RATIO)
        out[k] = { t: 0, d: durationMs, at: now, done: true };
    else if (timeMs >= MIN_RESUME_MS)
        out[k] = { t: Math.round(timeMs), d: Math.round(durationMs || 0), at: now };
    else
        return out;
    // Garde les plus recentes : le stockage du Player est petit.
    const keys = Object.keys(out);
    if (keys.length > MAX_ENTRIES) {
        keys.sort((a, b) => out[b].at - out[a].at).slice(MAX_ENTRIES).forEach(x => delete out[x]);
    }
    return out;
}

// Position ou reprendre (ms), ou 0.
function resumeAt(positions, accountId, videoId) {
    const e = (positions || {})[key(accountId, videoId)];
    return e && !e.done && e.t >= MIN_RESUME_MS ? e.t : 0;
}

// Avancement 0..1 pour une barre de progression (1 si vu).
function progress(positions, accountId, videoId) {
    const e = (positions || {})[key(accountId, videoId)];
    if (!e)
        return 0;
    if (e.done)
        return 1;
    return e.d > 0 ? Math.min(1, e.t / e.d) : 0;
}

// Episode suivant d'une serie (saison 0 = bonus, ignoree), ou null.
function nextEpisode(meta, videoId) {
    const videos = ((meta && meta.videos) || [])
        .filter(v => typeof v.season === "number" && v.season > 0)
        .slice()
        .sort((a, b) => a.season - b.season || (a.episode || a.number || 0) - (b.episode || b.number || 0));
    const i = videos.findIndex(v => v.id === videoId);
    return i !== -1 && i + 1 < videos.length ? videos[i + 1] : null;
}

// ----- Langues preferees -----

const LANG_CODES = {
    fr: ["fre", "fra", "fr"],
    en: ["eng", "en"],
    es: ["spa", "es"],
    de: ["ger", "deu", "de"],
    it: ["ita", "it"],
    ja: ["jpn", "ja"]
};

function matches(code, pref) {
    return (LANG_CODES[pref] || [pref]).indexOf(String(code || "").toLowerCase()) !== -1;
}

// Index de la piste audio a jouer : langue preferee si presente, sinon la premiere.
// pref : "auto" | "fr" | "en" | ... ; "vo" = premiere piste.
function pickAudio(tracks, pref) {
    if (!tracks || !tracks.length || !pref || pref === "auto" || pref === "vo")
        return 0;
    const i = tracks.findIndex(t => matches(t.language, pref));
    return i === -1 ? 0 : i;
}

// Index des sous-titres (0 = desactives).
// pref : "auto" (francais si l'audio n'est pas en francais), "off", ou une langue.
function pickSubtitle(options, pref, audioLanguage) {
    if (!options || options.length < 2 || pref === "off")
        return 0;
    const lang = !pref || pref === "auto" ? (matches(audioLanguage, "fr") ? "" : "fr") : pref;
    if (!lang)
        return 0;
    // Integres d'abord (synchronises avec la video), puis ceux des addons.
    const i = options.findIndex(o => o.kind === "embedded" && matches(o.language, lang));
    if (i !== -1)
        return i;
    const j = options.findIndex(o => o.kind !== "off" && matches(o.language, lang));
    return j === -1 ? 0 : j;
}

// Episode a proposer en ouvrant une serie : celui en cours le plus recent, sinon le suivant
// du dernier episode vu, sinon null (premiere visite).
// libraryItem (facultatif) : element de la bibliotheque Stremio (reprise faite sur un autre
// appareil) ; le plus recent des deux l'emporte.
function seriesResume(meta, positions, accountId, libraryItem) {
    const fromLibrary = libraryResume(meta, libraryItem);
    const local = localSeriesResume(meta, positions, accountId);
    if (!fromLibrary)
        return local ? local.video : null;
    if (!local || fromLibrary.at > local.at)
        return fromLibrary.video;
    return local.video;
}

function libraryResume(meta, item) {
    const s = item && item.state;
    if (!s || !s.video_id)
        return null;
    const video = ((meta && meta.videos) || []).find(v => v.id === s.video_id);
    if (!video)
        return null;
    const at = Date.parse(s.lastWatched || item._mtime || "") || 0;
    // Episode termine (plus de position) et vu : le suivant.
    const ended = !(s.timeOffset > 0) && s.flaggedWatched;
    return { video: ended ? nextEpisode(meta, video.id) || video : video, at: at };
}

function localSeriesResume(meta, positions, accountId) {
    const videos = ((meta && meta.videos) || []).filter(v => typeof v.season === "number" && v.season > 0);
    let best = null;
    let bestAt = -1;
    videos.forEach(v => {
        const e = (positions || {})[key(accountId, v.id)];
        if (e && e.at > bestAt) {
            best = { video: v, entry: e };
            bestAt = e.at;
        }
    });
    if (!best)
        return null;
    return { video: best.entry.done ? nextEpisode(meta, best.video.id) : best.video, at: best.entry.at };
}
