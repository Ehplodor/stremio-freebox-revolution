.pragma library
// Client du protocole d'addons Stremio (https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/protocol.md).
// Le transport HTTP est injecte (fetchJson(url) -> Promise), pour tourner a l'identique
// dans QML (XMLHttpRequest) et dans les tests Node.
// Le runtime du Player est Qt 5.15 : JavaScript ES2016 disponible (etape 0).

const DEFAULT_ADDONS = [
    "https://v3-cinemeta.strem.io/manifest.json",
    "https://opensubtitles-v3.strem.io/manifest.json"
];

// "https://x/manifest.json" -> "https://x"
function baseUrl(transportUrl) {
    return transportUrl.replace(/\/manifest\.json$/, "").replace(/\/+$/, "");
}

// extra : objet { search: "dark", skip: 100 } -> "search=dark&skip=100"
function extraPath(extra) {
    if (!extra)
        return "";
    const parts = [];
    Object.keys(extra).forEach(key => {
        const value = extra[key];
        if (value === undefined || value === null || value === "")
            return;
        (Array.isArray(value) ? value : [value]).forEach(v => {
            parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(v)));
        });
    });
    return parts.join("&");
}

// /{resource}/{type}/{id}[/{extra}].json
function resourceUrl(transportUrl, resource, type, id, extra) {
    const tail = extraPath(extra);
    return baseUrl(transportUrl) + "/" + resource + "/" + encodeURIComponent(type) + "/"
        + encodeURIComponent(id) + (tail ? "/" + tail : "") + ".json";
}

// Les ressources d'un manifest sont des chaines ou des objets { name, types, idPrefixes }.
function supports(manifest, resource, type, id) {
    const resources = manifest.resources || [];
    for (let i = 0; i < resources.length; i++) {
        const r = resources[i];
        const name = typeof r === "string" ? r : r.name;
        if (name !== resource)
            continue;
        const types = (typeof r === "object" && r.types) || manifest.types || [];
        if (type && types.indexOf(type) === -1)
            continue;
        const prefixes = typeof r === "object" && r.idPrefixes ? r.idPrefixes : manifest.idPrefixes;
        if (id && prefixes && prefixes.length && !prefixes.some(p => id.indexOf(p) === 0))
            continue;
        return true;
    }
    return false;
}

function extraOf(catalog) {
    return catalog.extra || [];
}

function requiresExtra(catalog) {
    if ((catalog.extraRequired || []).length)
        return true;
    return extraOf(catalog).some(e => e.isRequired);
}

function supportsExtra(catalog, name) {
    return extraOf(catalog).some(e => e.name === name) || (catalog.extraSupported || []).indexOf(name) !== -1;
}

// addons : [{ transportUrl, manifest }]. Catalogues affichables sur l'accueil (sans extra obligatoire).
function homeCatalogs(addons) {
    const rows = [];
    addons.forEach(addon => {
        (addon.manifest.catalogs || []).forEach(catalog => {
            if (!requiresExtra(catalog))
                rows.push(catalogRef(addon, catalog));
        });
    });
    return rows;
}

// Catalogues qui acceptent une recherche.
function searchCatalogs(addons) {
    const rows = [];
    addons.forEach(addon => {
        (addon.manifest.catalogs || []).forEach(catalog => {
            if (supportsExtra(catalog, "search"))
                rows.push(catalogRef(addon, catalog));
        });
    });
    return rows;
}

function catalogRef(addon, catalog) {
    return {
        transportUrl: addon.transportUrl,
        addonName: addon.manifest.name,
        type: catalog.type,
        id: catalog.id,
        name: catalog.name || catalog.id
    };
}

// Client lie a un transport.
function createClient(fetchJson) {
    function manifest(transportUrl) {
        return fetchJson(transportUrl).then(m => ({ transportUrl: transportUrl, manifest: m }));
    }

    // Charge plusieurs addons ; ceux qui echouent sont ignores mais signales.
    function loadAddons(transportUrls) {
        const errors = [];
        return Promise.all(transportUrls.map(url => manifest(url).catch(err => {
            errors.push({ transportUrl: url, error: String(err) });
            return null;
        }))).then(list => ({ addons: list.filter(a => a), errors: errors }));
    }

    function catalog(ref, extra) {
        return fetchJson(resourceUrl(ref.transportUrl, "catalog", ref.type, ref.id, extra))
            .then(r => r.metas || []);
    }

    // Meta depuis le premier addon qui la fournit pour ce type et cet identifiant.
    function meta(addons, type, id) {
        const candidates = addons.filter(a => supports(a.manifest, "meta", type, id));
        const tryNext = i => {
            if (i >= candidates.length)
                return Promise.reject(new Error("Aucun addon ne fournit la fiche " + type + "/" + id));
            return fetchJson(resourceUrl(candidates[i].transportUrl, "meta", type, id))
                .then(r => r.meta ? r.meta : tryNext(i + 1), () => tryNext(i + 1));
        };
        return tryNext(0);
    }

    // Agrege une ressource liste (stream, subtitles) depuis tous les addons concernes.
    function collect(addons, resource, key, type, id, extra) {
        const candidates = addons.filter(a => supports(a.manifest, resource, type, id));
        return Promise.all(candidates.map(a =>
            fetchJson(resourceUrl(a.transportUrl, resource, type, id, extra))
                .then(r => ({ addon: a.manifest.name, transportUrl: a.transportUrl, items: r[key] || [] }),
                      err => ({ addon: a.manifest.name, transportUrl: a.transportUrl, items: [], error: String(err) }))
        ));
    }

    function streams(addons, type, id) {
        return collect(addons, "stream", "streams", type, id);
    }

    function subtitles(addons, type, id, extra) {
        return collect(addons, "subtitles", "subtitles", type, id, extra);
    }

    return {
        manifest: manifest,
        loadAddons: loadAddons,
        catalog: catalog,
        meta: meta,
        streams: streams,
        subtitles: subtitles
    };
}

// Episodes d'une serie regroupes par saison, saisons triees (saison 0 = bonus, en dernier).
function seasons(meta) {
    const bySeason = {};
    (meta.videos || []).forEach(v => {
        const s = typeof v.season === "number" ? v.season : 0;
        (bySeason[s] = bySeason[s] || []).push(v);
    });
    return Object.keys(bySeason).map(Number)
        .sort((a, b) => (a === 0) - (b === 0) || a - b)
        .map(s => ({
            season: s,
            episodes: bySeason[s].sort((a, b) => (a.episode || a.number || 0) - (b.episode || b.number || 0))
        }));
}

// Affiche lisible par le Player : pas de WebP.
// images.metahub.space renvoie souvent du WebP, live.metahub.space du JPEG ; pour les autres
// sources, le service compagnon convertit (companion : URL du service, facultatif).
function posterUrl(url) {
    if (!url)
        return "";
    return url.replace(/^https?:\/\/images\.metahub\.space\//, "https://live.metahub.space/");
}

// Repli si l'affiche n'a pas pu etre decodee.
function posterFallback(url, companion) {
    return companion && url ? companion + "/image?url=" + encodeURIComponent(url) : "";
}
