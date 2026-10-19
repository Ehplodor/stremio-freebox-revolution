// Appels HTTP par XMLHttpRequest. ES5 uniquement.

// callback(err, status, text, ms) ; err est une chaine ou null.
function get(url, callback) {
    var start = new Date().getTime();
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
        var ms = new Date().getTime() - start;
        if (xhr.status === 0) {
            callback("echec reseau ou TLS (status 0)", 0, "", ms);
            return;
        }
        callback(null, xhr.status, xhr.responseText, ms);
    };
    xhr.open("GET", url);
    xhr.send();
}

// Resume court d'une reponse JSON, pour l'affichage.
function summarize(text, picker) {
    try {
        var data = JSON.parse(text);
        return picker(data);
    } catch (e) {
        return "JSON invalide (" + text.length + " octets) : " + e;
    }
}
