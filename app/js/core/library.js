.pragma library
// Bibliotheque Stremio (LibraryItem) : progression de lecture ecrite comme le fait Stremio, pour
// que « Continuer a regarder » soit le meme sur la box, le PC et le telephone.
//
// Format et regles transposes de stremio-core (src/types/library/library_item.rs,
// src/models/player.rs), licence MIT, Copyright (c) 2018 Smart Code OOD. Voir NOTICE.md.
// Le champ `watched` (bitfield des episodes vus) est conserve tel quel : V2.3.

const WATCHED_RATIO = 0.7;         // Stremio : vu quand timeWatched depasse 70 % de la duree
const ENDED_RATIO = 0.93;          // fin de la video : sort de « Continuer a regarder »
const MAX_LOCAL = 60;              // sans compte : elements gardes sur le Player

function iso(ms) {
    return new Date(ms).toISOString();
}

// Nouvel element a partir d'une fiche (Stremio : ouvert sans etre ajoute -> removed = temp = true).
function fromMeta(meta, now) {
    return {
        _id: meta.id,
        name: meta.name || "",
        type: meta.type,
        poster: meta.poster || null,
        posterShape: meta.posterShape || "poster",
        removed: true,
        temp: true,
        _ctime: iso(now),
        _mtime: iso(now),
        behaviorHints: meta.behaviorHints && typeof meta.behaviorHints === "object" ? meta.behaviorHints : {},
        state: {
            lastWatched: iso(now),
            timeWatched: 0,
            timeOffset: 0,
            overallTimeWatched: 0,
            timesWatched: 0,
            flaggedWatched: 0,
            duration: 0,
            video_id: null,
            watched: null,
            noNotif: false
        }
    };
}

// Progression de lecture. watchedMs : temps reellement regarde depuis la mise a jour precedente.
// Renvoie un nouvel element (l'ancien n'est pas modifie).
function updateProgress(item, videoId, positionMs, durationMs, watchedMs, now) {
    const out = JSON.parse(JSON.stringify(item));
    const s = Object.assign({ timeWatched: 0, timeOffset: 0, overallTimeWatched: 0, timesWatched: 0,
                              flaggedWatched: 0, duration: 0, video_id: null, watched: null, noNotif: false },
                            out.state || {});
    if (s.video_id !== videoId) {
        // Autre episode : le temps regarde repart de zero (comme stremio-core).
        s.video_id = videoId;
        s.timeWatched = 0;
        s.flaggedWatched = 0;
    }
    const watched = Math.max(0, Math.round(watchedMs || 0));
    const duration = Math.max(0, Math.round(durationMs || 0));
    s.duration = duration || s.duration;
    s.timeWatched += watched;
    s.overallTimeWatched += watched;
    s.lastWatched = iso(now);
    s.timeOffset = Math.max(1, Math.round(positionMs));
    if (s.duration > 0 && s.timeWatched > s.duration * WATCHED_RATIO && !s.flaggedWatched) {
        s.flaggedWatched = 1;
        s.timesWatched += 1;
    }
    // Fin de la video : plus rien a reprendre.
    if (s.duration > 0 && positionMs / s.duration >= ENDED_RATIO)
        s.timeOffset = 0;
    out.state = s;
    // Retire par l'utilisateur mais regarde a nouveau : temporaire (visible dans « Continuer »).
    if (out.removed)
        out.temp = true;
    out._mtime = iso(now);
    return out;
}

// Remplace (ou ajoute) un element dans une liste ; renvoie une nouvelle liste.
function upsert(items, item) {
    const out = (items || []).filter(i => i._id !== item._id);
    out.unshift(item);
    return out;
}

// Copie locale (sans compte) : elements de « Continuer a regarder » les plus recents seulement.
function trimLocal(items) {
    return (items || []).slice().sort((a, b) => (Date.parse(b._mtime) || 0) - (Date.parse(a._mtime) || 0))
        .slice(0, MAX_LOCAL);
}
