// Transport HTTP de l'appli : XMLHttpRequest -> Promise. Injecte dans le mini-core (js/core).

// Delai maximal d'une requete : certains addons ne repondent jamais.
const TIMEOUT_MS = 25000;

// Ce fichier n'est pas une .pragma library : il voit l'id "app" de main.qml, parent des minuteries.
function startTimer(ms, fn) {
    const timer = Qt.createQmlObject("import QtQuick 2.0; Timer { repeat: false }", app, "httpTimeout");
    timer.interval = ms;
    timer.triggered.connect(() => {
        fn();
        timer.destroy();
    });
    timer.start();
    return timer;
}

function request(method, url, body, asText) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        let finished = false;
        const timer = startTimer(TIMEOUT_MS, () => {
            if (finished)
                return;
            finished = true;
            xhr.abort();
            reject(new Error("pas de reponse apres " + TIMEOUT_MS / 1000 + " s"));
        });
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE || finished)
                return;
            finished = true;
            timer.stop();
            timer.destroy();
            if (xhr.status < 200 || xhr.status >= 300) {
                reject(new Error("HTTP " + xhr.status + " : " + url));
                return;
            }
            if (asText) {
                resolve(xhr.responseText);
                return;
            }
            try {
                resolve(xhr.responseText ? JSON.parse(xhr.responseText) : null);
            } catch (e) {
                reject(new Error("JSON invalide : " + url));
            }
        };
        xhr.open(method, url);
        if (body !== undefined)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body !== undefined ? JSON.stringify(body) : null);
    });
}

function fetchJson(url) {
    return request("GET", url);
}

function postJson(url, body) {
    return request("POST", url, body);
}

function fetchText(url) {
    return request("GET", url, undefined, true);
}
