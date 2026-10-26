.pragma library
// Ecran « Decouvrir » : catalogues des addons filtres par type, genre (ou annee), et filtres
// appliques sur les titres recus (decennie, note). Comme stremio-core (models/catalog_with_filters),
// les filtres que l'addon connait (extra « genre ») sont demandes a l'addon ; les autres sont
// appliques ici sur les pages chargees.

const TYPE_LABELS = { movie: "Films", series: "Séries", anime: "Anime", channel: "Chaînes", tv: "TV" };

// Extras qu'un catalogue peut exiger tout en restant utilisable ici.
const USABLE_REQUIRED = ["genre"];

function extras(catalog) {
    const list = (catalog.extra || []).slice();
    (catalog.extraSupported || []).forEach(name => {
        if (!list.some(e => e.name === name))
            list.push({ name: name, isRequired: (catalog.extraRequired || []).indexOf(name) !== -1 });
    });
    return list;
}

function usable(catalog) {
    return extras(catalog).every(e => !e.isRequired || USABLE_REQUIRED.indexOf(e.name) !== -1);
}

// Catalogues filtrables : [{ transportUrl, addonName, type, id, name, genres, genreRequired, skip }]
function catalogs(addons) {
    const out = [];
    (addons || []).forEach(addon => {
        (addon.manifest.catalogs || []).forEach(c => {
            if (!usable(c))
                return;
            const ex = extras(c);
            const genre = ex.find(e => e.name === "genre");
            out.push({
                transportUrl: addon.transportUrl,
                addonName: addon.manifest.name,
                type: c.type,
                id: c.id,
                name: c.name || c.id,
                genres: genre && Array.isArray(genre.options) ? genre.options.slice() : [],
                genreRequired: !!(genre && genre.isRequired),
                skip: ex.some(e => e.name === "skip")
            });
        });
    });
    return out;
}

// Types proposes (films et series d'abord).
function types(list) {
    const order = ["movie", "series"];
    const found = [];
    list.forEach(c => { if (found.indexOf(c.type) === -1) found.push(c.type); });
    return found.sort((a, b) => {
        const ia = order.indexOf(a), ib = order.indexOf(b);
        return (ia === -1 ? 99 : ia) - (ib === -1 ? 99 : ib);
    });
}

function typeLabel(type) {
    return TYPE_LABELS[type] || type;
}

// Filtres appliques ici.
const DECADES = [
    { id: "", label: "Toutes", from: 0, to: 9999 },
    { id: "2020", label: "Années 2020", from: 2020, to: 2029 },
    { id: "2010", label: "Années 2010", from: 2010, to: 2019 },
    { id: "2000", label: "Années 2000", from: 2000, to: 2009 },
    { id: "1990", label: "Années 1990", from: 1990, to: 1999 },
    { id: "1980", label: "Années 1980", from: 1980, to: 1989 },
    { id: "old", label: "Avant 1980", from: 0, to: 1979 }
];
const RATINGS = [
    { id: 0, label: "Toutes" },
    { id: 6, label: "6+ (IMDb)" },
    { id: 7, label: "7+ (IMDb)" },
    { id: 8, label: "8+ (IMDb)" }
];

function yearOf(meta) {
    const m = /(\d{4})/.exec(String(meta.year || meta.releaseInfo || meta.released || ""));
    return m ? parseInt(m[1], 10) : 0;
}

// filters : { decade, minRating } ; un titre sans annee ou sans note est ecarte seulement si ce
// filtre est actif.
function apply(metas, filters) {
    const d = DECADES.find(x => x.id === (filters.decade || "")) || DECADES[0];
    const min = filters.minRating || 0;
    return (metas || []).filter(m => {
        if (d.id) {
            const y = yearOf(m);
            if (!y || y < d.from || y > d.to)
                return false;
        }
        if (min) {
            const r = parseFloat(m.imdbRating);
            if (!(r >= min))
                return false;
        }
        return true;
    });
}

// Age maximum : ni Cinemeta ni les catalogues des addons courants ne donnent la classification.
// L'addon TMDB (instance publique d'ElfHosted, sans cle) sait filtrer ses catalogues cote serveur
// (option « ageRating » de sa configuration, classification americaine G / PG / PG-13 / R ; pour
// les series TV-G / TV-PG / TV-14 / TV-MA). Avec un age choisi, Decouvrir passe sur ses catalogues
// « Populaire » et « Annee » en francais.
const TMDB_BASE = "https://tmdb.elfhosted.com/";
const TMDB_LANGUAGE = "fr-FR";
const AGE_CATALOGS = ["tmdb.top", "tmdb.year"];
const AGES = [
    { id: "", label: "Sans limite" },
    { id: "G", label: "Tous publics" },
    { id: "PG", label: "10 ans" },
    { id: "PG-13", label: "12 ans" },
    { id: "R", label: "16 ans" }
];

function tmdbUrl(age) {
    const config = { language: TMDB_LANGUAGE };
    if (age)
        config.ageRating = age;
    return TMDB_BASE + encodeURIComponent(JSON.stringify(config)) + "/manifest.json";
}
const TMDB_URL = tmdbUrl("");

// Catalogues filtrables par age, depuis l'addon TMDB charge par tmdbUrl("").
function ageCatalogs(tmdbAddon) {
    if (!tmdbAddon)
        return [];
    return catalogs([tmdbAddon]).filter(c => AGE_CATALOGS.indexOf(c.id) !== -1)
        .map(c => Object.assign(c, { addonName: "TMDB" }));
}

// Le meme catalogue, filtre par l'addon sur l'age.
function withAge(catalog, age) {
    if (!age || catalog.transportUrl !== TMDB_URL)
        return catalog;
    return Object.assign({}, catalog, { transportUrl: tmdbUrl(age) });
}

function isTmdbId(id) {
    return /^tmdb:/.test(String(id));
}

// Extra a demander a l'addon pour un catalogue et un genre ("" = tous).
function request(catalog, genre, skip) {
    const extra = {};
    const g = genre || (catalog.genreRequired ? catalog.genres[0] : "");
    if (g)
        extra.genre = g;
    if (skip)
        extra.skip = skip;
    return extra;
}

// Valeur suivante / precedente d'une liste (filtres a la telecommande : Gauche / Droite).
function cycle(list, value, step) {
    const i = list.indexOf(value);
    return list[((i === -1 ? 0 : i) + step + list.length) % list.length];
}
