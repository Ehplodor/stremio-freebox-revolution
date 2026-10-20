// Tests du prechargement : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const buf = load("app/js/core/buffer.js");

const MIN = 60000;
// Film de 2 h, 7,2 Go : 1 Mo/s (8 Mbit/s).
const film = (end, rateBps, extra) => Object.assign({ total: 7200e6, base: 0, end: end, rateBps: rateBps, done: false }, extra);

test("avance prechargee devant la position", () => {
    assert.equal(buf.aheadSeconds(film(60e6, 0), 120 * MIN, 0), 60);
    assert.equal(buf.aheadSeconds(film(60e6, 0), 120 * MIN, 30000), 30);
    assert.equal(buf.aheadSeconds(film(60e6, 0, { base: 50e6 }), 120 * MIN, 0), 0, "avant la partie prechargee");
    assert.equal(buf.aheadSeconds(film(60e6, 0, { done: true }), 120 * MIN, 0), Infinity);
});

test("attente au demarrage selon la vitesse de telechargement", () => {
    assert.equal(buf.startTarget(film(0, 5e6), 120 * MIN, 0), 12, "telechargement 5x plus rapide : 12 s");
    const slow = buf.startTarget(film(0, 0.5e6), 120 * MIN, 0);     // deux fois plus lent que la video
    assert.equal(Math.round(slow), 12 + 3600, "il faut precharger la moitie du film");
    assert.equal(buf.startTarget(film(0, 0.5e6), 120 * MIN, 110 * MIN), 12 + 300, "reprise a 10 min de la fin");
});

test("progression, temps restant, attente trop longue", () => {
    const p = buf.progress(film(6e6, 2e6), 120 * MIN, 0, 12);
    assert.equal(p.ready, false);
    assert.equal(p.percent, 50);
    assert.equal(p.etaS, 3, "6 Mo manquants a 2 Mo/s");
    assert.equal(buf.progress(film(12e6, 2e6), 120 * MIN, 0, 12).ready, true);
    assert.equal(buf.progress(film(0, 0.5e6), 120 * MIN, 0, 3612).tooLong, true);
    assert.equal(buf.defaultTarget("start"), 12);
    assert.equal(buf.defaultTarget("stall"), 30);
    assert.equal(buf.formatEta(75), "1 min 15");
    assert.equal(buf.formatEta(-1), "calcul…");
});

test("pause automatique et reprise", () => {
    assert.ok(buf.shouldStall(film(65e6, 1e6), 120 * MIN, 60000), "5 s d'avance : pause");
    assert.ok(!buf.shouldStall(film(80e6, 1e6), 120 * MIN, 60000), "20 s d'avance : on continue");
    assert.ok(!buf.shouldStall(film(65e6, 1e6, { done: true }), 120 * MIN, 60000));
    assert.ok(!buf.shouldStall(film(65e6, 1e6, { base: 60e6 }), 120 * MIN, 30000), "saut avant la partie prechargee");
    assert.ok(!buf.shouldStall(film(65e6, 1e6), 120 * MIN, 60 * MIN), "saut loin devant : relais direct");
    assert.equal(buf.resumeTarget(film(65e6, 5e6), 120 * MIN, 60000), 30);
});
