.pragma library
// Catalogues du jour : les reponses des catalogues (addons, TMDB) sont gardees jusqu'au
// lendemain, en memoire et dans les Settings de l'appli (seul stockage permis sur la box, de
// taille limitee : titres reduits aux champs affiches, entrees prechargees gardees en priorite).

const MAX_CHARS = 1500000;               // ~1,5 Mo de JSON dans les Settings
const DESCRIPTION_CHARS = 240;

function dayOf(date) {
    const d = date || new Date();
    const pad = n => (n < 10 ? "0" : "") + n;
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
}

// { day, entries: { cle: reponse }, order: [cle] (ordre d'ajout), preloaded }
function create(day) {
    return { day: day, entries: {}, order: [], preloaded: false };
}

// Cache enregistre, s'il est du jour ; sinon un cache vide.
function parse(text, day) {
    try {
        const c = JSON.parse(text || "");
        if (c && c.day === day && c.entries && Array.isArray(c.order))
            return { day: day, entries: c.entries, order: c.order.filter(k => c.entries[k]), preloaded: !!c.preloaded };
    } catch (e) {
        // illisible : on repart de zero
    }
    return create(day);
}

// Cle d'une adresse : sans la cle API TMDB (jamais enregistree).
function key(url) {
    return String(url).replace(/([?&])api_key=[^&]*&?/, "$1").replace(/[?&]$/, "");
}

// Adresses gardees : catalogues d'addons (pas la recherche) et recherche avancee TMDB.
function cacheable(url) {
    const u = String(url);
    if (/\/discover\/(movie|tv)\?/.test(u))
        return true;
    return /\/catalog\//.test(u) && !/[\/&]search=/.test(u);
}

function cut(text, n) {
    const t = String(text || "");
    return t.length > n ? t.slice(0, n - 1) + "…" : t;
}

function compactMeta(m) {
    const out = {};
    ["id", "type", "name", "poster", "background", "logo", "posterShape", "releaseInfo", "year",
     "released", "imdbRating", "imdb_id", "tmdbRating"].forEach(k => {
        if (m[k] !== undefined && m[k] !== null && m[k] !== "")
            out[k] = m[k];
    });
    const genres = m.genres || m.genre;
    if (Array.isArray(genres) && genres.length)
        out.genres = genres.slice(0, 4);
    if (m.description)
        out.description = cut(m.description, DESCRIPTION_CHARS);
    return out;
}

function compactTmdb(r) {
    const out = {};
    ["id", "title", "name", "poster_path", "backdrop_path", "release_date", "first_air_date", "vote_average"].forEach(k => {
        if (r[k] !== undefined && r[k] !== null && r[k] !== "")
            out[k] = r[k];
    });
    if (r.overview)
        out.overview = cut(r.overview, DESCRIPTION_CHARS);
    return out;
}

// Reponse reduite aux champs utiles.
function compact(response) {
    if (response && Array.isArray(response.metas))
        return { metas: response.metas.map(compactMeta) };
    if (response && Array.isArray(response.results))
        return { page: response.page, total_pages: response.total_pages, results: response.results.map(compactTmdb) };
    return response;
}

function get(cache, url) {
    return cache.entries[key(url)] || null;
}

function put(cache, url, response) {
    const k = key(url);
    if (!cache.entries[k])
        cache.order.push(k);
    cache.entries[k] = compact(response);
    return cache.entries[k];
}

function count(cache) {
    return cache.order.length;
}

// Texte a enregistrer ; au-dela de maxChars, les dernieres entrees ajoutees sont laissees de cote
// (elles restent en memoire jusqu'a la fermeture de l'appli).
function serialize(cache, maxChars) {
    const max = maxChars || MAX_CHARS;
    const head = '{"day":' + JSON.stringify(cache.day) + ',"preloaded":' + (cache.preloaded ? "true" : "false");
    const parts = [];
    const kept = [];
    let size = head.length + 40;
    for (let i = 0; i < cache.order.length; i++) {
        const k = cache.order[i];
        const part = JSON.stringify(k) + ":" + JSON.stringify(cache.entries[k]);
        if (size + part.length + k.length + 4 > max)
            break;
        size += part.length + k.length + 4;
        parts.push(part);
        kept.push(k);
    }
    return head + ',"order":' + JSON.stringify(kept) + ',"entries":{' + parts.join(",") + "}}";
}

// Execute les taches (fonctions -> Promise) par lots de `parallel` ; onProgress(faites, total).
function runAll(tasks, parallel, onProgress) {
    let next = 0, done = 0;
    const total = tasks.length;
    return new Promise(resolve => {
        if (!total) {
            resolve();
            return;
        }
        const launch = () => {
            if (next >= total)
                return;
            const task = tasks[next++];
            const finish = () => {
                done++;
                if (onProgress)
                    onProgress(done, total);
                if (done === total)
                    resolve();
                else
                    launch();
            };
            let p;
            try {
                p = Promise.resolve(task());
            } catch (e) {
                p = Promise.resolve();
            }
            p.then(finish, finish);
        };
        for (let i = 0; i < Math.min(parallel || 4, total); i++)
            launch();
    });
}
