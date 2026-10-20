// Tests de la progression ecrite dans la bibliotheque Stremio : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const library = load("app/js/core/library.js");
const account = load("app/js/core/account.js");
const T0 = Date.parse("2026-10-20T20:00:00Z");
const MOVIE = { id: "tt15239678", type: "movie", name: "Dune : Deuxième partie", poster: "https://x/p.jpg" };

test("film ouvert sans etre ajoute : temporaire, puis dans « Continuer a regarder »", () => {
    const fresh = library.fromMeta(MOVIE, T0);
    assert.equal(fresh._id, "tt15239678");
    assert.equal(fresh.removed, true);
    assert.equal(fresh.temp, true);
    assert.equal(fresh.posterShape, "poster");
    assert.equal(fresh.state.video_id, null);
    assert.equal(account.continueWatching([fresh]).length, 0, "pas encore regarde");

    const item = library.updateProgress(fresh, "tt15239678", 600000, 9960000, 15000, T0 + 60000);
    assert.equal(item.state.timeOffset, 600000);
    assert.equal(item.state.duration, 9960000);
    assert.equal(item.state.timeWatched, 15000);
    assert.equal(item.state.overallTimeWatched, 15000);
    assert.equal(item.state.video_id, "tt15239678");
    assert.equal(item._mtime, "2026-10-20T20:01:00.000Z");
    assert.equal(item.state.lastWatched, "2026-10-20T20:01:00.000Z");
    assert.equal(fresh.state.timeOffset, 0, "l'element d'origine n'est pas modifie");
    assert.deepEqual(account.continueWatching([item]).map(i => i._id), ["tt15239678"]);
});

test("serie : autre episode, temps regarde remis a zero ; vu a 70 % ; fin hors de la reprise", () => {
    let item = library.fromMeta({ id: "tt0903747", type: "series", name: "Breaking Bad" }, T0);
    item = library.updateProgress(item, "tt0903747:1:1", 2000000, 2900000, 2100000, T0 + 1);
    assert.equal(item.state.flaggedWatched, 1);
    assert.equal(item.state.timesWatched, 1);
    item = library.updateProgress(item, "tt0903747:1:1", 2800000, 2900000, 700000, T0 + 2);
    assert.equal(item.state.timeOffset, 0, "fin : plus rien a reprendre");
    assert.equal(item.state.timesWatched, 1, "compte une seule fois");
    item = library.updateProgress(item, "tt0903747:1:2", 60000, 2800000, 60000, T0 + 3);
    assert.equal(item.state.video_id, "tt0903747:1:2");
    assert.equal(item.state.timeWatched, 60000);
    assert.equal(item.state.flaggedWatched, 0);
    assert.equal(item.state.overallTimeWatched, 2860000);
    assert.equal(account.toMeta(item).videoId, "tt0903747:1:2");
});

test("element retire par l'utilisateur puis regarde : temporaire ; champs inconnus conserves", () => {
    const removed = Object.assign(library.fromMeta(MOVIE, T0), { temp: false, extra: 1 });
    removed.state.watched = "abc:1:xyz";
    const item = library.updateProgress(removed, MOVIE.id, 120000, 9960000, 10000, T0 + 5);
    assert.equal(item.temp, true);
    assert.equal(item.extra, 1);
    assert.equal(item.state.watched, "abc:1:xyz");
});

test("liste : remplacement en tete, copie locale limitee", () => {
    const a = library.fromMeta(MOVIE, T0);
    const b = library.fromMeta({ id: "tt1", type: "movie", name: "B" }, T0 + 1);
    let list = library.upsert([a, b], library.updateProgress(a, MOVIE.id, 50000, 100000, 1000, T0 + 9));
    assert.deepEqual(list.map(i => i._id), ["tt15239678", "tt1"]);
    const many = [];
    for (let i = 0; i < 80; i++)
        many.push(library.fromMeta({ id: "tt" + i, type: "movie", name: "" }, T0 + i));
    const kept = library.trimLocal(many);
    assert.equal(kept.length, 60);
    assert.equal(kept[0]._id, "tt79");
});

test("datastorePut : forme de la requete", async () => {
    let sent = null;
    const acc = account.createAccount({ postJson: (url, body) => { sent = { url, body }; return Promise.resolve({ result: { success: true } }); } });
    await acc.libraryPut("KEY", [library.fromMeta(MOVIE, T0)]);
    assert.equal(sent.url, "https://api.strem.io/api/datastorePut");
    assert.equal(sent.body.collection, "libraryItem");
    assert.equal(sent.body.authKey, "KEY");
    assert.equal(sent.body.changes[0]._id, "tt15239678");
});
