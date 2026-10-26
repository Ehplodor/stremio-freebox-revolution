// Tests de l'ecran Decouvrir : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const discover = load("app/js/core/discover.js");
const plain = x => JSON.parse(JSON.stringify(x));
const CINEMETA = { transportUrl: "https://v3-cinemeta.strem.io/manifest.json", manifest: load.fixture("cinemeta-manifest.json") };

test("catalogues filtrables de Cinemeta : genre, annee obligatoire, pagination", () => {
    const list = discover.catalogs([CINEMETA]);
    assert.deepEqual(plain(discover.types(list)), ["movie", "series"]);
    const top = list.find(c => c.type === "movie" && c.id === "top");
    assert.ok(top.genres.indexOf("Action") !== -1);
    assert.equal(top.genreRequired, false);
    assert.ok(top.skip);
    assert.ok(!list.some(c => c.id === "last-videos" || c.id === "calendar-videos"), "extras obligatoires inconnus");
    const year = list.find(c => c.type === "movie" && c.id === "year");
    if (year) {
        assert.equal(year.genreRequired, true);
        assert.deepEqual(plain(discover.request(year, "", 0)), { genre: year.genres[0] });
    }
    assert.deepEqual(plain(discover.request(top, "", 0)), {});
    assert.deepEqual(plain(discover.request(top, "Drama", 100)), { genre: "Drama", skip: 100 });
});

test("filtres locaux : decennie et note", () => {
    const metas = [
        { id: "a", releaseInfo: "2021", imdbRating: "7.5" },
        { id: "b", releaseInfo: "2015–2019", imdbRating: "8.2" },
        { id: "c", year: 1994, imdbRating: "9.0" },
        { id: "d", releaseInfo: "", imdbRating: "" }
    ];
    assert.equal(discover.apply(metas, {}).length, 4);
    assert.deepEqual(plain(discover.apply(metas, { decade: "2010" }).map(m => m.id)), ["b"]);
    assert.deepEqual(plain(discover.apply(metas, { minRating: 8 }).map(m => m.id)), ["b", "c"]);
    assert.deepEqual(plain(discover.apply(metas, { decade: "1990", minRating: 7 }).map(m => m.id)), ["c"]);
    assert.equal(discover.cycle(["x", "y", "z"], "z", 1), "x");
});

test("age maximum : catalogues TMDB filtres par l'addon", () => {
    const tmdb = { transportUrl: discover.tmdbUrl(""), manifest: load.fixture("tmdb-fr-manifest.json") };
    assert.equal(discover.tmdbUrl(""), "https://tmdb.elfhosted.com/%7B%22language%22%3A%22fr-FR%22%7D/manifest.json");
    const list = discover.ageCatalogs(tmdb);
    assert.deepEqual(plain(list.map(c => c.type + "/" + c.id)), ["movie/tmdb.top", "series/tmdb.top", "movie/tmdb.year", "series/tmdb.year"]);
    assert.equal(list[0].addonName, "TMDB");
    assert.ok(list[0].skip);
    assert.equal(discover.ageCatalogs(null).length, 0);
    const pg = discover.withAge(list[0], "PG");
    assert.equal(pg.transportUrl, "https://tmdb.elfhosted.com/%7B%22language%22%3A%22fr-FR%22%2C%22ageRating%22%3A%22PG%22%7D/manifest.json");
    assert.equal(pg.id, "tmdb.top");
    assert.equal(discover.withAge(list[0], ""), list[0]);
    const other = { transportUrl: CINEMETA.transportUrl, id: "top" };
    assert.equal(discover.withAge(other, "PG"), other, "seul l'addon TMDB connait le filtre");
    assert.ok(discover.isTmdbId("tmdb:862"));
    assert.ok(!discover.isTmdbId("tt0114709"));
});

test("tous les catalogues : fusion tour a tour et doublons", () => {
    const cats = [
        { transportUrl: "a", id: "top", type: "movie", genres: ["Drama", "Action"], genreRequired: false },
        { transportUrl: "b", id: "netflix", type: "movie", genres: ["Comedy"], genreRequired: false },
        { transportUrl: "a", id: "year", type: "movie", genres: ["2024"], genreRequired: true },
        { transportUrl: "a", id: "top", type: "series", genres: [], genreRequired: false }
    ];
    const all = discover.allCatalog(cats, "movie");
    assert.equal(all.kind, "all");
    assert.deepEqual(plain(all.parts.map(c => c.id)), ["top", "netflix"]);
    assert.deepEqual(plain(all.genres), ["Action", "Comedy", "Drama"]);
    assert.deepEqual(plain(discover.allParts(all, "Comedy").map(c => c.id)), ["netflix"]);
    const known = {};
    const first = discover.mergeNew([
        [{ id: "tt1", name: "A" }, { id: "tt2", name: "B" }],
        [{ id: "tt2", name: "B" }, { id: "x:9", name: "Le Film", releaseInfo: "2001" }, { id: "y:3", name: "le film !", year: 2001 }]
    ], known);
    assert.deepEqual(plain(first.map(m => m.id)), ["tt1", "tt2", "x:9"]);
    assert.equal(discover.mergeNew([[{ id: "tmdb:5", imdb_id: "tt1", name: "A" }]], known).length, 0);
    assert.equal(discover.mergeNew([[{ id: "tmdb:7", name: "Le Film", year: 2001 }]], known, true).length, 1, "un seul catalogue : par identifiant");
});

test("catalogue TMDB complet : filtres envoyes a TMDB", () => {
    const cat = discover.apiCatalog("movie", [{ id: 28, name: "Action" }, { id: 16, name: "Animation" }]);
    assert.deepEqual(plain(cat.genres), ["Action", "Animation"]);
    assert.deepEqual(plain(discover.apiOptions(cat, { genre: "Animation", decade: "2010", minRating: 7, maxAge: "PG", provider: 8 }, 3)),
                     { genreId: 16, from: 2010, to: 2019, minRating: 7, maxAge: "PG", ageCountry: "", providerId: 8, page: 3 });
    assert.deepEqual(plain(discover.apiOptions(cat, {}, 1)),
                     { genreId: "", from: 0, to: 9999, minRating: 0, maxAge: "", ageCountry: "", providerId: "", page: 1 });
});
