.pragma library
// Reglages de l'appli. L'adresse du PC n'est plus ecrite en dur : l'appli est chargee depuis
// l'agent du PC (http://<PC>:11480/fbx/app/...), on en deduit les services du meme PC.

const AGENT_PORT = 11480;
const STREMIO_PORT = 11470;

// pcHost : adresse du PC (ex. "192.168.0.16") ; "" sans PC (services vides : lecture directe).
function settingsFor(pcHost) {
    if (!pcHost)
        return { pcHost: "", agent: "", server: "", companion: "", maxWidth: 1280 };
    return {
        pcHost: pcHost,
        agent: "http://" + pcHost + ":" + AGENT_PORT,
        // Serveur de streaming Stremio (Stremio Desktop sur le PC).
        server: "http://" + pcHost + ":" + STREMIO_PORT,
        // Agent / compagnon : relais HLS sans piste de sous-titres, affiches, sous-titres integres.
        companion: "http://" + pcHost + ":" + AGENT_PORT,
        maxWidth: 1280
    };
}

// "http://192.168.0.16:11480/fbx/app/qml/" -> "192.168.0.16" ; "" si chargement local.
function hostFromUrl(url) {
    const m = /^https?:\/\/([^\/:]+)/.exec(String(url));
    return m ? m[1] : "";
}

// Addons utilises sans compte lie. Avec un compte, ce sont ceux du compte.
const DEFAULT_ADDONS = [
    "https://v3-cinemeta.strem.io/manifest.json",
    "https://opensubtitles-v3.strem.io/manifest.json"
];

// Scenario automatique de verification (developpement) ; null en usage normal.
// Exemples : { type: "movie", id: "tt0241527", noPlay: true }
//            { type: "series", id: "tt5753856", episode: "tt5753856:1:1", noPlay: true }
// Verification de chargement du lecteur : { loadPlayer: true }
const AUTOTEST = null;

// Developpement : ignorer tout PC, comme une box seule (tools/fbx_qml_run.py --sans-pc).
const NO_PC = false;

// Journal de l'element qui a le focus (verification des touches a distance).
const DEBUG_FOCUS = true;
