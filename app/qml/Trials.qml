import QtQuick 2.15
import fbx.web 1.0

// Essais « zero PC » du jalon V2.1 (docs/V2.1-ESSAIS.md), lances a la main depuis Reglages > Essais.
// Charge par un Loader : fbx.web n'existe que sur la box (le rendu sur PC s'en passe).
//
// Freebox Server : autorisation par la fleche de la Server (FreeboxOSAuth de libfbxqml), puis
// gestionnaire de telechargements (GET /downloads/, /downloads/{id}/files : preview_url).
Item {
    id: trials

    property string appToken: ""        // jeton d'application Freebox OS (Settings de l'appli)
    property string appVersion: ""
    signal tokenChanged(string token)
    signal status(string message, string kind)
    signal logMessage(string message)
    signal playRequested(string url, string title)

    readonly property string apiBase: "http://mafreebox.freebox.fr/api/v8"
    property var auth: null
    property var os: null

    function makeClients() {
        auth = new FreeboxOSAuth.Client({
            base_url: apiBase,
            app_id: "com.ehplodor.revostream",
            app_name: "Revo Stream",
            app_version: appVersion || "2",
            device_name: "Freebox Player",
            app_token: appToken || undefined
        });
        os = new FreeboxOS.Client({ base_url: apiBase, http_transaction_factory: auth.http_transaction_factory });
        os.add("downloads");
    }

    // 1. Autorisation : la Server affiche une demande, a valider avec sa fleche droite.
    function authorize() {
        makeClients();
        logMessage("Freebox OS : demande d'autorisation");
        status("Validez sur l'écran de la Freebox Server (flèche droite)…", "warn");
        auth.query().then(() => {
            pollTimer.tries = 0;
            pollTimer.start();
        }, e => status("Autorisation impossible : " + describe(e), "error"));
    }

    function describe(e) {
        return e ? (e.message || e.msg || e.error_code || JSON.stringify(e)) : "?";
    }

    Timer {
        id: pollTimer
        property int tries: 0
        interval: 1000
        repeat: true
        onTriggered: {
            tries++;
            if (tries > 90) {
                stop();
                trials.status("Autorisation : pas de réponse de la Server en 90 s", "error");
                return;
            }
            trials.auth.check().then(state => {
                trials.logMessage("Freebox OS : autorisation " + state);
                if (state === "pending" || state === "unknown")
                    return;
                pollTimer.stop();
                if (state === "granted") {
                    trials.tokenChanged(trials.auth.app_token);
                    trials.status("Appli autorisée sur la Freebox Server", "");
                } else {
                    trials.status("Autorisation refusée (" + state + ")", "error");
                }
            }, e => trials.logMessage("Freebox OS : check en échec " + trials.describe(e)));
        }
    }

    // 2. Telechargements : liste, fichiers du plus recent, aperçu (lisible pendant le telechargement).
    function listDownloads() {
        if (!appToken) {
            status("Autorisez d'abord l'appli sur la Freebox Server", "warn");
            return;
        }
        makeClients();
        os.downloads.read().then(list => {
            list = list || [];
            logMessage("Freebox OS : " + list.length + " téléchargements");
            list.forEach(d => logMessage("  #" + d.id + " " + d.status + " " + Math.round((d.rx_pct || 0) / 100) + "% "
                                         + (d.type || "") + " " + d.name));
            const latest = list.slice().sort((a, b) => (b.created_ts || 0) - (a.created_ts || 0))[0];
            if (!latest) {
                status("Aucun téléchargement sur la Freebox Server", "warn");
                return;
            }
            os.downloads(latest.id).add("files");
            return os.downloads(latest.id).files.read().then(files => {
                files = files || [];
                files.forEach(f => logMessage("  fichier " + f.name + " " + Math.round((f.size || 0) / 1048576) + " Mo "
                                             + (f.mimetype || "") + " aperçu " + (f.preview_url ? "oui" : "non")));
                const video = files.filter(f => /^video\//.test(f.mimetype || "") && f.preview_url)
                    .sort((a, b) => (b.size || 0) - (a.size || 0))[0];
                if (!video) {
                    status("« " + latest.name + " » : aucune vidéo avec aperçu", "warn");
                    return;
                }
                // preview_url est relatif a la Server (/api/v8/dl/...), sans authentification.
                const url = /^https?:/.test(video.preview_url) ? video.preview_url
                    : "http://mafreebox.freebox.fr" + video.preview_url;
                status("Lecture de l'aperçu : " + video.name, "");
                playRequested(url, video.name);
            });
        }).then(null, e => status("Téléchargements illisibles : " + describe(e), "error"));
    }
}
