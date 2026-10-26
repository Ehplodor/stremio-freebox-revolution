// Tests de la recherche avancee TMDB et de la lecture de la cle : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const tmdb = load("app/js/core/tmdb.js");
const lz = load("app/js/core/lzstring.js");
const plain = x => JSON.parse(JSON.stringify(x));
const KEY = "0123456789abcdef0123456789abcdef";
const unlz = lz.decompressFromEncodedURIComponent;

test("cle API lue dans l'addon TMDB du compte (JSON ou lz-string)", () => {
    // compressToEncodedURIComponent de lz-string 1.5.0
    assert.equal(unlz("N4IgNghgdg5grhGBTEAuEAzATgWgGIBKIAvkA"), JSON.stringify({ language: "fr-FR" }));
    assert.equal(unlz("%7B"), null);
    const json = encodeURIComponent(JSON.stringify({ language: "fr-FR", tmdbApiKey: KEY }));
    const compressed = "N4IgNghgdg5grhGBTEAuEAzATgWgGIBKIANCAC4C2AJgEYCCADgJYDSSAnmiAAwCMATAGYALAFYAbAHYAHAE4INAMZUkGPkLFS5C5apABfIA";
    const addon = url => ({ transportUrl: url, manifest: { id: "tmdb-addon" } });
    assert.equal(tmdb.apiKey([addon("https://tmdb.elfhosted.com/" + json + "/manifest.json")], unlz), KEY);
    assert.equal(tmdb.apiKey([addon("https://tmdb.elfhosted.com/" + compressed + "/manifest.json")], unlz), KEY);
    assert.equal(tmdb.apiKey([addon("https://tmdb.elfhosted.com/N4IgNghgdg5grhGBTEAuEAzATgWgGIBKIAvkA/manifest.json")], unlz), "");
    assert.equal(tmdb.apiKey([addon("https://tmdb.elfhosted.com/manifest.json")], unlz), "");
    assert.equal(tmdb.apiKey([{ transportUrl: "https://x/" + json + "/manifest.json", manifest: { id: "autre" } }], unlz), "");
    assert.equal(tmdb.apiKey(null), "");
});

test("adresse de recherche avancee : genre, annees, note, age, service", () => {
    const url = tmdb.discoverUrl(KEY, "movie", { genreId: 16, from: 2010, to: 2019, minRating: 7, maxAge: "PG", providerId: 8, page: 2 });
    const q = new URL(url);
    assert.equal(q.pathname, "/3/discover/movie");
    const p = Object.fromEntries(q.searchParams);
    assert.equal(p.with_genres, "16");
    assert.equal(p["primary_release_date.gte"], "2010-01-01");
    assert.equal(p["primary_release_date.lte"], "2019-12-31");
    assert.equal(p["vote_average.gte"], "7");
    assert.equal(p.certification_country, "FR");
    assert.equal(p.certification, "U|10");
    assert.equal(p.with_watch_providers, "8");
    assert.equal(p.watch_region, "FR");
    assert.equal(p.page, "2");
    const tv = Object.fromEntries(new URL(tmdb.discoverUrl(KEY, "series", { from: 0, to: 9999, maxAge: "G" })).searchParams);
    assert.equal(tv.certification_country, "US");
    assert.ok(!("first_air_date.gte" in tv) && !("first_air_date.lte" in tv) && !("with_genres" in tv));
});

test("resultats TMDB -> metas", () => {
    const r = { page: 1, total_pages: 1, results: [{ id: 862, title: "Toy Story", poster_path: "/a.jpg", release_date: "1995-11-22", vote_average: 7.97 }] };
    assert.deepEqual(plain(tmdb.metas(r, "movie")[0]), {
        id: "tmdb:862", type: "movie", name: "Toy Story", poster: "https://image.tmdb.org/t/p/w342/a.jpg",
        background: "", description: "", releaseInfo: "1995", tmdbRating: "8.0"
    });
    assert.ok(tmdb.lastPage(r));
    assert.deepEqual(plain(tmdb.providers({ results: [{ provider_id: 8, provider_name: "Netflix", display_priority: 2 }, { provider_id: 337, provider_name: "Disney Plus", display_priority: 1 }] })),
                     [{ id: 337, name: "Disney Plus" }, { id: 8, name: "Netflix" }]);
});
