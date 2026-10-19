# Plan de portage de Stremio vers la Freebox Player Revolution

_Version 2, 19 octobre 2026. Basé sur la lecture du code des dépôts publics `github.com/stremio` et `github.com/fbx` (SDK Freebox). Les points marqués **[à vérifier]** n'ont pas pu être confirmés sans une box en mode développeur._

## 1. Conclusion en une phrase

On ne peut pas « porter » l'application Stremio existante telle quelle : le Player Revolution n'exécute que des applications **QML/JavaScript (Qt 5)**, sans navigateur moderne ni WebAssembly ni code natif. Il faut écrire **un nouveau client QML** qui parle le même protocole d'addons et la même API de compte que Stremio, et s'appuyer sur un **serveur de streaming Stremio externe** (PC, NAS, Raspberry Pi) pour les torrents et le transcodage.

## 2. Ce que fait Stremio aujourd'hui (dépôts étudiés)

| Dépôt | Rôle | Techno | Réutilisable sur Freebox ? |
|---|---|---|---|
| `stremio-core` | Toute la logique : addons, bibliothèque, profil, lecteur, notifications, liaison de compte (`models/link.rs`) | Rust, compilé en WASM pour le web (`stremio-core-web`) | **Non** en binaire. **Oui** comme spécification : types, appels API, règles métier à réécrire en JS |
| `stremio-web` | Interface web (React 18, webpack) | JS/React + core WASM | **Non** (pas de moteur web moderne sur le Player). Sert de référence UX |
| `stremio-video` | Abstraction des lecteurs (HTML5, Tizen, webOS, Titan, Vidaa, Chromecast…) + `withStreamingServer` | JS | **Partiellement** : la logique `withStreamingServer` (URL `/hlsv2/.../master.m3u8`, `/hlsv2/probe`, `/subtitles.vtt`, `/opensubHash`) est à transposer telle quelle |
| `stremio-shell` | Appli de bureau Qt5/QML qui embarque stremio-web dans QtWebEngine + mpv | C++/Qt | **Non** (QtWebEngine et mpv absents du Player) |
| `stremio-addon-sdk` | SDK pour créer des addons + doc du protocole (`docs/protocol.md`, `docs/api/`) | Node.js | **Oui** : la doc du protocole est la spécification du client. Le SDK lui-même sert à créer un addon de test |
| Serveur de streaming (`server.js`, image Docker) | Torrent vers HTTP, transcodage HLS (ffmpeg), sous-titres | Node.js | **Oui, mais hors de la box** (voir §4) |

Points du protocole utiles pour le client :
- Addons : `GET {base}/manifest.json`, `/catalog/{type}/{id}.json`, `/meta/{type}/{id}.json`, `/stream/{type}/{id}.json`, `/subtitles/...`. Simple JSON par HTTP, parfaitement faisable en `XMLHttpRequest` QML.
- Un flux (`Stream`) peut être `url` (HTTP direct), `infoHash`+`fileIdx` (torrent), `ytId` (YouTube) ou `externalUrl`. Les flux `behaviorHints.notWebReady` / `proxyHeaders` doivent passer par le serveur de streaming.
- Compte : `https://api.strem.io` (`login`, `getUser`, `addonCollectionGet/Set`, `datastoreGet/Put` pour la bibliothèque et la progression). Liaison TV par code via `https://link.stremio.com`, ce qui évite de taper un mot de passe à la télécommande.

## 3. Contraintes de la Freebox Player Revolution

**Environnement applicatif (SDK QML, `github.com/fbx/libfbxqml`, `fbx/qmlapps_examples`)**
- Applications 100 % **QML + JavaScript**, Qt 5 / QtQuick 2.x (exemples de `QtQuick 2.0` à `2.7`, plugin Qt Creator prévu pour Qt 5.8). Pas de C++ tiers, pas de WebView, pas de WASM.
- Paquet = dossier avec `manifest.json` (nom, identifiant, `capabilities` comme `net_wan`, `entryPoints`) + fichiers `.qml`.
- Bibliothèque `fbx.*` : `fbx.ui.*` (contrôles adaptés télécommande, menus, pages, dialogues), `fbx.web` (Http, Rest, OAuth, Store, client Freebox OS), `fbx.async` (Deferred/promesses), `fbx.media` (`VideoPlayer`, `PlayerTimeline`, `VideoSeekController`, menu des pistes audio/sous-titres), `fbx.cdm` (DRM Widevine), `fbx.inapp`, `App.urlOpen()`.
- QtMultimedia `MediaPlayer` + `VideoOutput` aussi disponibles (exemple `rss_video`). L'exemple `miniplay` lit du DASH (`dash+https://...`).
- Télécommande : événements `Keys` Qt standard (flèches, OK, Retour = `Qt.Key_Back`, Menu, Info, Recherche, chiffres). Navigation 100 % au focus, pas de souris ni de clavier.
- Développement : activer le mode développeur dans les réglages du Player, puis lancer depuis Qt Creator avec le plugin Freebox (découverte de la box sur le réseau, debug à distance) ou `fbx-qml-run`. Pas d'émulateur ; certains modules ne fonctionnent que sur la box.

**Matériel et vidéo** (box de 2010)
- Décodage : H.264, MPEG-2, MPEG-4 ASP (DivX/Xvid), VC-1. Conteneurs MKV, MP4, AVI, TS, MOV… Audio AAC/AC3/E-AC3/DTS (downmix stéréo) ou passthrough HDMI. Source : liste officielle Free de 2011.
- **Pas de HEVC/H.265, pas de VP9/AV1, pas de 4K, pas de HDR.** Une grande partie des flux actuels (x265, 4K) devra donc être **transcodée en H.264** par le serveur de streaming.
- Processeur Intel Atom CE4100 et mémoire limitée **[à vérifier]** : interface légère obligatoire (affiches en petite taille, listes virtualisées, peu d'animations).
- Lecteur : HLS et sous-titres externes (SRT/VTT) **[à vérifier]**. En repli, affichage des sous-titres par un calque `Text` QML synchronisé sur la position de lecture.
- Version exacte du runtime QML sur la Revolution aujourd'hui **[à vérifier]** : certains exemples récents utilisent `let` (ES6), ce qui suppose un Qt 5.12+ ; la Revolution peut être plus ancienne. Premier test à faire sur la box.

**Publication**
- Compte développeur sur `https://factory.free.fr` (FreeFactory), envoi d'une archive TAR générée par Qt Creator (« Make FreeStore Package »), gestion bêta/finale, bêta-testeurs, visuels (icônes 80/150/220 px, bannières 300×90 et 736×152, cf. exemple `appletrailers/freestore`).
- Validation par Free avant mise sur le FreeStore. Critères non publics **[à vérifier]**.

## 4. Architecture cible

```
 Freebox Player Revolution (appli QML)          Réseau local / Internet
 ┌──────────────────────────────────┐
 │ UI QML (fbx.ui) : Accueil,       │──HTTP JSON──▶ Addons Stremio (Cinemeta, OpenSubtitles, addons perso)
 │ Découvrir, Fiche, Choix du flux, │──HTTP JSON──▶ api.strem.io / link.stremio.com (compte, bibliothèque)
 │ Bibliothèque, Réglages           │
 │ « mini-core » JS : addons,       │──HTTP──────▶ Serveur de streaming Stremio (PC/NAS/RPi, Docker)
 │ bibliothèque, progression        │                 torrent → HTTP, transcodage HLS H.264, sous-titres VTT
 │ Lecteur : fbx.media.VideoPlayer  │◀──HLS/MP4───
 └──────────────────────────────────┘
```

1. **Interface QML** construite avec `fbx.ui` pour respecter l'ergonomie télécommande du Player.
2. **« Mini-core » en JavaScript** (fichiers `.pragma library`), réécriture ciblée de `stremio-core` : client de transport d'addons, agrégation des catalogues, résolution meta/streams, modèle bibliothèque et progression, synchronisation via `datastoreGet/Put`. On garde les mêmes structures JSON que `stremio-core/src/types` pour rester compatible avec le compte Stremio.
3. **Lecteur** basé sur `fbx.media.VideoPlayer` (à défaut `MediaPlayer`+`VideoOutput`), avec la logique de `stremio-video/withStreamingServer` : si le flux est un torrent, non web-ready ou dans un codec non supporté, on passe par `/hlsv2/{id}/master.m3u8?...` du serveur avec un profil H.264/AAC 1080p max.
4. **Serveur de streaming externe** : la Freebox Revolution (Server) ne permet pas d'héberger de VM/Docker, et le Player ne peut pas exécuter Node.js. Choix retenu : le PC Windows de la maison (voir §7). L'appli le trouve par son adresse IP saisie une fois dans les réglages.
5. **Mode sans serveur (dégradé)** : uniquement les flux `url` HTTP directs en H.264 (par exemple addons avec débrideur). Utile pour un premier MVP.

## 5. Étapes proposées

| # | Étape | Livrable | Critère de sortie |
|---|---|---|---|
| 0 | **Preuve de faisabilité sur la box** | Appli « hello » + lecture d'un MP4 H.264, d'un HLS et d'un MKV par URL ; test d'XHR HTTPS vers `v3-cinemeta.strem.io` ; relevé de la version Qt/ES supportée | Les 4 tests passent sur la Revolution |
| 1 | Squelette du projet | `manifest.json`, `.fbxproject`, structure `qml/`, `js/core/`, CI de lint (`qmllint`) | Lancement depuis Qt Creator |
| 2 | Mini-core addons | Client manifest/catalog/meta/stream + addons par défaut (Cinemeta, OpenSubtitles) | Tests unitaires JS sur des réponses enregistrées |
| 3 | Interface de navigation | Accueil (rangées de catalogues), Découvrir (filtres), Fiche film/série (saisons, épisodes), Recherche | Navigation fluide à la télécommande |
| 4 | Lecture | Choix du flux, lecteur, pistes audio/sous-titres, reprise de position | Lecture d'un flux HTTP direct de bout en bout |
| 5 | Serveur de streaming (PC Windows) | Réglage de l'adresse `http://<IP-du-PC>:11470`, `/hlsv2/probe`, transcodage, torrents, sous-titres `/subtitles.vtt` | Lecture d'un torrent x265 transcodé |
| 6 | Compte Stremio | Liaison par code (`link.stremio.com`), synchro addons et bibliothèque, « Continuer à regarder » | Bibliothèque identique au compte sur PC |
| 7 | Gestion des addons | Installer un addon par URL (saisie ou QR depuis le téléphone), ordre, suppression | Addon tiers utilisable |
| 8 | Optimisation et robustesse | Cache d'images, pagination, gestion d'erreurs, mémoire | Pas de plantage après 2 h d'usage |
| 9 | Installation durable | Appli disponible sur la box sans Qt Creator (mode dév ou bêta privée FreeFactory) | Lancement depuis le menu du Player |

## 6. Risques principaux

1. **Validation FreeStore et aspect juridique** (élevé). Free peut refuser une appli qui facilite l'accès à des torrents. Parade : livrer un client d'addons neutre (aucun addon de torrent préinstallé, uniquement Cinemeta et OpenSubtitles), et prévoir une diffusion hors store en mode développeur si refus.
2. **Marque « Stremio »** (moyen). Le nom et le logo appartiennent à Stremio. Parade : nom propre (« client compatible Stremio ») ou demande d'accord à l'équipe Stremio.
3. **Codecs** (élevé). Sans HEVC, la majorité des flux récents exige le transcodage, donc un serveur sur le réseau local assez puissant (un Raspberry Pi peut être juste pour du 1080p x265 → H.264 **[à vérifier]**).
4. **Runtime QML ancien ou limité** (moyen). Pas d'ES6, mémoire faible, modules manquants. Parade : étape 0 avant tout développement, code JS en ES5 par défaut.
5. **Évolution de l'API Stremio** (moyen). `api.strem.io` n'est pas une API publique documentée ; la suivre via le code de `stremio-core`.
6. **Licences** (faible). `stremio-core` et l'addon SDK sont MIT ; `stremio-web` est GPL-2.0 : ne pas copier de code de `stremio-web` dans une appli fermée, ou publier notre appli en GPL.
7. **Fin de vie de la Revolution** (moyen). Box de 2010, firmware et SDK peu mis à jour depuis 2018. Le même code QML devrait tourner sur les Players plus récents de Free (Pop, Ultra) **[à vérifier]**, ce qui élargit l'audience.

## 7. Décisions prises (19 octobre 2026)

- **Diffusion : usage personnel en mode développeur.** Pas de soumission au FreeStore pour l'instant, donc les risques 1 et 2 (validation Free, marque) ne bloquent plus. L'étape 9 devient « installation durable sur la box » : vérifier si une appli lancée en mode développeur reste installée, sinon utiliser une bêta privée FreeFactory dont Rod est le seul testeur **[à vérifier]**.
- **Serveur de streaming : PC Windows sur le même réseau.** Le plus simple est Stremio Desktop pour Windows ou `stremio-service` (icône dans la barre des tâches), qui démarrent le serveur de streaming sur le port `11470`. L'appli QML l'appelle sur `http://<IP-du-PC>:11470`. À prévoir : IP fixe ou réservation DHCP du PC dans Freebox OS, et autorisation du port 11470 dans le pare-feu Windows (profil « réseau privé »). Le processeur d'un PC transcode sans peine du 1080p x265 vers H.264, ce qui règle en grande partie le risque 3. Le PC doit être allumé pour lire des torrents ; les flux HTTP directs H.264 restent lisibles sans lui.
- **Licence : MIT.** Le code dont on va transposer la logique est sous MIT (`stremio-core`, `stremio-video`, `stremio-addon-sdk`) et les exemples Freebox sont dans le domaine public, donc MIT n'impose aucune contrainte nouvelle et reste compatible avec tout projet qui voudrait reprendre le nôtre, y compris en GPL. En contrepartie, on ne copie **aucun code** de `stremio-web` ni de `stremio-shell` (GPL) : ils servent seulement de référence d'ergonomie. Quand une fonction est transposée depuis un dépôt MIT de Stremio, on garde la mention de copyright de Smart Code OOD dans le fichier concerné et dans `NOTICE.md`.

## Sources

- Organisation Stremio : https://github.com/stremio (`stremio-core`, `stremio-web`, `stremio-video`, `stremio-shell`, `stremio-addon-sdk`)
- SDK Freebox : https://dev.freebox.fr/sdk/player.html, https://github.com/fbx/libfbxqml, https://github.com/fbx/qmlapps_examples, https://github.com/fbx/freebox-qtcreator-plugin, https://github.com/fbx/freebox-dev-utils
- Formats supportés : https://www.universfreebox.com/article/13461/Freebox-Revolution-Quels-sont-les-formats-audios-et-videos-supportes/amp
- Annonce du SDK QML : https://next.ink/22240/88991-freebox-player-free-lance-sdk-applicatif-base-sur-qml/
- Retour d'expérience développeur : https://www.universfreebox.com/?p=44290
