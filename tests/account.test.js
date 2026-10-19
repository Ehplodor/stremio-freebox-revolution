// Tests du module compte : node --test tests/*.test.js
"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const load = require("./load");

const account = load("app/js/core/account.js");
const plain = x => JSON.parse(JSON.stringify(x));

function fakeTransport(routes, calls) {
    const answer = (url, body) => {
        calls.push(body ? { url: url, body: body } : { url: url });
        for (const prefix of Object.keys(routes)) {
            if (url.indexOf(prefix) === 0) {
                const r = routes[prefix];
                return Promise.resolve(typeof r === "function" ? r(body) : r);
            }
        }
        return Promise.reject(new Error("404 " + url));
    };
    return { fetchJson: url => answer(url), postJson: (url, body) => answer(url, body) };
}

const item = (id, extra) => Object.assign({
    _id: id, name: id, type: "movie", poster: "", removed: false, temp: false,
    _mtime: "2026-10-01T00:00:00.000Z",
    state: { timeOffset: 0, duration: 0, lastWatched: null, video_id: null }
}, extra);

test("liaison par code puis cle", async () => {
    const calls = [];
    let reads = 0;
    const acc = account.createAccount(fakeTransport({
        "https://link.stremio.com/api/v2/create?type=Create": { result: { success: true, code: "AB12", link: "https://link.stremio.com/AB12", qrcode: "https://link.stremio.com/qr?data=x" } },
        "https://link.stremio.com/api/v2/read?type=Read&code=AB12": () => (++reads < 3
            ? { error: { code: 101, message: "Invalid or expired token" } }
            : { result: { authKey: "KEY" } })
    }, calls));
    const link = await acc.createLink();
    assert.equal(link.code, "AB12");
    const key = await account.pollLink(acc, link.code, (fn, ms) => setImmediate(fn), 10, 5);
    assert.equal(key, "KEY");
    assert.equal(reads, 3);
});

test("liaison abandonnee apres le nombre d'essais", async () => {
    const acc = account.createAccount(fakeTransport({
        "https://link.stremio.com/api/v2/read": { error: { code: 101, message: "x" } }
    }, []));
    await assert.rejects(account.pollLink(acc, "ZZ", fn => setImmediate(fn), 1, 3), /expire/);
});

test("requetes API du compte", async () => {
    const calls = [];
    const acc = account.createAccount(fakeTransport({
        "https://api.strem.io/api/getUser": { result: { email: "a@b.c" } },
        "https://api.strem.io/api/addonCollectionGet": { result: { addons: [{ transportUrl: "https://x/manifest.json", manifest: { name: "X" } }] } },
        "https://api.strem.io/api/datastoreGet": { result: [item("tt1")] },
        "https://api.strem.io/api/logout": { error: { code: 1, message: "Session does not exist" } }
    }, calls));
    assert.equal((await acc.user("K")).email, "a@b.c");
    assert.equal((await acc.addons("K"))[0].manifest.name, "X");
    assert.equal((await acc.libraryItems("K")).length, 1);
    await assert.rejects(acc.logout("K"), /Session does not exist/);
    assert.deepEqual(plain(calls.map(c => c.body)), [
        { type: "GetUser", authKey: "K" },
        { type: "AddonCollectionGet", authKey: "K", update: true },
        { authKey: "K", collection: "libraryItem", ids: [], all: true },
        { type: "Logout", authKey: "K" }
    ]);
});

test("continuer a regarder et bibliotheque", () => {
    const items = [
        item("vu", { state: { timeOffset: 600000, duration: 6000000, lastWatched: "2026-10-10T00:00:00Z", video_id: null } }),
        item("serie", { type: "series", state: { timeOffset: 100, duration: 1000, lastWatched: "2026-10-18T00:00:00Z", video_id: "tt9:1:2" } }),
        item("retire", { removed: true, state: { timeOffset: 5, duration: 10 } }),
        item("temp", { removed: true, temp: true, _mtime: "2026-10-19T00:00:00Z", state: { timeOffset: 5, duration: 10, lastWatched: "2026-10-01T00:00:00Z" } }),
        item("autre", { type: "other", state: { timeOffset: 5, duration: 10 } }),
        item("jamais", { _mtime: "2026-10-15T00:00:00Z" })
    ];
    assert.deepEqual(plain(account.continueWatching(items).map(i => i._id)), ["serie", "vu", "temp"]);
    assert.deepEqual(plain(account.library(items).map(i => i._id)), ["jamais", "vu", "serie"]);
    const m = account.toMeta(items[1]);
    assert.equal(m.videoId, "tt9:1:2");
    assert.equal(m.progress, 0.1);
});
