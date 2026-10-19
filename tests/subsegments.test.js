// Tests des sous-titres par segments : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const seg = load("app/js/core/subsegments.js");
const plain = x => JSON.parse(JSON.stringify(x));

// Forme reelle de subtitle0.m3u8 du serveur Stremio (releve le 19 octobre 2026).
const PLAYLIST = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:10\n#EXT-X-MEDIA-SEQUENCE:1\n#EXT-X-PLAYLIST-TYPE:VOD\n"
    + "#EXTINF:10.000000,\nsubtitle0/segment1.vtt?mediaURL=x&a=1\n"
    + "#EXTINF:10.000000,\nsubtitle0/segment2.vtt?mediaURL=x&a=1\n"
    + "#EXTINF:10.000000,\nsubtitle0/segment3.vtt?mediaURL=x&a=1\n"
    + "#EXTINF:4.500000,\nsubtitle0/segment4.vtt?mediaURL=x&a=1\n#EXT-X-ENDLIST\n";

test("lecture de la playlist de sous-titres", () => {
    const s = seg.parsePlaylist(PLAYLIST, "http://pc:11480/hlsv2/fbx1/subtitle0.m3u8?mediaURL=x");
    assert.equal(s.length, 4);
    assert.deepEqual(plain(s[1]), { start: 10000, end: 20000,
        url: "http://pc:11480/hlsv2/fbx1/subtitle0/segment2.vtt?mediaURL=x&a=1" });
    assert.equal(s[3].end, 34500);
});

test("segments a charger autour de la position", () => {
    const s = seg.parsePlaylist(PLAYLIST, "http://pc/hlsv2/1/subtitle0.m3u8");
    assert.deepEqual(plain(seg.needed(s, 15000, {}, 5000, 10000)), [1, 2], "le plus proche d'abord, fenetre 10-25 s");
    assert.deepEqual(plain(seg.needed(s, 15000, { 1: true }, 5000, 10000)), [2]);
    assert.deepEqual(plain(seg.needed(s, 15000, {}, 6000, 10000)), [1, 2, 0], "fenetre elargie vers l'arriere");
    assert.deepEqual(plain(seg.needed(s, 33000, {}, 0, 60000)), [3]);
});

test("fusion des cues sans doublons", () => {
    const a = [{ start: 1000, end: 2000, text: "A" }, { start: 9000, end: 12000, text: "B" }];
    const b = [{ start: 9000, end: 12000, text: "B" }, { start: 5000, end: 6000, text: "C" }];
    assert.deepEqual(plain(seg.merge(a, b).map(c => c.text)), ["A", "C", "B"]);
});
