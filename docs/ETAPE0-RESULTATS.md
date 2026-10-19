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

## Conséquences pour le plan

- Le risque « runtime ancien » disparaît : on peut écrire le mini-core en JavaScript moderne.
- Le lecteur sera `MediaPlayer` de QtMultimedia, pas `fbx.media`. Les menus de pistes audio et sous-titres sont à faire nous-mêmes.
- Pas de `QtQuick.Controls` : l'interface se fait avec `fbx.ui.*` et des composants QtQuick de base.
- HTTPS fonctionne avec les certificats actuels, les addons et `api.strem.io` sont donc joignables directement.
- Reste à tester (étape 5) : le HLS transcodé par le serveur du PC (`/hlsv2/.../master.m3u8`), les sous-titres et l'audio AC3/DTS.
