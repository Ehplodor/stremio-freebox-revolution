// Tests des catalogues du jour : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const dc = load("app/js/core/daycache.js");
const plain = x => JSON.parse(JSON.stringify(x));
const CAT = "https://v3-cinemeta.strem.io/catalog/movie/top.json";

test("jour, cles et adresses gardees", () => {
    assert.equal(dc.dayOf(new Date(2026, 9, 5, 23, 59)), "2026-10-05");
    assert.equal(dc.key("https://api.themoviedb.org/3/discover/movie?api_key=abc&language=fr-FR&page=1"),
                 "https://api.themoviedb.org/3/discover/movie?language=fr-FR&page=1");
    assert.equal(dc.key("https://x/3/discover/movie?language=fr-FR&api_key=abc"), "https://x/3/discover/movie?language=fr-FR");
    assert.ok(dc.cacheable(CAT));
    assert.ok(dc.cacheable("https://x/catalog/movie/top/genre=Drama&skip=100.json"));
    assert.ok(!dc.cacheable("https://x/catalog/movie/top/search=dark.json"));
    assert.ok(!dc.cacheable("https://x/meta/movie/tt1.json"));
    assert.ok(dc.cacheable("https://api.themoviedb.org/3/discover/tv?api_key=k&page=2"));
    assert.ok(!dc.cacheable("https://api.themoviedb.org/3/genre/movie/list?api_key=k"));
});

test("reponses reduites, enregistrees et relues le meme jour seulement", () => {
    const c = dc.create("2026-10-26");
    dc.put(c, CAT, { metas: [{ id: "tt1", type: "movie", name: "A", poster: "p", description: "x".repeat(500),
                               genres: ["a", "b", "c", "d", "e"], cast: ["long"], videos: [], imdbRating: "7.1" }] });
    const m = dc.get(c, CAT).metas[0];
    assert.equal(m.description.length, 240);
    assert.deepEqual(plain(m.genres), ["a", "b", "c", "d"]);
    assert.ok(!("cast" in m) && !("videos" in m));
    dc.put(c, "https://api.themoviedb.org/3/discover/movie?api_key=k&page=1",
           { page: 1, total_pages: 9, results: [{ id: 5, title: "T", poster_path: "/p.jpg", popularity: 3, overview: "o" }] });
    assert.deepEqual(plain(dc.get(c, "https://api.themoviedb.org/3/discover/movie?api_key=autre&page=1")),
                     { page: 1, total_pages: 9, results: [{ id: 5, title: "T", poster_path: "/p.jpg", overview: "o" }] });
    c.preloaded = true;
    const text = dc.serialize(c);
    assert.ok(text.indexOf("api_key") === -1);
    const again = dc.parse(text, "2026-10-26");
    assert.equal(dc.count(again), 2);
    assert.ok(again.preloaded);
    assert.equal(dc.get(again, CAT).metas[0].name, "A");
    assert.equal(dc.count(dc.parse(text, "2026-10-27")), 0, "le lendemain : tout est recharge");
    assert.equal(dc.count(dc.parse("pas du json", "2026-10-26")), 0);
});

test("taille limitee : les premieres entrees (prechargees) sont gardees", () => {
    const c = dc.create("d");
    for (let i = 0; i < 10; i++)
        dc.put(c, "https://x/catalog/movie/c" + i + ".json", { metas: [{ id: "tt" + i, name: "n".repeat(100) }] });
    const text = dc.serialize(c, 800);
    assert.ok(text.length <= 800);
    const kept = dc.parse(text, "d");
    assert.ok(dc.count(kept) >= 3 && dc.count(kept) < 10);
    assert.equal(kept.order[0], "https://x/catalog/movie/c0.json");
});

test("taches par lots, progression jusqu'au bout meme en cas d'echec", async () => {
    const seen = [];
    let running = 0, peak = 0;
    const tasks = [0, 1, 2, 3, 4, 5, 6].map(i => () => {
        running++;
        peak = Math.max(peak, running);
        return new Promise((res, rej) => setTimeout(() => { running--; (i === 3 ? rej : res)(i); }, 5));
    });
    await dc.runAll(tasks, 3, (done, total) => seen.push(done + "/" + total));
    assert.equal(seen[seen.length - 1], "7/7");
    assert.equal(peak, 3);
    await dc.runAll([], 3, () => assert.fail());
});
