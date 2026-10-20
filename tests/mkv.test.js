// Tests de la lecture des pistes d'un MKV (en-tete) : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const path = require("path");
const load = require("./load");

const mkv = load("app/js/core/mkv.js");
const playback = load("app/js/core/playback.js");
// 64 premiers Ko de apps/step0-test/media/multi.mkv (H.264, audio FR AAC + EN AC3, sous-titres FR/EN).
const HEAD = new Uint8Array(fs.readFileSync(path.join(__dirname, "fixtures", "multi-head.mkv")));
const plain = x => JSON.parse(JSON.stringify(x));

test("pistes lues dans l'en-tete (memes resultats que ffprobe)", () => {
    const r = mkv.parse(HEAD);
    assert.ok(r.tracks, r.error);
    assert.deepEqual(plain(r.tracks.map(t => t.type + ":" + t.language + ":" + (t.isDefault ? "d" : "-"))),
                     ["video:und:d", "audio:fre:d", "audio:eng:-", "subtitle:fre:d", "subtitle:eng:-"]);
    const audio = mkv.audioTracks(r.tracks, playback.trackLabel);
    assert.deepEqual(plain(audio.map(a => a.label)),
                     ["Français - Francais 440 Hz (AAC 1 canaux)", "Anglais - English 880 Hz (AC3 1 canaux)"]);
    assert.equal(mkv.defaultIndex(audio), 0);
});

test("en-tete tronque : position des pistes, puis lecture a cet endroit", () => {
    const full = mkv.parse(HEAD);
    // Debut reel de l'element Tracks (enfant du segment).
    const segment = mkv.children(HEAD, 0, HEAD.length)[1];
    const at = mkv.children(HEAD, segment.start, HEAD.length).find(e => e.id === 0x1654AE6B).headerStart;
    assert.ok(at > 100);
    // Coupe juste avant les pistes : position donnee par le SeekHead.
    let r = mkv.parse(HEAD.slice(0, at));
    assert.equal(r.tracksAt, at);
    // Coupe au milieu des pistes : position de l'element tronque.
    r = mkv.parse(HEAD.slice(0, at + 20));
    assert.equal(r.tracksAt, at);
    const second = mkv.parse(HEAD.slice(at), at, r.segmentStart);
    assert.equal(second.tracks.length, full.tracks.length);
});

test("autre chose qu'un MKV", () => {
    assert.ok(mkv.parse(new Uint8Array([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70])).error);
    assert.ok(mkv.parse(new Uint8Array(0)).error);
});
