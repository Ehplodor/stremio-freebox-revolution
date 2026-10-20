// Tests du tri des flux : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const sorting = load("app/js/core/sorting.js");
const plain = x => JSON.parse(JSON.stringify(x));

// Textes au format reel des addons (Torrentio public, Comet), raccourcis.
const S = {
    uhdHdr: { name: "Torrentio\n4k HDR", title: "Harry Potter 2160p BluRay x265 HEVC 10bit HDR AAC 7.1\n👤 80 💾 14.98 GB ⚙️ 1337x" },
    dv1080: { name: "[AD+] Torrentio\n1080p DV", title: "Harry.Potter.2001.1080p.WEB-DL.DV.HEVC\n👤 5 💾 6.1 GB" },
    frCached: { name: "[AD+] Torrentio\n1080p", title: "Harry Potter 2001 MULTi TRUEFRENCH 1080p BluRay x264\n👤 40 💾 9.2 GB\n🇫🇷 / 🇬🇧" },
    enCached: { name: "[AD+] Torrentio\n1080p", title: "Harry Potter 2001 1080p BluRay x264\n👤 300 💾 2.5 GB\n🇬🇧" },
    frDownload: { name: "[AD download] Torrentio\n1080p", title: "Harry Potter 2001 FRENCH 1080p x265\n👤 12 💾 3.1 GB" },
    comet720: { name: "[AD⚡] Comet 720p", description: "Harry Potter 720p VFF\n💾 1.4 GB" },
    unknown: { name: "Lumio", title: "Harry Potter" }
};
const items = Object.keys(S).map(k => ({ addon: k, stream: S[k] }));

test("lecture des informations d'un flux", () => {
    const i = sorting.parse(S.uhdHdr);
    assert.equal(i.resolution, 2160);
    assert.ok(i.hdr && !i.dv);
    assert.equal(i.codec, "HEVC");
    assert.equal(i.sizeGb, 14.98);
    assert.equal(i.seeders, 80);
    assert.equal(i.cached, null);

    const f = sorting.parse(S.frCached);
    assert.equal(f.cached, true);
    assert.deepEqual(plain(f.languages).sort(), ["en", "fr", "multi"]);
    assert.equal(sorting.parse(S.frDownload).cached, false);
    assert.equal(sorting.parse(S.comet720).cached, true);
    assert.ok(sorting.parse(S.dv1080).dv);
    assert.equal(sorting.badges(f), "En cache · 1080p · H.264 · FR/EN/MULTI · 9.2 Go · 40 sources");
});

test("tri par defaut : en cache, puis inconnu, puis a telecharger ; 4K et Dolby Vision masques", () => {
    const r = sorting.sortStreams(items, null);
    assert.deepEqual(plain(r.visible.map(x => x.addon)), ["frCached", "enCached", "comet720", "unknown", "frDownload"]);
    assert.equal(r.hidden, 2);
});

test("preferences modifiees : langue anglaise, 4K permise, taille d'abord, cache obligatoire", () => {
    let p = sorting.normalize(null);
    p = sorting.edit(p, "languages", 1);                 // multi
    p = sorting.edit(p, "languages", 1);                 // en
    assert.equal(p.languages, "en");
    p = sorting.edit(p, "maxResolution", -1);            // 1080 -> 2160
    assert.equal(p.maxResolution, 2160);
    p = sorting.edit(p, "hideUncached", 0);
    for (let k = 0; k < 5; k++)
        p = sorting.edit(p, "order:size", -1);           // remonte la taille en tete
    assert.deepEqual(plain(p.order), ["size", "addon", "cached", "resolution", "language", "direct", "seeders"]);
    const r = sorting.sortStreams(items, p);
    // "a telecharger" masque ; les flux sans indication (pas de debrideur) restent.
    assert.deepEqual(plain(r.visible.map(x => x.addon)), ["comet720", "enCached", "frCached", "uhdHdr", "unknown"]);
    assert.equal(sorting.edit(p, "reset", 0).languages, "fr");
});

test("preferences anciennes ou partielles completees", () => {
    const p = sorting.normalize({ order: ["size", "inconnu", "size"], maxSizeGb: 10 });
    assert.equal(p.order[0], "addon", "sans effet tant qu'aucun ordre d'addons n'est choisi");
    assert.equal(p.order[1], "size", "puis le choix de l'utilisateur");
    assert.deepEqual(plain(p.order.slice().sort()), ["addon", "cached", "direct", "language", "resolution", "seeders", "size"]);
    // Preferences enregistrees avant l'ajout du critere "direct" : il reprend sa place.
    const old = sorting.normalize({ order: ["cached", "resolution", "language", "size", "seeders"] });
    assert.deepEqual(plain(old.order), ["addon", "cached", "resolution", "language", "direct", "size", "seeders"]);
    const testRun = sorting.normalize({ order: ["cached", "resolution", "language", "size", "seeders", "direct"] });
    assert.deepEqual(plain(testRun.order), ["addon", "cached", "resolution", "language", "direct", "size", "seeders"]);
    assert.equal(p.maxSizeGb, 10);
    assert.equal(p.hideDolbyVision, true);
    const rows = sorting.settingsRows(p);
    assert.equal(rows[0].value, "Addon (ordre choisi ci-dessous)");
    assert.equal(rows[1].value, "Taille (plus petit d'abord)");
    assert.equal(rows.find(r => r.key === "maxSizeGb").value, "10 Go");
});

test("fichiers trop petits masques, H.264 prefere a qualite egale, taille en Mo", () => {
    const list = [
        { addon: "hevc", stream: { name: "[AD+] T\n1080p", title: "Film 1080p x265 FRENCH\n💾 2.0 GB" } },
        { addon: "h264", stream: { name: "[AD+] T\n1080p", title: "Film 1080p x264 FRENCH\n💾 4.0 GB" } },
        { addon: "extrait", stream: { name: "[AD+] T\n1080p", title: "Film sample 1080p x264 FRENCH\n💾 120 MB" } }
    ];
    const r = sorting.sortStreams(list, null);
    assert.deepEqual(plain(r.visible.map(x => x.addon)), ["h264", "hevc"]);
    assert.equal(r.hidden, 1);
    const shown = sorting.sortStreams(list, sorting.edit(null, "hideTiny", 0));
    assert.equal(shown.visible.length, 3);
    assert.match(shown.visible.find(x => x.addon === "extrait").badges, /120 Mo/);
});

test("H.264 10 bits non compte comme lisible directement", () => {
    const list = [
        { addon: "10b", stream: { name: "[AD+] T", title: "Anime 1080p x264 10bit FRENCH" } },
        { addon: "8b", stream: { name: "[AD+] T", title: "Anime 1080p x264 FRENCH" } }
    ];
    assert.equal(sorting.parse(list[0].stream).codec, "H.264 10 bits");
    assert.deepEqual(plain(sorting.sortStreams(list, null).visible.map(x => x.addon)), ["8b", "10b"]);
});

test("priorite par addon modifiable", () => {
    const names = ["Torrentio", "Comet", "Lumio"];
    const list = [
        { addon: "Torrentio", stream: { name: "[AD+] T\n1080p", title: "Film 1080p x264 FRENCH" } },
        { addon: "Comet", stream: { name: "[AD+] C\n720p", title: "Film 720p x264 FRENCH" } },
        { addon: "Lumio", stream: { name: "L", title: "Film 1080p x264 FRENCH" } }
    ];
    assert.deepEqual(plain(sorting.sortStreams(list, null).visible.map(x => x.addon)), ["Torrentio", "Comet", "Lumio"],
        "sans ordre d'addons : criteres habituels (en cache d'abord)");
    let p = sorting.edit(null, "addon:Comet", -1, names);      // Comet monte d'un cran
    p = sorting.edit(p, "addon:Comet", -1, names);
    assert.deepEqual(plain(p.addonOrder), ["Comet", "Torrentio", "Lumio"]);
    assert.deepEqual(plain(sorting.sortStreams(list, p).visible.map(x => x.addon)), ["Comet", "Torrentio", "Lumio"]);
    const rows = sorting.settingsRows(p, names.concat(["Nouveau"]));
    assert.deepEqual(plain(rows.filter(r => r.key.indexOf("addon:") === 0).map(r => r.value)),
        ["Comet", "Torrentio", "Lumio", "Nouveau"]);
});

test("episode suivant : source la plus proche (addon, equipe, resolution, langue)", () => {
    const sorted = sorting.sortStreams([
        { addon: "Comet", stream: { name: "[AD+] Comet 1080p", title: "Serie.S01E02.1080p.WEB.x264.MULTi-GROUPA" } },
        { addon: "Torrentio", stream: { name: "[AD+] Torrentio\n1080p", title: "Serie.S01E02.1080p.WEB.x265.FRENCH-GROUPB" } },
        { addon: "Torrentio", stream: { name: "[AD+] Torrentio\n720p", title: "Serie.S01E02.720p.WEB.x264.MULTi-GROUPA" } },
        { addon: "Torrentio", stream: { name: "[AD+] Torrentio\n1080p", title: "Serie.S01E02.1080p.WEB.x264.MULTi-GROUPA" } }
    ], null).visible;
    const prev = sorting.sortStreams([{ addon: "Torrentio",
        stream: { name: "[AD+] Torrentio\n1080p", title: "Serie.S01E01.1080p.WEB.x264.MULTi-GROUPA" } }], null).visible[0];
    assert.equal(prev.info.group, "groupa");
    const pick = sorting.closest(prev, sorted);
    assert.equal(pick.addon, "Torrentio");
    assert.equal(pick.info.resolution, 1080);
    assert.equal(pick.info.group, "groupa");
    assert.equal(sorting.closest(prev, []), null);
});
