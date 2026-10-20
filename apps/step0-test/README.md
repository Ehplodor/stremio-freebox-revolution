# Étape 0 : appli de test de faisabilité

Petite appli QML (JavaScript ES5) qui vérifie sur le Freebox Player Revolution ce que le plan marque **[à vérifier]** :

| # | Test | Ce qu'on apprend |
|---|---|---|
| 1 | Version Qt, modules, JavaScript | Plus haute version de `QtQuick` / `QtMultimedia` importable (donc version de Qt), modules `fbx.*` présents, syntaxe ES6 acceptée ou non. Lancé automatiquement au démarrage. |
| 2-4 | XHR Cinemeta | HTTPS vers `v3-cinemeta.strem.io` (certificats récents acceptés ?), HTTP simple, redirection 307 du catalogue. |
| 5 | XHR serveur Stremio du PC | La box joint `http://192.168.0.16:11470/settings` (adresse dans `js/config.js`). |
| 6-10 | QtMultimedia | MP4 H.264, HLS en HTTPS et HTTP, MKV H.264, MP4 servi par le PC. |
| 11-14 | `fbx.media.VideoPlayer` | Mêmes flux avec le lecteur natif Freebox, dont HLS avec préfixe `hls+` (l'exemple `miniplay` utilise `dash+https://`). |
| 15 | `App.urlOpen` | Ouverture dans le lecteur système du Player. |

Télécommande : Haut/Bas pour choisir, OK pour lancer, Retour pour arrêter la vidéo ou quitter. Les résultats s'affichent à droite et dans la console du PC.

## Lancer depuis le PC Windows

1. Sur le Player : activer le mode développeur dans les réglages.
2. Sur le PC (même réseau), depuis la racine du dépôt :

```bash
python tools/fbx_qml_run.py apps/step0-test/manifest.json
```

Le script cherche le Player par mDNS (`_fbx-devel._tcp`). S'il ne le trouve pas, passer son IP : `-t 192.168.0.xx`. Il sert le dossier de l'appli sur le port 8234 du PC et affiche la sortie de l'appli. Ctrl+C pour arrêter.

Pour le test 10, déposer un MP4 H.264 nommé `media/test.mp4` dans ce dossier (non versionné).

Alternative : Qt Creator avec le plugin `fbx/freebox-qtcreator-plugin`, en ouvrant `step0-test.fbxproject`.

## Notes

- Inspiré de `fbx/qmlapps_examples` (`miniplay`, `rss_video`, `qmlkeys`) et `fbx/freebox-dev-utils` (`fbx-qml-run`), tous deux dans le domaine public. Aucun code Stremio repris.
- `PlayerFbx.qml` est chargé par un `Loader` : si `fbx.media` manque, seul ce test échoue.
- Les vidéos de test (test-videos.co.uk, test-streams.mux.dev) sont courtes ; les MP4/MKV n'ont pas de son.
