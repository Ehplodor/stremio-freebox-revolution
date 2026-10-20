.pragma library
// Tri et filtrage des flux selon des preferences modifiables (enregistrees sur le Player).
// Les informations sont lues dans le texte des flux (name, title/description, filename),
// au format courant des addons (Torrentio, Comet, StreamFusion...).

const CRITERIA = {
    addon: "Addon (ordre choisi ci-dessous)",
    cached: "En cache chez le debrideur",
    resolution: "Resolution",
    language: "Langue",
    direct: "Lisible sans transcodage (H.264)",
    size: "Taille (plus petit d'abord)",
    seeders: "Sources (seeders)"
};

const LANGUAGE_PRESETS = [
    { id: "fr", label: "Francais, multi, puis anglais", order: ["fr", "multi", "en"] },
    { id: "multi", label: "Multi, francais, puis anglais", order: ["multi", "fr", "en"] },
    { id: "en", label: "Anglais, multi, puis francais", order: ["en", "multi", "fr"] },
    { id: "none", label: "Aucune preference", order: [] }
];

const DEFAULT_PREFS = {
    order: ["addon", "cached", "resolution", "language", "direct", "size", "seeders"],
    addonOrder: [],           // noms d'addons, du prefere au moins prefere (vide : aucun ordre)
    maxResolution: 1080,      // le Player affiche au plus du 1080p ; au-dela, transcodage inutile
    languages: "fr",
    hideUncached: false,
    hideDolbyVision: true,    // couleurs fausses une fois transcode
    maxSizeGb: 0,             // 0 : pas de limite
    hideTiny: true            // fichiers < 300 Mo : extraits, bonus, faux fichiers
};

const RESOLUTION_CHOICES = [2160, 1080, 720];
const SIZE_CHOICES = [0, 5, 10, 20, 40];

// Complete des preferences enregistrees (eventuellement anciennes ou partielles).
function normalize(prefs) {
    const p = Object.assign({}, DEFAULT_PREFS, prefs || {});
    const known = Object.keys(CRITERIA);
    const order = (Array.isArray(p.order) ? p.order : []).filter((c, i, a) => known.indexOf(c) !== -1 && a.indexOf(c) === i);
    // Migration ponctuelle : ordre par defaut enregistre par une version de test qui placait
    // "direct" en dernier (19 octobre 2026).
    if (order.join() === "cached,resolution,language,size,seeders,direct")
        order.splice(3, 0, order.pop());
    // Critere absent (ajoute dans une version plus recente) : place apres son voisin par defaut.
    // "addon" va en tete : sans effet tant qu'aucun ordre d'addons n'est choisi.
    const defaults = DEFAULT_PREFS.order.filter(c => c !== "addon");
    defaults.forEach((c, i) => {
        if (order.indexOf(c) !== -1)
            return;
        const before = defaults.slice(0, i).reverse().find(x => order.indexOf(x) !== -1);
        order.splice(before ? order.indexOf(before) + 1 : order.length, 0, c);
    });
    if (order.indexOf("addon") === -1)
        order.unshift("addon");
    p.order = order;
    p.addonOrder = (Array.isArray(p.addonOrder) ? p.addonOrder : [])
        .filter((n, i, a) => typeof n === "string" && n && a.indexOf(n) === i);
    return p;
}

function textOf(stream) {
    const hints = stream.behaviorHints || {};
    return [stream.name, stream.title, stream.description, hints.filename].filter(x => x).join("\n");
}

const FLAGS = { "🇫🇷": "fr", "🇬🇧": "en", "🇺🇸": "en", "🇪🇸": "es", "🇮🇹": "it", "🇩🇪": "de", "🇯🇵": "ja", "🇷🇺": "ru" };

// Informations lues dans le texte d'un flux.
function parse(stream) {
    const text = textOf(stream);
    const lower = text.toLowerCase();
    const info = { resolution: 0, cached: null, languages: [], sizeGb: 0, seeders: -1, hdr: false, dv: false, codec: "" };

    if (/\b(2160p|4k|uhd)\b/i.test(text)) info.resolution = 2160;
    else if (/\b1080p\b/i.test(text)) info.resolution = 1080;
    else if (/\b720p\b/i.test(text)) info.resolution = 720;
    else if (/\b(480p|576p|sd|dvdrip)\b/i.test(text)) info.resolution = 480;

    // Debrideurs : [AD+] / [RD+] / ⚡ = deja en cache ; "download" / ⬇ = a telecharger.
    const name = String(stream.name || "");
    if (/\[(ad|rd|pm|tb|dl|ed|oc|pp)\+\]|⚡/i.test(name)) info.cached = true;
    else if (/download|⬇|\[(ad|rd|pm|tb|dl|ed|oc|pp)\]/i.test(name)) info.cached = false;

    info.dv = /\b(dv|dovi|dolby[ .-]?vision)\b/i.test(text);
    info.hdr = info.dv || /\bhdr(10\+?)?\b/i.test(text);
    if (/\b(x265|h\.?265|hevc)\b/i.test(text)) info.codec = "HEVC";
    else if (/\b(x264|h\.?264|avc)\b/i.test(text))
        // H.264 10 bits (Hi10P) : le Player ne le decode pas, il faudra transcoder.
        info.codec = /\b(10[ .-]?bits?|hi10p?)\b/i.test(text) ? "H.264 10 bits" : "H.264";
    else if (/\bav1\b/i.test(text)) info.codec = "AV1";

    const size = /💾\s*([\d.,]+)\s*(gb|go|mb|mo)/i.exec(text) || /\b([\d.,]+)\s*(gb|go)\b/i.exec(text);
    if (size)
        info.sizeGb = parseFloat(size[1].replace(",", ".")) / (/^m/i.test(size[2]) ? 1024 : 1);
    const seed = /👤\s*(\d+)/.exec(text);
    if (seed)
        info.seeders = parseInt(seed[1], 10);

    info.group = releaseGroup(stream);

    const langs = [];
    Object.keys(FLAGS).forEach(f => { if (text.indexOf(f) !== -1) langs.push(FLAGS[f]); });
    if (/\b(multi|vff?\+?vo|dual)\b/i.test(lower)) langs.push("multi");
    if (/\b(french|truefrench|vff|vfq|vf2|vfi|vf|fr|fre)\b/i.test(lower)) langs.push("fr");
    if (/\b(english|eng)\b/i.test(lower)) langs.push("en");
    info.languages = langs.filter((l, i) => langs.indexOf(l) === i);
    return info;
}

// Equipe de sortie ("FraMeSToR", "QxR"...) : fin du nom de fichier ou crochets.
function releaseGroup(stream) {
    const hints = stream.behaviorHints || {};
    const candidates = [hints.filename, String(stream.title || stream.description || "").split("\n")[0]];
    for (let i = 0; i < candidates.length; i++) {
        const t = String(candidates[i] || "").replace(/\.(mkv|mp4|avi|ts|m2ts)$/i, "").trim();
        let m = /-([A-Za-z0-9]{2,20})\)?$/.exec(t);
        if (m && !/^(\d+p|x26[45]|h26[45]|hevc|avc|dts|ac3|aac|web|dl)$/i.test(m[1]))
            return m[1].toLowerCase();
        m = /\[([A-Za-z0-9 .]{2,20})\]\s*$/.exec(t);
        if (m)
            return m[1].toLowerCase();
    }
    return "";
}

// Raison de masquer un flux selon les preferences, ou "".
function hiddenReason(info, prefs) {
    if (prefs.maxResolution && info.resolution > prefs.maxResolution)
        return "resolution " + info.resolution + "p";
    if (prefs.hideUncached && info.cached === false)
        return "pas en cache";
    if (prefs.hideDolbyVision && info.dv)
        return "Dolby Vision";
    if (prefs.hideTiny && info.sizeGb > 0 && info.sizeGb < 0.3)
        return "trop petit";
    if (prefs.maxSizeGb && info.sizeGb > prefs.maxSizeGb)
        return "taille " + info.sizeGb.toFixed(1) + " Go";
    return "";
}

function languageRank(info, prefs) {
    const preset = LANGUAGE_PRESETS.find(p => p.id === prefs.languages) || LANGUAGE_PRESETS[0];
    let best = preset.order.length;
    info.languages.forEach(l => {
        const i = preset.order.indexOf(l);
        if (i !== -1 && i < best)
            best = i;
    });
    return best;
}

function addonRank(name, prefs) {
    const i = (prefs.addonOrder || []).indexOf(name);
    return i === -1 ? 1000 : i;
}

// Ordre complet des addons : ceux deja ordonnes, puis les nouveaux (dans l'ordre recu).
function mergedAddonOrder(prefs, names) {
    const order = (prefs.addonOrder || []).slice();
    (names || []).forEach(n => { if (n && order.indexOf(n) === -1) order.push(n); });
    return order;
}

// Comparaison selon un critere : negatif si a passe avant b.
function compareBy(criterion, a, b, prefs) {
    switch (criterion) {
    case "addon": return addonRank(a.addon, prefs) - addonRank(b.addon, prefs);
    case "cached": return (b.info.cached === true) - (a.info.cached === true) || (a.info.cached === false) - (b.info.cached === false);
    case "resolution": return b.info.resolution - a.info.resolution;
    case "language": return languageRank(a.info, prefs) - languageRank(b.info, prefs);
    case "direct": return (b.info.codec === "H.264") - (a.info.codec === "H.264");
    case "size": return (a.info.sizeGb || 1e9) - (b.info.sizeGb || 1e9);
    case "seeders": return b.info.seeders - a.info.seeders;
    default: return 0;
    }
}

// items : [{ addon, stream }] -> { visible: [...], hidden: n } ; chaque element recoit info et badges.
function sortStreams(items, prefsIn) {
    const prefs = normalize(prefsIn);
    const visible = [];
    let hidden = 0;
    items.forEach((item, index) => {
        const info = item.info || parse(item.stream);
        const entry = Object.assign({}, item, { info: info, index: index, badges: badges(info) });
        if (hiddenReason(info, prefs))
            hidden++;
        else
            visible.push(entry);
    });
    visible.sort((a, b) => {
        for (let i = 0; i < prefs.order.length; i++) {
            const c = compareBy(prefs.order[i], a, b, prefs);
            if (c)
                return c;
        }
        return a.index - b.index;             // ordre d'arrivee en dernier recours
    });
    return { visible: visible, hidden: hidden };
}

function badges(info) {
    const out = [];
    if (info.cached === true) out.push("En cache");
    if (info.cached === false) out.push("A telecharger");
    if (info.resolution) out.push(info.resolution >= 2160 ? "4K" : info.resolution + "p");
    if (info.dv) out.push("Dolby Vision");
    else if (info.hdr) out.push("HDR");
    if (info.codec) out.push(info.codec);
    if (info.languages.length) out.push(info.languages.map(l => l.toUpperCase()).join("/"));
    if (info.sizeGb) out.push(info.sizeGb < 1 ? Math.round(info.sizeGb * 1024) + " Mo" : info.sizeGb.toFixed(1) + " Go");
    if (info.seeders >= 0) out.push(info.seeders + " sources");
    return out.join(" · ");
}

// ----- Edition des preferences (ecran Tri des sources) -----

function cycle(list, value, step) {
    const i = list.indexOf(value);
    return list[((i === -1 ? 0 : i) + step + list.length) % list.length];
}

// Lignes de l'ecran de reglages : [{ key, label, value }]
function settingsRows(prefsIn, addonNames) {
    const p = normalize(prefsIn);
    const rows = p.order.map((c, i) => ({ key: "order:" + c, label: "Critere " + (i + 1), value: CRITERIA[c] }));
    const preset = LANGUAGE_PRESETS.find(x => x.id === p.languages) || LANGUAGE_PRESETS[0];
    rows.push({ key: "languages", label: "Langues", value: preset.label });
    rows.push({ key: "maxResolution", label: "Resolution maximale", value: p.maxResolution >= 2160 ? "4K (tout)" : p.maxResolution + "p" });
    rows.push({ key: "hideUncached", label: "Masquer ce qui n'est pas en cache", value: p.hideUncached ? "Oui" : "Non" });
    rows.push({ key: "hideDolbyVision", label: "Masquer Dolby Vision", value: p.hideDolbyVision ? "Oui" : "Non" });
    rows.push({ key: "maxSizeGb", label: "Taille maximale", value: p.maxSizeGb ? p.maxSizeGb + " Go" : "Aucune" });
    rows.push({ key: "hideTiny", label: "Masquer les fichiers trop petits (< 300 Mo)", value: p.hideTiny ? "Oui" : "Non" });
    mergedAddonOrder(p, addonNames).forEach((name, i) => {
        rows.push({ key: "addon:" + name, label: "Addon " + (i + 1), value: name });
    });
    rows.push({ key: "reset", label: "Revenir aux reglages par defaut", value: "" });
    return rows;
}

// Gauche/Droite (step -1/+1) ou OK (step 0) sur une ligne : nouvelles preferences.
// Sur un critere, Gauche/Droite le fait monter ou descendre dans l'ordre.
function edit(prefsIn, key, step, addonNames) {
    const p = normalize(prefsIn);
    if (key.indexOf("addon:") === 0) {
        const order = mergedAddonOrder(p, addonNames);
        const name = key.slice(6);
        const i = order.indexOf(name);
        const j = i + (step || 0);
        if (i !== -1 && step && j >= 0 && j < order.length) {
            order.splice(i, 1);
            order.splice(j, 0, name);
        }
        p.addonOrder = order;
        return p;
    }
    if (key.indexOf("order:") === 0) {
        const c = key.slice(6);
        const i = p.order.indexOf(c);
        const j = i + (step || 0);
        if (step && j >= 0 && j < p.order.length) {
            p.order.splice(i, 1);
            p.order.splice(j, 0, c);
        }
        return p;
    }
    const dir = step || 1;
    switch (key) {
    case "languages": p.languages = cycle(LANGUAGE_PRESETS.map(x => x.id), p.languages, dir); break;
    case "maxResolution": p.maxResolution = cycle(RESOLUTION_CHOICES, p.maxResolution, dir); break;
    case "hideUncached": p.hideUncached = !p.hideUncached; break;
    case "hideDolbyVision": p.hideDolbyVision = !p.hideDolbyVision; break;
    case "hideTiny": p.hideTiny = !p.hideTiny; break;
    case "maxSizeGb": p.maxSizeGb = cycle(SIZE_CHOICES, p.maxSizeGb, dir); break;
    case "reset": return normalize(null);
    }
    return p;
}

// ----- Episode suivant : source la plus proche de la precedente -----

// Ressemblance entre la source jouee (entree triee : { addon, info }) et une candidate.
function similarity(prev, cand) {
    const a = prev.info, b = cand.info;
    let score = 0;
    if (prev.addon === cand.addon) score += 100;
    if (a.group && a.group === b.group) score += 60;
    if (a.resolution && a.resolution === b.resolution) score += 30;
    if (a.codec && a.codec === b.codec) score += 15;
    if (a.languages.length && a.languages.some(l => b.languages.indexOf(l) !== -1)) score += 20;
    if (a.languages.length && a.languages.length === b.languages.length
            && a.languages.every(l => b.languages.indexOf(l) !== -1)) score += 10;
    if (a.hdr === b.hdr) score += 5;
    if (b.cached === true) score += 12;
    if (b.cached === false) score -= 12;
    if (a.sizeGb && b.sizeGb) {
        const ratio = Math.min(a.sizeGb, b.sizeGb) / Math.max(a.sizeGb, b.sizeGb);
        score += Math.round(10 * ratio);
    }
    return score;
}

// Candidate la plus proche ; a egalite, l'ordre du tri decide. null si liste vide.
function closest(prev, candidates) {
    let best = null;
    let bestScore = -Infinity;
    candidates.forEach(c => {
        const sc = similarity(prev, c);
        if (sc > bestScore) {
            best = c;
            bestScore = sc;
        }
    });
    return best;
}
