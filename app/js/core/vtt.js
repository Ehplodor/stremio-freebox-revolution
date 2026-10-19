.pragma library
// Lecture de sous-titres WebVTT pour un calque Text QML (le lecteur du Player ne les affiche pas).

function parseTime(t) {
    const m = /(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{1,3})/.exec(t);
    if (!m)
        return NaN;
    return ((parseInt(m[1] || "0", 10) * 60 + parseInt(m[2], 10)) * 60 + parseInt(m[3], 10)) * 1000
        + parseInt((m[4] + "00").slice(0, 3), 10);
}

// Texte VTT -> [{ start, end, text }] en millisecondes, trie par debut.
function parse(text) {
    const cues = [];
    const blocks = String(text).replace(/\r/g, "").split(/\n{2,}/);
    blocks.forEach(block => {
        const lines = block.split("\n");
        const i = lines.findIndex(l => l.indexOf("-->") !== -1);
        if (i === -1)
            return;
        const parts = lines[i].split("-->");
        const start = parseTime(parts[0]);
        const end = parseTime(parts[1]);
        if (isNaN(start) || isNaN(end))
            return;
        const body = lines.slice(i + 1).join("\n").replace(/<[^>]+>/g, "").trim();
        if (body)
            cues.push({ start: start, end: end, text: body });
    });
    return cues.sort((a, b) => a.start - b.start);
}

// Texte a afficher a positionMs (plusieurs cues simultanes joints par un saut de ligne).
function textAt(cues, positionMs) {
    const out = [];
    for (let i = 0; i < cues.length && cues[i].start <= positionMs; i++) {
        if (positionMs < cues[i].end)
            out.push(cues[i].text);
    }
    return out.join("\n");
}
