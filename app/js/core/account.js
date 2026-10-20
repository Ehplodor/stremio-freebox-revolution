.pragma library
// Compte Stremio : liaison par code (link.stremio.com), utilisateur, addons et bibliotheque
// (api.strem.io). Formes des requetes d'apres stremio-core (src/types/api, MIT,
// Copyright (c) 2018 Smart Code OOD).
// Ecriture : seulement la progression de lecture (datastorePut, voir library.js).

const API = "https://api.strem.io/api/";
const LINK = "https://link.stremio.com/api/v2/";

function unwrap(response) {
    if (response && response.error)
        throw new Error("API " + response.error.code + " : " + response.error.message);
    if (!response || response.result === undefined)
        throw new Error("réponse API inattendue");
    return response.result;
}

// Elements de la bibliotheque a montrer dans « Continuer a regarder ».
function continueWatching(items) {
    return items
        .filter(i => i.type !== "other" && (!i.removed || i.temp) && i.state && i.state.timeOffset > 0)
        .sort((a, b) => lastWatched(b) - lastWatched(a));
}

// Bibliotheque visible : ni retiree ni temporaire, plus recemment modifiee en premier.
function library(items) {
    return items
        .filter(i => i.type !== "other" && !i.removed && !i.temp)
        .sort((a, b) => mtime(b) - mtime(a));
}

// Date de modification en ms ; 0 si absente ou illisible (un NaN fausserait le tri).
function mtime(item) {
    return Date.parse(item._mtime || "") || 0;
}

function lastWatched(item) {
    return Date.parse((item.state && item.state.lastWatched) || "") || mtime(item);
}

function progress(item) {
    const s = item.state || {};
    return s.duration > 0 ? Math.min(1, s.timeOffset / s.duration) : 0;
}

// Element de bibliotheque -> meta minimale pour les rangees d'affiches.
function toMeta(item) {
    return {
        id: item._id,
        type: item.type,
        name: item.name,
        poster: item.poster || "",
        videoId: item.state ? item.state.video_id || null : null,
        progress: progress(item)
    };
}

// transport : { fetchJson(url), postJson(url, body) } -> Promise
function createAccount(transport) {
    function call(method, body) {
        return transport.postJson(API + method, body).then(unwrap);
    }

    return {
        // { code, link, qrcode } : afficher le code et le QR, l'utilisateur valide sur link.stremio.com
        createLink: () => transport.fetchJson(LINK + "create?type=Create").then(unwrap),

        // authKey si l'utilisateur a valide, sinon null (le code n'est pas encore lie).
        readLink: code => transport.fetchJson(LINK + "read?type=Read&code=" + encodeURIComponent(code))
            .then(r => r && r.result && r.result.authKey ? r.result.authKey : null),

        user: authKey => call("getUser", { type: "GetUser", authKey: authKey }),

        // Addons installes sur le compte : [{ transportUrl, manifest, flags }]
        addons: authKey => call("addonCollectionGet", { type: "AddonCollectionGet", authKey: authKey, update: true })
            .then(r => r.addons || []),

        libraryItems: authKey => call("datastoreGet", { authKey: authKey, collection: "libraryItem", ids: [], all: true }),

        // Elements modifies (LibraryItem complets) : remplace ceux du compte.
        libraryPut: (authKey, items) => call("datastorePut", { authKey: authKey, collection: "libraryItem", changes: items }),

        logout: authKey => call("logout", { type: "Logout", authKey: authKey })
    };
}

// Interroge readLink toutes les intervalMs jusqu'a obtenir la cle (ou abandon apres maxTries).
// schedule(fn, ms) : minuterie fournie par l'appelant (Timer QML ou setTimeout).
function pollLink(account, code, schedule, intervalMs, maxTries) {
    return new Promise((resolve, reject) => {
        let tries = 0;
        const tick = () => {
            tries++;
            account.readLink(code).then(key => {
                if (key)
                    resolve(key);
                else if (tries >= maxTries)
                    reject(new Error("code expire, recommencer"));
                else
                    schedule(tick, intervalMs);
            }, () => tries >= maxTries ? reject(new Error("liaison impossible")) : schedule(tick, intervalMs));
        };
        tick();
    });
}
