.pragma library
// Recherche avancee TMDB (api.themoviedb.org/3/discover) avec la cle API de l'utilisateur.
// La cle n'est jamais saisie dans l'appli : elle est lue dans la configuration de l'addon TMDB
// (tmdb-addon, https://github.com/mrcanelas/tmdb-addon) installe sur le compte Stremio. Cette
// configuration est le segment d'adresse avant /manifest.json : JSON, ou JSON compresse par
// lz-string (page /configure de l'addon).

const API = "https://api.themoviedb.org/3";
const IMAGES = "https://image.tmdb.org/t/p/";
const LANGUAGE = "fr-FR";
const REGION = "FR";
const PAGE_SIZE = 20;

// Configuration d'un addon TMDB depuis son adresse ; decompress : lz-string (lzstring.js).
function addonConfig(transportUrl, decompress) {
    const m = /\/([^\/]+)\/manifest\.json$/.exec(String(transportUrl));
    if (!m)
        return null;
    const parse = text => {
        try {
            const c = JSON.parse(text);
            return c && typeof c === "object" ? c : null;
        } catch (e) {
            return null;
        }
    };
    let config = null;
    try {
        config = parse(decodeURIComponent(m[1]));
    } catch (e) {
        config = null;
    }
    return config || (decompress ? parse(decompress(m[1]) || "") : null);
}

// Premiere cle API trouvee dans les addons TMDB du compte ; "" sinon.
function apiKey(addons, decompress) {
    const list = addons || [];
    for (let i = 0; i < list.length; i++) {
        const a = list[i];
        if (!a.manifest || a.manifest.id !== "tmdb-addon")
            continue;
        const config = addonConfig(a.transportUrl, decompress);
        if (config && typeof config.tmdbApiKey === "string" && /^\w{16,}$/.test(config.tmdbApiKey.trim()))
            return config.tmdbApiKey.trim();
    }
    return "";
}

function query(params) {
    return Object.keys(params).filter(k => params[k] !== undefined && params[k] !== "")
        .map(k => k + "=" + encodeURIComponent(params[k])).join("&");
}

function kind(type) {
    return type === "series" ? "tv" : "movie";
}

function genresUrl(key, type) {
    return API + "/genre/" + kind(type) + "/list?" + query({ api_key: key, language: LANGUAGE });
}

function providersUrl(key, type) {
    return API + "/watch/providers/" + kind(type) + "?" + query({ api_key: key, language: LANGUAGE, watch_region: REGION });
}

// Identifiants externes (IMDb) d'un titre ; id : "tmdb:862" ou 862.
function externalIdsUrl(key, type, id) {
    return API + "/" + kind(type) + "/" + String(id).replace(/^tmdb:/, "") + "/external_ids?" + query({ api_key: key });
}

// Services de streaming disponibles en France, les plus courants d'abord : [{ id, name }]
function providers(response, max) {
    return ((response && response.results) || [])
        .slice().sort((a, b) => (a.display_priority || 99) - (b.display_priority || 99))
        .slice(0, max || 20)
        .map(p => ({ id: p.provider_id, name: p.provider_name }));
}

// Age maximum (memes choix que discover.js, codes americains) -> classifications acceptees.
// Films : classification francaise ; series : TMDB ne connait que les codes americains TV-*.
const MOVIE_AGES = { "G": ["U"], "PG": ["U", "10"], "PG-13": ["U", "10", "12"], "R": ["U", "10", "12", "16"] };
const TV_AGES = { "G": ["TV-Y", "TV-Y7", "TV-G"], "PG": ["TV-Y", "TV-Y7", "TV-G", "TV-PG"],
                  "PG-13": ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14"],
                  "R": ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14", "TV-MA"] };

// opts : { genreId, from, to (annees), minRating, maxAge, providerId, page (1..) }
function discoverUrl(key, type, opts) {
    const tv = type === "series";
    const o = opts || {};
    const ages = (tv ? TV_AGES : MOVIE_AGES)[o.maxAge || ""];
    const params = {
        api_key: key,
        language: LANGUAGE,
        sort_by: "popularity.desc",
        include_adult: "false",
        page: o.page || 1,
        with_genres: o.genreId || "",
        "vote_average.gte": o.minRating || "",
        // une note sur trois votes ne veut rien dire
        "vote_count.gte": o.minRating ? 150 : "",
        certification_country: ages ? (tv ? "US" : REGION) : "",
        certification: ages ? ages.join("|") : "",
        with_watch_providers: o.providerId || "",
        watch_region: o.providerId ? REGION : ""
    };
    const datePrefix = tv ? "first_air_date" : "primary_release_date";
    if (o.from)
        params[datePrefix + ".gte"] = o.from + "-01-01";
    if (o.to && o.to < 9999)
        params[datePrefix + ".lte"] = o.to + "-12-31";
    return API + "/discover/" + kind(type) + "?" + query(params);
}

// Resultat TMDB -> meta Stremio (identifiant tmdb:, comme l'addon TMDB).
function toMeta(r, type) {
    const date = r.release_date || r.first_air_date || "";
    return {
        id: "tmdb:" + r.id,
        type: type,
        name: r.title || r.name || "",
        poster: r.poster_path ? IMAGES + "w342" + r.poster_path : "",
        background: r.backdrop_path ? IMAGES + "w1280" + r.backdrop_path : "",
        description: r.overview || "",
        releaseInfo: date.slice(0, 4),
        tmdbRating: r.vote_average ? (Math.round(r.vote_average * 10) / 10).toFixed(1) : ""
    };
}

function metas(response, type) {
    return ((response && response.results) || []).map(r => toMeta(r, type));
}

// Derniere page atteinte ?
function lastPage(response) {
    return !response || !response.results || !response.results.length || (response.page || 1) >= (response.total_pages || 1);
}
