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

// Age maximum (memes choix que discover.js, codes americains) -> filtre de classification.
// Films : classification francaise de TMDB (TP, 10, 12, 16, 18 : « certification.lte » suit cet
// ordre) ; « Tous publics » s'ecrit TP (et non U). Series : TMDB ne filtre que sur les codes
// americains TV-*, comme l'addon TMDB (liste « a|b »). ageCountry "US" : films en codes
// americains aussi (repli quand la classification francaise ne donne rien).
const MOVIE_AGES_FR = { "G": "TP", "PG": "10", "PG-13": "12", "R": "16" };
const MOVIE_AGES_US = { "G": ["G"], "PG": ["G", "PG"], "PG-13": ["G", "PG", "PG-13"], "R": ["G", "PG", "PG-13", "R"] };
const TV_AGES = { "G": ["TV-Y", "TV-Y7", "TV-G"], "PG": ["TV-Y", "TV-Y7", "TV-G", "TV-PG"],
                  "PG-13": ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14"],
                  "R": ["TV-Y", "TV-Y7", "TV-G", "TV-PG", "TV-14", "TV-MA"] };

function ageParams(type, maxAge, ageCountry) {
    if (!maxAge || !MOVIE_AGES_FR[maxAge])
        return {};
    if (type === "series")
        return { certification_country: "US", certification: TV_AGES[maxAge].join("|") };
    if (ageCountry === "US")
        return { certification_country: "US", certification: MOVIE_AGES_US[maxAge].join("|") };
    return { certification_country: REGION, "certification.lte": MOVIE_AGES_FR[maxAge] };
}

// opts : { genreId, from, to (annees), minRating, maxAge, ageCountry, providerId, page (1..) }
function discoverUrl(key, type, opts) {
    const tv = type === "series";
    const o = opts || {};
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
        with_watch_providers: o.providerId || "",
        watch_region: o.providerId ? REGION : ""
    };
    Object.assign(params, ageParams(type, o.maxAge, o.ageCountry));
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

// ----- Personnes (filmographie) et collections -----

function findUrl(key, imdbId) {
    return API + "/find/" + encodeURIComponent(imdbId) + "?" + query({ api_key: key, external_source: "imdb_id", language: LANGUAGE });
}

function movieUrl(key, tmdbId) {
    return API + "/movie/" + tmdbId + "?" + query({ api_key: key, language: LANGUAGE });
}

function collectionUrl(key, collectionId) {
    return API + "/collection/" + collectionId + "?" + query({ api_key: key, language: LANGUAGE });
}

function searchUrl(key, what, text) {
    return API + "/search/" + what + "?" + query({ api_key: key, language: LANGUAGE, query: text, include_adult: "false" });
}

function creditsUrl(key, personId) {
    return API + "/person/" + personId + "/combined_credits?" + query({ api_key: key, language: LANGUAGE });
}

// Film TMDB d'un identifiant IMDb (reponse de /find) ; null sinon.
function foundMovieId(response) {
    const r = response && response.movie_results && response.movie_results[0];
    return r ? r.id : null;
}

// Collection d'un film (reponse de /movie) : { id, name } ou null.
function collectionOf(response) {
    const c = response && response.belongs_to_collection;
    return c && c.id ? { id: c.id, name: c.name || "" } : null;
}

// Films d'une collection, dans l'ordre de sortie (sans date : a la fin).
function collectionMetas(response) {
    const parts = ((response && response.parts) || []).slice();
    parts.sort((a, b) => (a.release_date || "9999").localeCompare(b.release_date || "9999"));
    return parts.map(r => toMeta(r, "movie"));
}

// Filmographie (reponse de /combined_credits) : films et series, joues ou realises, une fois
// chacun, les plus connus d'abord (nombre de votes). Emissions sans affiche ecartees.
function filmography(response) {
    const all = ((response && response.cast) || []).concat((response && response.crew) || []);
    const seen = {};
    const out = [];
    all.forEach(r => {
        if (r.media_type !== "movie" && r.media_type !== "tv")
            return;
        const k = r.media_type + ":" + r.id;
        if (seen[k] || !r.poster_path)
            return;
        seen[k] = true;
        out.push(r);
    });
    out.sort((a, b) => (b.vote_count || 0) - (a.vote_count || 0));
    return out.map(r => toMeta(r, r.media_type === "tv" ? "series" : "movie"));
}

// Resultats de recherche de personnes et de collections, en tuiles.
function personMetas(response) {
    return ((response && response.results) || []).filter(p => p.profile_path)
        .map(p => ({ id: "tmdbperson:" + p.id, type: "person", name: p.name || "",
                     poster: IMAGES + "w342" + p.profile_path }));
}

function collectionTiles(response) {
    return ((response && response.results) || []).filter(c => c.poster_path)
        .map(c => ({ id: "tmdbcol:" + c.id, type: "collection", name: c.name || "",
                     poster: IMAGES + "w342" + c.poster_path }));
}

// Personne la plus connue d'une recherche par nom ; null sinon.
function bestPerson(response) {
    const list = ((response && response.results) || []).slice();
    list.sort((a, b) => (b.popularity || 0) - (a.popularity || 0));
    return list[0] ? { id: list[0].id, name: list[0].name } : null;
}

// "tmdbperson:287" -> { kind: "person", id: "287" } ; "tmdbcol:10" -> { kind: "collection", ... }
function tileKind(id) {
    const m = /^tmdb(person|col):(\d+)$/.exec(String(id));
    return m ? { kind: m[1] === "col" ? "collection" : "person", id: m[2] } : null;
}
