# Étape 0 : résultats sur le Freebox Player Revolution

_19 octobre 2026. Appli `apps/step0-test` lancée depuis le PC Windows (192.168.0.16) avec `tools/fbx_qml_run.py`, Player en mode développeur à l'adresse 192.168.0.42 (trouvé par mDNS `_fbx-devel._tcp`)._

## Runtime

| Point | Résultat |
|---|---|
| Qt | **5.15** (QtQuick 2.15, QtMultimedia 5.15), Linux, écran 1280×720 |
| JavaScript | ES6+ complet : `let`/`const`, fonctions fléchées, template strings, classes, `Promise`, `Object.assign`, `Array.prototype.find` |
| Modules présents | `fbx.application`, `fbx.ui.control`, `fbx.ui.menu`, `fbx.web`, `fbx.async`, `fbx.data`, `QtQuick.XmlListModel` |
| Modules absents | **`fbx.media`**, `QtQuick.Controls` 1 et 2 |
| Racine `Application` | C'est une fenêtre : `Keys` ne s'y attache pas, il faut un `FocusScope` enfant |

## Réseau (XMLHttpRequest)

| Test | Résultat |
|---|---|
| HTTPS `v3-cinemeta.strem.io/manifest.json` | OK, 200 en 186 ms |
| HTTP même URL | OK, 200 en 44 ms |
| Catalogue `catalog/movie/top.json` (redirection 307 vers un autre hôte) | OK, 50 films, 130 ko |
| Serveur Stremio du PC `http://192.168.0.16:11470/settings` | OK, serveur 4.21.2 |

## Lecture (QtMultimedia `MediaPlayer` + `VideoOutput`, moteur `fbxmms`)

| Flux | Résultat |
|---|---|
| MP4 H.264 720p en HTTPS | OK, lu jusqu'à la fin |
| HLS H.264 en HTTPS | OK, lecture continue sur 20 s |
| HLS H.264 en HTTP | OK |
| MKV H.264 720p en HTTPS | OK, lu jusqu'à la fin |
| `fbx.media.VideoPlayer` | Non testable : module absent |

## Étape 0 bis : transcodage par le serveur du PC (tests sans témoin)

Vidéos synthétiques 60 s 720p générées par `tools/make_test_media.sh` et servies par le PC. Le Player était seul : les journaux montrent l'image décodée (résolution remontée) et la position qui avance, **pas le son**.

| Test | Résultat |
|---|---|
| Module complémentaire | `fbx.ui.base/controller/layout/page/dialog/settings`, `fbx.crypto`, `fbx.wl`, `fbx.inapp`, `QtQuick.Window/Layouts`, `QtGraphicalEffects`, `QtQuick.LocalStorage`, `QtWebSockets` présents ; `fbx.os.mms`, `fbx.cdm`, `Qt.labs.settings` absents |
| Débit PC vers box (XHR 20 Mo) | **9,3 Mbit/s** (internet vers box : 2,5 Mbit/s sur un petit fichier) |
| H.264 + AC3 5.1 / E-AC3 5.1 / DTS 5.1 en direct (MKV) | Lecture complète, image décodée. Son à confirmer à l'oreille |
| HEVC en direct | La position avance mais aucune image décodée (attendu : pas de HEVC) |
| `/hlsv2/probe` depuis la box | OK : `matroska, video hevc, audio ac3, subtitle subrip` |
| HEVC → HLS H.264/AAC (`/hlsv2/.../master.m3u8`) | **Bloque à 10 s**, reproductible, même avec le transcodage déjà en cache |
| Même chose sur un MKV HEVC **sans** sous-titres | Lecture fluide sur 40 s |
| Même fichier avec sous-titres via un relais qui retire la piste `SUBTITLES` du master | **Lecture fluide sur 40 s** |
| AC3 forcé vers AAC, HEVC 1080p internet transcodé | OK |
| `/subtitles.vtt?from=<srt>` | OK, VTT correct (accents compris) |

Analyse :
- Le serveur Stremio transcode du HEVC 720p en 2,3 s pour 60 s de vidéo (NVENC) : le PC n'est pas un goulot.
- Le serveur ajoute au `master.m3u8` une piste `#EXT-X-MEDIA:TYPE=SUBTITLES` découpée en segments VTT de 10 s. Le lecteur HLS du Player se bloque à la fin du premier segment. Aucun paramètre du serveur ne retire cette piste.
- Contournement retenu : un petit relais sur le PC (`/stremio/...` dans `tools/fbx_qml_run.py`) qui retire cette piste ; les sous-titres seront affichés par l'appli elle-même (calque `Text` alimenté par `/subtitles.vtt` ou `subtitle0.m3u8`). À terme, ce relais deviendra un petit service compagnon sur le PC, à côté de Stremio.
- Le flux transcodé fait environ 6 Mbit/s pour cette mire très chargée ; avec 9,3 Mbit/s mesurés entre le PC et la box, la marge est faible pour du 1080p. Brancher le Player en Ethernet ou limiter le débit de transcodage est à prévoir.

## Conséquences pour le plan

- Le risque « runtime ancien » disparaît : on peut écrire le mini-core en JavaScript moderne.
- Le lecteur sera `MediaPlayer` de QtMultimedia, pas `fbx.media`. Les menus de pistes audio et sous-titres sont à faire nous-mêmes.
- Pas de `QtQuick.Controls` : l'interface se fait avec `fbx.ui.*` et des composants QtQuick de base.
- HTTPS fonctionne avec les certificats actuels, les addons et `api.strem.io` sont donc joignables directement.
- Reste à tester (étape 5) : le HLS transcodé par le serveur du PC (`/hlsv2/.../master.m3u8`), les sous-titres et l'audio AC3/DTS.
