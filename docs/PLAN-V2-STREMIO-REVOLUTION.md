# Plan de portage V2 : « Stremio Revolution »

_20 octobre 2026 (mise à jour : objectif « zéro PC », §4). Point de départ pour une nouvelle conversation. S'appuie sur la V1 (branche
`feasibility/step0-qml-test`, `docs/PLAN.md`, `docs/ETAPE0-RESULTATS.md`, `docs/INSTALLATION.md`) et sur
des recherches complémentaires faites le même jour (sources en fin de document). Les points
**[à vérifier]** n'ont pas encore été confirmés sur la box._

## 1. Objectif

Passer d'un « client Stremio qui marche » (V1) à **l'équivalent de Stremio sur la Freebox Player
Revolution** : mêmes écrans et fonctions que Stremio Desktop/Web, synchronisés avec le compte Stremio
dans les deux sens, installable depuis le FreeStore et **sans aucun PC** : la box seule, la Freebox
Server, le compte Stremio, les addons et le débrideur suffisent. L'agent du PC de la V1 devient facultatif
(confort), puis peut disparaître.

Limites matérielles de la box (Atom CE4100, 2010) qu'aucun logiciel ne lèvera : pas de décodage
HEVC/AV1/H.264 10 bits/4K/HDR, pas de code natif ni WebAssembly. Le §4 explique comment chaque besoin qui
en dépendait est couvert autrement.

## 2. Acquis de la V1 (validés sur la box)

| Domaine | Acquis |
|---|---|
| Runtime | Qt 5.15, JavaScript ES2016+, 1280×720 ; `fbx.application` (Settings persistants), `fbx.ui.*`, `fbx.web`, `fbx.async`, `fbx.crypto` ; pas de `QtQuick.Controls`, `LocalStorage` refusé, `fbx.media` réservé (VOD/TV) |
| Lecture | QtMultimedia `MediaPlayer` (moteur fbxmms) : MP4/MKV/HLS H.264, AAC/AC3/E-AC3/DTS. Pas de HEVC, pas de H.264 10 bits, pas de choix de piste audio natif |
| Addons | Client complet manifest/catalog/meta/stream/subtitles, agrégation, paramètres d'URL conservés |
| Compte | Liaison par code (`link.stremio.com`), addons du compte, bibliothèque et « Continuer à regarder » **en lecture seule** |
| Sources | Tri réglable et enregistré (priorité par addon, cache débrideur, résolution, langue…), filtre selon les capacités mesurées du PC et du réseau, source la plus proche pour l'épisode suivant |
| Lecteur | Pistes audio (via le PC), sous-titres addons + intégrés (par segments), décalage en direct, reprise, épisode suivant préparé, préchargement par le PC avec écran d'attente et pause automatique |
| PC | Lanceur unique, agent (relais Stremio, préchargement, capacités, PC éveillé), bouton téléphone, démarrage automatique |
| Distribution | **Bêta privée FreeFactory installée sur le Player** (20/10/2026). Leçon : le manifest doit déclarer `net_lan` pour joindre le PC (corrigé en 2.0.1) |
| Outils | Tests Node (44), contrôle QML, télécommande réseau scriptée, addon de test (films, série, sources bridées), **rendu des vrais écrans QML sur le PC** (PyQt5 + faux modules `fbx.application` et `QtMultimedia`), client Freebox OS (`tools/freebox_os.py`) |

## 3. Découvertes qui changent la donne pour la V2

1. **Le Player peut parler à la Freebox Server sans PC.** `fbx.web` contient `FreeboxOS` et
   `FreeboxOSAuth` (autorisation par la flèche de la Server, comme `tools/freebox_os.py`), avec les
   capacités de manifest `net_gw`, `gw_downloader`, `gw_explorer`.
2. **Torrents sans PC (piste à valider en premier).** Le gestionnaire de téléchargements de Freebox OS
   accepte les liens `magnet:` et les `.torrent` (`POST /downloads/add`). Chaque fichier d'un torrent a une
   `preview_url` **lisible pendant le téléchargement, sans authentification**, et la Server télécharge en
   priorité les pièces nécessaires à l'aperçu. Pour un torrent H.264, le Player pourrait donc lire en
   streaming sans PC. **[à vérifier]** : débit réel, saut dans la vidéo, comportement en fin de lecture
   (suppression de la tâche).
3. **Manifest** : capacités disponibles `net_lan`, `net_gw`, `net_wan`, `gw_*` (settings, contacts,
   calls, explorer, downloader, parental, pvr), `in_app_purchase`, `morality_18`. Points d'entrée `main`
   et `settings`, et **`urlHandler`** (regex d'URL ou de type MIME) : l'appli peut se proposer pour ouvrir
   des liens (par exemple des vidéos du disque de la Freebox) **[à vérifier]**.
4. **API Stremio en écriture** (d'après `stremio-core`) : `datastorePut` (bibliothèque et progression),
   `datastoreMeta` (ids + dates de modification, pour une synchro incrémentale), `addonCollectionSet`
   (installer, désinstaller, réordonner les addons), `saveUser` (réglages du profil), `logout`,
   `getNotification`. Format exact de `LibraryItem` et de son `state` relevé (voir §7.2).
5. **Installation hors FreeStore impossible** sur le firmware actuel (API développeur limitée à
   `debug_qml_app`, aucun format reconnu depuis l'explorateur). La bêta privée FreeFactory est la voie.

## 4. Se passer entièrement du PC

Chaque fonction que la V1 confiait au PC, et sa solution sans PC :

| Besoin (rôle du PC en V1) | Solution sans PC | Statut |
|---|---|---|
| **Interface chargée depuis le PC** | Toute l'appli dans le paquet FreeStore (option B, §6.1) | Sûr |
| **Vidéos HEVC/AV1/10 bits/4K/HDR** (conversion) | 1. **Choisir une source H.264** : mesuré le 20/10 sur 10 titres récents (5 films, 5 séries, Torrentio), **tous** ont des sources H.264 720p/1080p, dont des versions FR ou MULTi (1 à 17 par titre). Le tri V1 le fait déjà, il devient la règle : sans PC, HEVC/AV1/10 bits masqués par défaut. 2. **Conversion dans le nuage par le débrideur** quand aucune source H.264 n'existe : Real-Debrid `GET /streaming/transcode/{id}` (HLS « apple », MP4), TorBox API de streaming + transcodeur (offre Pro, doc Postman). Premiumize a arrêté le transcodage. AllDebrid : `streams` de `/link/unlock` = autres résolutions surtout pour les hébergeurs vidéo. 3. En dernier recours, serveur de streaming Stremio sur un petit serveur dans le nuage (VPS ou offre gratuite ARM) : pas de PC à la maison, mais à installer une fois. | 1 : mesuré. 2 : **[à vérifier]** (RD et TorBox ; AllDebrid sur un fichier de film avec l'accord de Rod). 3 : option |
| **Torrents** (serveur Stremio du PC) | 1. Addons avec débrideur : le débrideur transforme déjà le torrent en lien HTTP (cas de Rod). 2. **Gestionnaire de téléchargements de la Freebox Server** : `magnet:` ajouté par l'appli (capacité `gw_downloader`, autorisation par la flèche de la Server), lecture de la `preview_url` du fichier pendant le téléchargement (sans authentification, pièces d'aperçu prioritaires). | 1 : fait. 2 : **[à vérifier]** débit, sauts, fin de tâche |
| **Choix de la piste audio** (le PC réécrivait le HLS) | 1. **`fbx.media.VideoPlayer`** (module de Free, `fbx.os.mms`) : `audioList`, `currentAudioIndex`, `subtitleList`, `currentSubtitleIndex`, `subtitleUrl` (lu dans `libfbxqml`). Réservé aux applis « VOD/TV » : absent en mode développeur (vérifié le 20/10), **à demander à Free** pour l'appli FreeStore, et à tester dans l'appli installée. 2. Lecteur natif du Player via `App.urlOpen(url, type)` : essayé le 20/10 en mode développeur, aucune lecture déclenchée (une fenêtre de choix s'affiche peut-être à l'écran) **[à vérifier avec Rod devant la télé]**. 3. Repli : préférer les sources mono-langue ou MULTi dont la piste par défaut est la bonne (tri par langue). | 1 et 2 : **[à vérifier]**. 3 : faisable |
| **Sous-titres intégrés au MKV** (extraits par le PC) | 1. `fbx.media` (`subtitleList`) si l'accès est accordé. 2. Sous-titres des addons (OpenSubtitles) avec le **hash OpenSubtitles calculé sur la box** : taille + 64 Ko du début et de la fin, lus par `XMLHttpRequest` avec `Range` (somme 64 bits à écrire sans BigInt), pour des sous-titres calés sur la version exacte. 3. En dernier recours, piste texte (SRT/ASS) extraite en JavaScript en lisant l'index du MKV par requêtes `Range` : possible mais lourd. | 1 : **[à vérifier]**. 2 : faisable. 3 : lourd |
| **Conversion SRT → VTT, encodages** (`/subtitles.vtt` du serveur Stremio) | Analyseur SRT/ASS/VTT en JavaScript (le calque de sous-titres de la V1 l'affiche déjà), décodage Windows-1252 écrit à la main (pas de `TextDecoder`) à partir de `arraybuffer` | Faisable |
| **Préchargement anti-coupures** (cache disque du PC) | 1. Choisir des sources dont le débit tient dans la connexion de la box (évaluation V1 avec le débit Internet → box mesuré). 2. **Téléchargement préalable par la Freebox Server** (lien HTTP du débrideur ajouté au gestionnaire), puis lecture depuis son disque par un lien de partage Freebox OS (`share_link`) ou la `preview_url` pour les torrents : utile en Wi-Fi/CPL faible ou pour « regarder plus tard ». Pour un lien HTTP (pas de `preview_url`), lecture pendant que le fichier grossit par l'URL de fichier de Freebox OS (`/api/v4/dl/…`) ou par le serveur UPnP de la Server. 3. Le tampon du lecteur et la pause automatique de la V1 (calcul débit/avance de `buffer.js`) se réutilisent tels quels. | 1 et 3 : faits. 2 : **[à vérifier]** |
| **Affiches WebP** (converties par le PC) | `live.metahub.space` (JPEG) déjà utilisé ; sinon tester le décodage WebP de Qt sur la box, ou un service public de conversion (images.weserv.nl), réglable et désactivable ; sinon affiche générée (titre sur fond) | **[à vérifier]** |
| **Flux avec en-têtes** (`behaviorHints.proxyHeaders`, via le serveur Stremio) | Masqués sans PC (le lecteur ne sait pas ajouter d'en-têtes), ou proxy fourni par l'addon lui-même (MediaFlow…) | Faisable |
| **Bandes-annonces YouTube** | `App.urlOpen` vers l'appli YouTube du Player | **[à vérifier]** |
| **Mesure des capacités, PC éveillé, bouton téléphone** | Inutiles sans PC (seul le débit Internet de la box reste mesuré) | — |

Conséquences :
- **Distribution B obligatoire** (§6.1) : l'appli entière dans le paquet FreeStore.
- **Démarche auprès de Free** : demander l'accès à `fbx.media` pour l'appli (catégorie Multimédia & vidéo),
  argument : lecteur vidéo qui a besoin du choix des pistes audio et des sous-titres. C'est la pièce qui
  rend le lecteur aussi complet qu'avec le PC.
- L'agent du PC reste une option « confort » pour les rares titres sans source H.264 ni conversion par
  le débrideur, tant que le jalon V2.1 n'a pas tranché.

## 5. Parité fonctionnelle visée

Inventaire des fonctions de Stremio (modèles de `stremio-core`, écrans de `stremio-web`) :

| Fonction Stremio | Modèle core | V1 | V2 visée |
|---|---|---|---|
| Accueil (rangées des catalogues) | `catalogs_with_extra` | Fait | Rangées configurables, ordre et masquage, pagination horizontale |
| Continuer à regarder | `continue_watching_preview` | Lecture seule | Retirer un titre, synchro vers le compte |
| Découvrir (type, catalogue, genre, année, pagination) | `catalog_with_filters` | Absent | Écran complet avec filtres `extra` (genre, skip) |
| Recherche | `local_search` + catalogues `search` | Basique | Historique, résultats par type, recherche vocale non (pas de micro) |
| Fiche film/série | `meta_details` | Fait | Bande-annonce (YouTube via `App.urlOpen`), ajouter/retirer de la bibliothèque, vu/non vu par épisode et par saison, liens (IMDb…) en QR code |
| Bibliothèque | `library_with_filters`, `library_by_type` | Rangée | Écran avec filtre par type et tri (récent, nom, nombre de visionnages) |
| Calendrier (épisodes à venir des séries suivies) | `calendar` | Absent | Vue mois/semaine |
| Notifications (nouveaux épisodes) | `getNotification` + `should_pull_notifications` | Absent | Pastille sur l'accueil, liste |
| Addons installés / catalogue / détails / configuration | `installed_addons_with_filters`, `addon_details` | Absent | Installer par URL ou depuis un catalogue, désinstaller, ordre ; configuration par QR code vers la page `configure` sur le téléphone |
| Lecteur | `player` | Très complet | Progression écrite dans le compte, « vu » automatique à 90 %, hash OpenSubtitles (`/opensubHash`) pour des sous-titres mieux calés |
| Serveur de streaming | `streaming_server` | Via le PC | Mode sans PC (Freebox Server), réglages lisibles depuis la box |
| Profil et réglages | `saveUser`, `ctx` | Locaux | Synchro des réglages compatibles (langues, lecture suivante…) |
| Liaison / connexion / déconnexion | `link` | Liaison | + déconnexion (`logout`), changement de compte |
| TV en direct | `live_tv_*` | Absent | Hors périmètre V2 (à rediscuter) |
| Export de données | `data_export` | Absent | Hors périmètre |

## 6. Architecture V2

### 6.1 Choix de distribution

| Option | Principe | Pour | Contre |
|---|---|---|---|
| A. Lanceur seul (V1) | Le paquet FreeStore charge l'appli depuis le PC | Mises à jour instantanées, aucune revalidation | PC obligatoire même pour naviguer |
| **B. Appli embarquée (recommandée)** | Toute l'appli dans le paquet ; le PC est détecté et utilisé s'il est là | Fonctionne sans PC, démarrage plus rapide, vraie appli | Chaque version passe par FreeFactory (délai de validation) |
| C. Hybride | B + un « canal développeur » : si l'agent du PC propose une version plus récente, l'appli peut la charger | Développement rapide, utilisateurs stables | Deux chemins de chargement à tester |

Avec l'objectif « zéro PC », **B est imposée**. C n'a d'intérêt que pendant le développement (charger la
version en cours depuis le PC de développement sans repasser par FreeFactory).

### 6.2 Modes de lecture

| Mode | Disponible | Couvre |
|---|---|---|
| Direct | Toujours | Liens HTTP H.264 (débrideurs, addons HTTP) : le cas courant |
| Conversion par le débrideur **[à vérifier]** | Compte Real-Debrid ou TorBox Pro | Sources HEVC/AV1 sans équivalent H.264, en HLS H.264 |
| Freebox Server **[à vérifier]** | Appli autorisée sur la Server | Torrents H.264 (`preview_url`), téléchargement préalable |
| PC (facultatif) | Agent détecté | Tout, comme la V1 |

Le choix du mode se fait par source, comme aujourd'hui l'évaluation des capacités (`sorting.assess`).
Une source non lisible dans les modes disponibles est masquée ou marquée, avec une raison claire.

### 6.3 Découpage du code

```
app/
  qml/            écrans (un fichier par écran) + composants (affiche, rangée, liste, clavier, dialogue)
  js/core/        mini-core sans dépendance QML (testé sous Node)
    addons.js     transport et agrégation (existant)
    library.js    NOUVEAU : modèle LibraryItem, synchro datastoreMeta/Get/Put, file d'envoi hors ligne
    watched.js    NOUVEAU : WatchedBitField (transposé de stremio-core, MIT)
    calendar.js   NOUVEAU : épisodes à venir des séries de la bibliothèque
    notifications.js NOUVEAU
    addonsmgr.js  NOUVEAU : addonCollectionGet/Set, installation, ordre
    profile.js    NOUVEAU : réglages synchronisés (saveUser)
    playback.js, sorting.js, resume.js, buffer.js, subsegments.js, vtt.js (existants)
    freeboxos.js  NOUVEAU : autorisation et gestionnaire de téléchargements (mode sans PC)
    debrid.js     NOUVEAU : conversion par le débrideur (Real-Debrid, TorBox), si disponible
    subtitles.js  NOUVEAU : SRT/ASS/VTT, Windows-1252, hash OpenSubtitles (Range)
  js/platform/    accès aux API de la box (Settings, urlOpen, réseau), isolé pour les tests
companion/        agent du PC (existant), versionné avec l'appli
bootstrap/        lanceur (option A/C)
```

Règle : la logique va dans `js/core` (testable sous Node), les écrans QML ne font qu'afficher et
transmettre les touches.

## 7. Mini-core V2 : points techniques

### 7.1 Synchronisation de la bibliothèque (comme stremio-core)

1. `datastoreMeta` (collection `libraryItem`) : liste `[id, _mtime]` du compte.
2. Comparer avec le cache local (dans `Settings`, compressé) : télécharger (`datastoreGet` avec `ids`) ce
   qui est plus récent côté compte, envoyer (`datastorePut` avec `changes`) ce qui est plus récent localement.
3. Pendant la lecture : mise à jour locale toutes les 30 s (`timeOffset`, `timeWatched`, `duration`,
   `video_id`, `lastWatched`), envoi groupé toutes les 2 min et à l'arrêt.
4. Hors ligne : file d'envoi persistée, rejouée au retour du réseau.

### 7.2 Format `LibraryItem` (à respecter à l'octet près)

`_id`, `name`, `type`, `poster`, `posterShape`, `removed`, `temp`, `_ctime`, `_mtime`, `behaviorHints`,
`state` : `lastWatched`, `timeWatched`, `timeOffset`, `overallTimeWatched`, `timesWatched`,
`flaggedWatched`, `duration` (ms), `video_id` (nom tel quel), `watched` (bitfield sérialisé), `noNotif`.
Règles utiles : « Continuer à regarder » = `type != other`, `(!removed || temp)`, `timeOffset > 0` ;
un titre ouvert sans être ajouté est créé avec `removed = temp = true` ; passage à l'épisode suivant =
`video_id` changé, `timeWatched` reporté dans `overallTimeWatched`, `timeOffset = 1`.

### 7.3 Autres

- Réglages du compte : ne synchroniser que les champs compris par la V2, sans écraser les autres
  (lire `getUser`, fusionner, `saveUser`).
- Addons : l'ordre de `addonCollectionSet` est l'ordre d'affichage dans Stremio ; ne jamais retirer les
  addons « protégés » (Cinemeta, local).
- Stockage sur la box : `Settings` uniquement (pas de `LocalStorage`) ; prévoir une limite de taille
  **[à vérifier]** et un cache compressé (JSON minimal) pour la bibliothèque.

## 8. Interface (télécommande d'abord)

- Écrans : Accueil, Découvrir, Bibliothèque, Calendrier, Recherche, Fiche, Choix de la source, Lecteur,
  Addons, Réglages, Compte. Barre du haut à 6 onglets maximum.
- Composants à écrire une fois : affiche, rangée, grille paginée, liste de réglages, clavier à l'écran,
  dialogue de confirmation, QR code (déjà dans le compte), toast. `fbx.ui` à évaluer avant de réécrire
  (dialogues, menus) **[à vérifier]**.
- Budget de performance (Atom CE4100) : affiches à la taille affichée (`sourceSize`), listes
  virtualisées, pas d'effet graphique coûteux, rendu stable à 1280×720.
- Accents : la V1 affiche « Reglages », « Demarrer »… à corriger partout (police et encodage UTF-8
  validés sur la box).
- Vérification visuelle : le rendu sur PC (PyQt5) produit des captures de chaque écran ; à intégrer
  aux tests pour repérer les chevauchements (bug trouvé ainsi le 20/10).

## 9. Agent du PC (facultatif)

- Gardé tel quel tant que V2.1 n'a pas montré que tout passe sans lui ; plus d'investissement
  (pas d'exécutable Windows) sauf si un besoin résiduel apparaît.
- L'appli le détecte sans en dépendre : aucun écran ne doit attendre le PC.

## 10. Jalons

| # | Jalon | Contenu | Critère de sortie |
|---|---|---|---|
| V2.0 | Fondations autonomes | Appli entière dans le paquet (B) ; structure §6.3 ; manifest `net_lan`, `net_wan`, `net_gw`, `gw_downloader`, `gw_explorer` ; accents ; tests de rendu ; **sonde des modules** (`fbx.os.mms`, `fbx.media`) dans l'appli installée, résultat envoyé au journal | Bêta installée qui fonctionne PC éteint (catalogues, fiches, lecture directe H.264) |
| V2.1 | **Essais « zéro PC »** (avec Rod devant la télé) | `App.urlOpen` vers le lecteur natif ; `preview_url` d'un torrent H.264 ; lien de partage Freebox d'un fichier téléchargé ; conversion Real-Debrid/TorBox (comptes de test) et `streams` AllDebrid (accord de Rod) ; YouTube ; demande d'accès `fbx.media` envoyée à Free | Tableau du §4 sans **[à vérifier]** ; choix définitif des modes de lecture |
| V2.2 | Lecture sans PC | Tri « H.264 d'abord » sans PC, `subtitles.js` (SRT/ASS, Windows-1252, hash OpenSubtitles), modes retenus en V2.1, piste audio (fbx.media ou repli) | Les 10 titres de la mesure du 20/10 lisibles PC éteint, en français |
| V2.3 | Bibliothèque synchronisée | `library.js`, `watched.js`, progression écrite dans le compte, vu/non vu, ajouter/retirer | Une reprise commencée sur la box apparaît dans Stremio sur le PC, et inversement |
| V2.4 | Découvrir + Bibliothèque + Recherche | Écrans complets, filtres, pagination | Parité avec Stremio Web sur ces écrans |
| V2.5 | Addons | Liste, installation par URL et catalogue, désinstallation, ordre, configuration par QR | Un addon installé sur la box apparaît dans Stremio PC |
| V2.6 | Calendrier + notifications | Épisodes à venir, pastille de nouveautés | Nouvel épisode signalé le jour de sa sortie |
| V2.7 | Lecteur complet | Synchro de progression, « vu » à 90 %, préchargement par la Freebox Server si retenu | Lecture longue (2 h) sans fuite mémoire |
| V2.8 | Publication | Visuels, textes, bêta élargie, éventuellement version publique | Validation Free |

Ordre conseillé : V2.0, V2.1 (ils décident de l'architecture de lecture), V2.2 (le PC peut alors être
éteint), puis V2.3 (ce qui rend l'appli « Stremio » au quotidien).

## 11. Risques et questions ouvertes

| Risque | Niveau | Parade |
|---|---|---|
| Validation FreeStore d'une appli complète (torrents, addons tiers) | Élevé | Aucun addon de sources préinstallé, description neutre, bêta privée en repli |
| Marque « Stremio » dans le nom | Moyen | Garder « Revo Stream » comme nom public, « compatible Stremio » dans la description ; demander l'accord de Stremio avant tout nom « Stremio Revolution » public |
| `preview_url` trop lente ou sans saut possible | Moyen | Torrents via le débrideur (cas actuel de Rod) |
| Accès `fbx.media` refusé par Free | Moyen | Piste audio par choix de la source ; sous-titres externes avec hash |
| Conversion des débrideurs indisponible (Real-Debrid incertain, TorBox réservé au Pro) | Faible | Sources H.264 disponibles sur tous les titres mesurés ; serveur dans le nuage en option |
| Taille de `Settings` limitée | Moyen | Cache minimal, bibliothèque rechargeable depuis le compte |
| API Stremio non documentée | Moyen | Suivre `stremio-core` ; tests de contrat sur des réponses enregistrées |
| Délai de validation de chaque version (option B) | Moyen | Option C (canal développeur via le PC) |
| Mémoire et processeur de la box | Moyen | Budget §8, mesures pendant les tests longs |

Questions à trancher avec Rod au démarrage :
1. Garder l'agent du PC comme option pendant la transition, ou le retirer dès V2.2 ?
2. Périmètre public : rester en bêta privée (Rod + proches) ou viser une publication ?
3. Nom public définitif.
4. Accord pour une autorisation Freebox OS depuis le Player (test V2.1).
5. Accord pour un essai AllDebrid (`streams` d'un fichier de film) et choix d'un débrideur avec conversion
   si besoin (Real-Debrid, TorBox Pro).
6. Envoi de la demande d'accès `fbx.media` à Free (par Rod, depuis son compte FreeFactory).

## 12. Méthode de travail (reprise de la V1)

- Branche dédiée par jalon, jamais `main` ; commits « Ehplodor » avec la ligne Co-Authored-By.
- Licence MIT ; transposition depuis `stremio-core`/`stremio-video` (MIT) avec mention dans `NOTICE.md` ;
  **aucun code** de `stremio-web` ni `stremio-shell` (GPL).
- Rien d'installé ni de modifié dans Windows (pare-feu, réglages) sans accord ; réglages Stremio non
  modifiés (paramètres par requête).
- Aucune suppression : les fichiers obsolètes vont dans un dossier `_obsolete`.
- Télécommande réseau : code uniquement dans la variable d'environnement `FBX_REMOTE_CODE` d'un script
  hors dépôt, jamais dans le dépôt ni les messages. Clés et liens de débrideur jamais dans les journaux.
- Pas de lecture AllDebrid sans accord : l'addon de test couvre les essais.
- Vérification : tests Node, contrôle QML, rendu des écrans sur PC, puis essai sur la box à la
  télécommande réseau avant chaque envoi.

## 13. Message de démarrage pour la nouvelle conversation

> Projet « Stremio Revolution » (V2). Dépôt `C:\Dev\stremio-freebox-revolution`, partir de la branche
> `feasibility/step0-qml-test`. Lis d'abord `docs/PLAN-V2-STREMIO-REVOLUTION.md`, puis `docs/PLAN.md`,
> `docs/ETAPE0-RESULTATS.md` et `docs/INSTALLATION.md`. Player à 192.168.0.42 (mode développeur), PC
> 192.168.0.16, Freebox Server 192.168.0.254. Préfixe FreeFactory `com.ehplodor`, appli « Revo Stream »
> en bêta privée. Objectif : **aucun PC nécessaire** (§4). Commence par les questions du §11, puis les jalons
> V2.0 et V2.1. Respecte les règles du §12.

## Sources

- Mesure des sources H.264 (20/10/2026) : Torrentio public, 10 titres (Dune 2, Oppenheimer, Inception,
  Love of Your Life, Spider-Man Brand New Day, Breaking Bad, The Bear, Dark, Severance, Shogun)
- AllDebrid API v4 (`/link/unlock`, `/link/streaming`, `/link/delayed`) : https://docs.alldebrid.com/
- Real-Debrid (`/streaming/transcode/{id}`, `/streaming/mediaInfos/{id}`) : https://api.real-debrid.com/
- Premiumize (transcodage retiré) : https://www.premiumize.me/api
- TorBox (API de streaming et transcodeur, v8.1) : https://feedback.torbox.app/changelog/v81,
  https://www.postman.com/wamy-dev/torbox/folder/0y3rsik/stream
- `fbx.media` (`VideoPlayer`, pistes) : https://github.com/fbx/libfbxqml (`fbx/media/view.qml`)

- Manifest Freebox (capacités, points d'entrée, urlHandler) : https://dev.freebox.fr/sdk/manifest.html
- SDK QML et modules : https://dev.freebox.fr/sdk/player.html, https://dev.freebox.fr/sdk/libfbxqml/,
  https://github.com/fbx/libfbxqml (`fbx/web/freeboxos.js`, `fbx/web/freeboxos_auth.js`)
- API de téléchargement Freebox OS (magnet, `preview_url`, pièces) : https://dev.freebox.fr/sdk/os/download/
- Requêtes API Stremio : https://github.com/Stremio/stremio-core/blob/development/src/types/api/request.rs
- Bibliothèque Stremio : https://github.com/Stremio/stremio-core/blob/development/src/types/library/library_item.rs
- Modèles Stremio : https://github.com/Stremio/stremio-core/tree/development/src/models
- Écrans Stremio Web : https://github.com/Stremio/stremio-web/tree/development/src/routes
