.pragma library
// Sous-titres integres charges par morceaux, comme un lecteur HLS : le serveur Stremio expose
// chaque piste en segments WebVTT de quelques secondes (subtitleN.m3u8). On ne demande que les
// segments autour de la position de lecture : quelques secondes au lieu de lire tout le fichier.

// Playlist HLS (texte) -> [{ start, end, url }] en millisecondes ; url resolue sur baseUrl.
function parsePlaylist(text, baseUrl) {
    const base = String(baseUrl).replace(/[?#].*$/, "").replace(/[^\/]*$/, "");
    const segments = [];
    let t = 0;
    let duration = null;
    String(text).replace(/\r/g, "").split("\n").forEach(line => {
        line = line.trim();
        if (line.indexOf("#EXTINF:") === 0) {
            duration = parseFloat(line.slice(8)) * 1000;
        } else if (line && line.charAt(0) !== "#" && duration !== null) {
            const url = /^https?:\/\//.test(line) ? line : base + line;
            segments.push({ start: Math.round(t), end: Math.round(t + duration), url: url });
            t += duration;
            duration = null;
        }
    });
    return segments;
}

// Indices des segments a charger pour la position donnee (pas deja charges ni en cours),
// les plus proches d'abord : un peu avant (saut arriere) et la minute qui suit.
function needed(segments, positionMs, done, behindMs, aheadMs) {
    const from = positionMs - (behindMs === undefined ? 10000 : behindMs);
    const to = positionMs + (aheadMs === undefined ? 60000 : aheadMs);
    const out = [];
    segments.forEach((s, i) => {
        if (s.end > from && s.start < to && !done[i])
            out.push(i);
    });
    return out.sort((a, b) => Math.abs(segments[a].start - positionMs) - Math.abs(segments[b].start - positionMs));
}

// Ajoute des cues sans doublons (les segments se recouvrent), triees par debut.
function merge(existing, added) {
    const seen = {};
    const out = [];
    existing.concat(added).forEach(c => {
        const k = c.start + "|" + c.end + "|" + c.text;
        if (!seen[k]) {
            seen[k] = true;
            out.push(c);
        }
    });
    return out.sort((a, b) => a.start - b.start);
}
