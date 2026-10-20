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
