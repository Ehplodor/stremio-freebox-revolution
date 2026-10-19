// Reglages de developpement. Ils passeront dans un ecran Reglages (stockage local) plus tard.

const PC = "192.168.0.16";

const SETTINGS = {
    // Serveur de streaming Stremio (Stremio Desktop ou stremio-service sur le PC).
    server: "http://" + PC + ":11470",
    // Service compagnon (companion/companion.py) : relais HLS sans piste de sous-titres.
    companion: "http://" + PC + ":11480",
    maxWidth: 1280
};

// Addons utilises sans compte lie. Avec un compte, ce sont ceux du compte.
const DEFAULT_ADDONS = [
    "https://v3-cinemeta.strem.io/manifest.json",
    "https://opensubtitles-v3.strem.io/manifest.json"
];

// Ajoutes dans tous les cas pendant le developpement : addon de test servi par le PC
// (tools/test_addon.py). Ignore s'il ne repond pas.
const DEV_ADDONS = [
    "http://" + PC + ":8235/manifest.json"
];

// Scenario automatique pour tester sans telecommande : vide pour desactiver.
// Ouvre la fiche indiquee, lance son premier flux, puis revient a l'accueil.
// account: true ouvre d'abord l'ecran Compte quelques secondes (code de liaison).
// linkOnly: true ouvre seulement l'ecran Compte (le code s'affiche aussi dans la console du PC).
// noPlay: true s'arrete a la liste des flux (aucune lecture, donc rien de debloque chez le debrideur).
// Exemple : { type: "movie", id: "tt0241527", noPlay: true }
// tracks: true change de piste audio puis de sous-titres pendant la lecture.
// Exemple : { type: "movie", id: "fbxtest-multi", tracks: true, playSeconds: 60 }
// sort: true modifie le tri comme a la telecommande puis remet les preferences.
// Exemple : { type: "movie", id: "tt0241527", sort: true }
const AUTOTEST = null;
