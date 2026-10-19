// Transport HTTP de l'appli : XMLHttpRequest -> Promise. Injecte dans le mini-core (js/core).

function request(method, url, body, asText) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
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
