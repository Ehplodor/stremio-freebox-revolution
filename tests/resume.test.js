// Tests reprise, episode suivant, langues preferees : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const resume = load("app/js/core/resume.js");
const plain = x => JSON.parse(JSON.stringify(x));

test("positions : enregistrement, reprise, vu, par compte", () => {
    let p = resume.record({}, "A", "tt1", 10000, 6000000, 1);
    assert.equal(Object.keys(p).length, 0, "moins de 30 s : rien");
    p = resume.record(p, "A", "tt1", 1200000, 6000000, 2);
    assert.equal(resume.resumeAt(p, "A", "tt1"), 1200000);
    assert.equal(resume.resumeAt(p, "B", "tt1"), 0, "autre compte");
    assert.equal(resume.progress(p, "A", "tt1"), 0.2);
    p = resume.record(p, "A", "tt1", 5700000, 6000000, 3);
    assert.equal(resume.resumeAt(p, "A", "tt1"), 0, "vu jusqu'au generique");
    assert.equal(resume.progress(p, "A", "tt1"), 1);
});

test("positions : taille limitee, les plus anciennes partent", () => {
    let p = {};
    for (let i = 0; i < 310; i++)
        p = resume.record(p, "A", "v" + i, 60000, 600000, i);
    assert.equal(Object.keys(p).length, 300);
    assert.equal(resume.resumeAt(p, "A", "v0"), 0);
    assert.equal(resume.resumeAt(p, "A", "v309"), 60000);
});

test("episode suivant", () => {
    const meta = { videos: [
        { id: "s:2:1", season: 2, episode: 1 }, { id: "s:1:2", season: 1, episode: 2 },
        { id: "s:1:1", season: 1, episode: 1 }, { id: "s:0:1", season: 0, episode: 1 } ] };
    assert.equal(resume.nextEpisode(meta, "s:1:1").id, "s:1:2");
    assert.equal(resume.nextEpisode(meta, "s:1:2").id, "s:2:1", "saison suivante");
    assert.equal(resume.nextEpisode(meta, "s:2:1"), null);
    assert.equal(resume.nextEpisode({}, "x"), null);
});

test("langues preferees", () => {
    const audio = [{ language: "eng" }, { language: "fre" }];
    assert.equal(resume.pickAudio(audio, "fr"), 1);
    assert.equal(resume.pickAudio(audio, "vo"), 0);
    assert.equal(resume.pickAudio(audio, "de"), 0, "absente : premiere piste");
    const subs = [{ kind: "off" }, { kind: "external", language: "fre" }, { kind: "embedded", language: "fre" },
                  { kind: "embedded", language: "eng" }];
    assert.equal(resume.pickSubtitle(subs, "auto", "eng"), 2, "integre prefere");
    assert.equal(resume.pickSubtitle(subs, "auto", "fre"), 0, "audio deja en francais");
    assert.equal(resume.pickSubtitle(subs, "en", "fre"), 3);
    assert.equal(resume.pickSubtitle(subs, "off", "eng"), 0);
});

test("serie : episode a reprendre", () => {
    const meta = { videos: [{ id: "s:1:1", season: 1, episode: 1 }, { id: "s:1:2", season: 1, episode: 2 },
                            { id: "s:1:3", season: 1, episode: 3 }] };
    let p = {};
    assert.equal(resume.seriesResume(meta, p, "A"), null, "jamais vue");
    p = resume.record(p, "A", "s:1:1", 600000, 1200000, 1);
    p = resume.record(p, "A", "s:1:2", 300000, 1200000, 5);
    assert.equal(resume.seriesResume(meta, p, "A").id, "s:1:2", "le plus recent");
    p = resume.record(p, "A", "s:1:2", 1190000, 1200000, 9);
    assert.equal(resume.seriesResume(meta, p, "A").id, "s:1:3", "fini : le suivant");
});

test("serie : reprise faite sur un autre appareil (bibliotheque Stremio)", () => {
    const meta = { videos: [{ id: "s:1:1", season: 1, episode: 1 }, { id: "s:2:1", season: 2, episode: 1 },
                            { id: "s:2:2", season: 2, episode: 2 }] };
    const item = at => ({ _id: "s", state: { video_id: "s:2:1", timeOffset: 1000, lastWatched: new Date(at).toISOString() } });
    let p = resume.record({}, "A", "s:1:1", 600000, 1200000, Date.parse("2026-10-01"));
    assert.equal(resume.seriesResume(meta, p, "A", item(Date.parse("2026-10-10"))).id, "s:2:1", "compte plus recent");
    assert.equal(resume.seriesResume(meta, p, "A", item(Date.parse("2026-09-01"))).id, "s:1:1", "box plus recente");
    const ended = { _id: "s", state: { video_id: "s:2:1", timeOffset: 0, flaggedWatched: 1, lastWatched: "2026-10-10T00:00:00Z" } };
    assert.equal(resume.seriesResume(meta, {}, "A", ended).id, "s:2:2", "termine : le suivant");
    assert.equal(resume.seriesResume(meta, {}, "A", null), null);
});
