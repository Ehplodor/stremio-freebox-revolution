# Plan de portage V2 : « Stremio Revolution »

_20 octobre 2026. Point de départ pour une nouvelle conversation. S'appuie sur la V1 (branche
`feasibility/step0-qml-test`, `docs/PLAN.md`, `docs/ETAPE0-RESULTATS.md`, `docs/INSTALLATION.md`) et sur
des recherches complémentaires faites le même jour (sources en fin de document). Les points
**[à vérifier]** n'ont pas encore été confirmés sur la box._

## 1. Objectif

Passer d'un « client Stremio qui marche » (V1) à **l'équivalent de Stremio sur la Freebox Player
Revolution** : mêmes écrans et fonctions que Stremio Desktop/Web, synchronisés avec le compte Stremio
dans les deux sens, installable depuis le FreeStore et **utilisable sans PC** pour tout ce que la box sait
faire seule, le PC restant un accélérateur (conversion HEVC, préchargement, torrents).

Ce qui reste hors d'atteinte, quoi qu'on fasse : décoder du HEVC/AV1/4K/HDR sur la box (matériel de
2010), exécuter du code natif ou WebAssembly (QML/JavaScript seulement).

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
   `getNotification`. Format exact de `LibraryItem` et de son `state` relevé (voir §6.2).
5. **Installation hors FreeStore impossible** sur le firmware actuel (API développeur limitée à
   `debug_qml_app`, aucun format reconnu depuis l'explorateur). La bêta privée FreeFactory est la voie.

## 4. Parité fonctionnelle visée

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

## 5. Architecture V2

### 5.1 Choix de distribution (décision à prendre en premier)

| Option | Principe | Pour | Contre |
|---|---|---|---|
| A. Lanceur seul (V1) | Le paquet FreeStore charge l'appli depuis le PC | Mises à jour instantanées, aucune revalidation | PC obligatoire même pour naviguer |
| **B. Appli embarquée (recommandée)** | Toute l'appli dans le paquet ; le PC est détecté et utilisé s'il est là | Fonctionne sans PC, démarrage plus rapide, vraie appli | Chaque version passe par FreeFactory (délai de validation) |
| C. Hybride | B + un « canal développeur » : si l'agent du PC propose une version plus récente, l'appli peut la charger | Développement rapide, utilisateurs stables | Deux chemins de chargement à tester |

Recommandation : **C**, avec B comme comportement par défaut. Le code reste unique (mêmes fichiers QML/JS),
seul le point de chargement change.

### 5.2 Modes de lecture

| Mode | Disponible | Couvre |
|---|---|---|
| Direct | Toujours | Liens HTTP H.264 (débrideurs, addons HTTP) |
| Freebox Server **[à vérifier]** | Sans PC, appli autorisée sur la Server | Torrents H.264 via le gestionnaire de téléchargements et `preview_url` |
| PC | Agent détecté | Tout : conversion HEVC/10 bits/AV1, torrents par le serveur Stremio, préchargement, piste audio, sous-titres intégrés |

Le choix du mode se fait par source, comme aujourd'hui l'évaluation des capacités (`sorting.assess`).
Une source non lisible dans les modes disponibles est masquée ou marquée, avec une raison claire.

### 5.3 Découpage du code

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
  js/platform/    accès aux API de la box (Settings, urlOpen, réseau), isolé pour les tests
companion/        agent du PC (existant), versionné avec l'appli
bootstrap/        lanceur (option A/C)
```

Règle : la logique va dans `js/core` (testable sous Node), les écrans QML ne font qu'afficher et
transmettre les touches.

## 6. Mini-core V2 : points techniques

### 6.1 Synchronisation de la bibliothèque (comme stremio-core)

1. `datastoreMeta` (collection `libraryItem`) : liste `[id, _mtime]` du compte.
2. Comparer avec le cache local (dans `Settings`, compressé) : télécharger (`datastoreGet` avec `ids`) ce
   qui est plus récent côté compte, envoyer (`datastorePut` avec `changes`) ce qui est plus récent localement.
3. Pendant la lecture : mise à jour locale toutes les 30 s (`timeOffset`, `timeWatched`, `duration`,
   `video_id`, `lastWatched`), envoi groupé toutes les 2 min et à l'arrêt.
4. Hors ligne : file d'envoi persistée, rejouée au retour du réseau.

### 6.2 Format `LibraryItem` (à respecter à l'octet près)

`_id`, `name`, `type`, `poster`, `posterShape`, `removed`, `temp`, `_ctime`, `_mtime`, `behaviorHints`,
`state` : `lastWatched`, `timeWatched`, `timeOffset`, `overallTimeWatched`, `timesWatched`,
`flaggedWatched`, `duration` (ms), `video_id` (nom tel quel), `watched` (bitfield sérialisé), `noNotif`.
Règles utiles : « Continuer à regarder » = `type != other`, `(!removed || temp)`, `timeOffset > 0` ;
un titre ouvert sans être ajouté est créé avec `removed = temp = true` ; passage à l'épisode suivant =
`video_id` changé, `timeWatched` reporté dans `overallTimeWatched`, `timeOffset = 1`.

### 6.3 Autres

- Réglages du compte : ne synchroniser que les champs compris par la V2, sans écraser les autres
  (lire `getUser`, fusionner, `saveUser`).
- Addons : l'ordre de `addonCollectionSet` est l'ordre d'affichage dans Stremio ; ne jamais retirer les
  addons « protégés » (Cinemeta, local).
- Stockage sur la box : `Settings` uniquement (pas de `LocalStorage`) ; prévoir une limite de taille
  **[à vérifier]** et un cache compressé (JSON minimal) pour la bibliothèque.

## 7. Interface (télécommande d'abord)

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

## 8. Agent du PC V2

- Paquet Windows sans Python à installer (exécutable autonome), icône dans la barre des tâches,
  démarrage avec Windows, mise à jour par GitHub Releases.
- Variante Docker (NAS, Raspberry Pi) avec le serveur de streaming Stremio officiel.
- API inchangée pour l'appli (`/fbx/api/status`, `/fbx/prefetch`, relais `hlsv2`), versionnée
  (l'appli vérifie la compatibilité au démarrage).

## 9. Jalons

| # | Jalon | Contenu | Critère de sortie |
|---|---|---|---|
| V2.0 | Fondations | Décision A/B/C ; structure §5.3 ; capacités du manifest (`net_lan`, `net_wan`, `net_gw`, `gw_downloader`) ; accents ; tests de rendu des écrans | Bêta installée qui démarre sans PC (catalogues, fiches) |
| V2.1 | **Test du mode Freebox Server** | Autorisation depuis le Player, ajout d'un magnet, lecture de la `preview_url` d'un torrent H.264 ; mesure du débit et des sauts | Décision : mode sans PC pour les torrents oui/non |
| V2.2 | Bibliothèque synchronisée | `library.js`, `watched.js`, progression écrite dans le compte, vu/non vu, ajouter/retirer | Une reprise commencée sur la box apparaît dans Stremio sur le PC, et inversement |
| V2.3 | Découvrir + Bibliothèque + Recherche | Écrans complets, filtres, pagination | Parité avec Stremio Web sur ces écrans |
| V2.4 | Addons | Liste, installation par URL et catalogue, désinstallation, ordre, configuration par QR | Un addon installé sur la box apparaît dans Stremio PC |
| V2.5 | Calendrier + notifications | Épisodes à venir, pastille de nouveautés | Nouvel épisode signalé le jour de sa sortie |
| V2.6 | Lecteur | Synchro de progression, « vu » à 90 %, hash OpenSubtitles, mode Freebox Server intégré | Lecture longue (2 h) sans fuite mémoire |
| V2.7 | Agent PC packagé | Exécutable Windows, Docker, mise à jour | Installation sur un PC vierge en 5 min |
| V2.8 | Publication | Visuels, textes, bêta élargie, éventuellement version publique | Validation Free |

Ordre conseillé : V2.0 puis V2.1 en premier (le résultat de V2.1 change l'architecture de lecture),
ensuite V2.2 (c'est ce qui rend l'appli « Stremio » au quotidien).

## 10. Risques et questions ouvertes

| Risque | Niveau | Parade |
|---|---|---|
| Validation FreeStore d'une appli complète (torrents, addons tiers) | Élevé | Aucun addon de sources préinstallé, description neutre, bêta privée en repli |
| Marque « Stremio » dans le nom | Moyen | Garder « Revo Stream » comme nom public, « compatible Stremio » dans la description ; demander l'accord de Stremio avant tout nom « Stremio Revolution » public |
| `preview_url` trop lente ou sans saut possible | Moyen | Le mode PC reste la référence |
| Taille de `Settings` limitée | Moyen | Cache minimal, bibliothèque rechargeable depuis le compte |
| API Stremio non documentée | Moyen | Suivre `stremio-core` ; tests de contrat sur des réponses enregistrées |
| Délai de validation de chaque version (option B) | Moyen | Option C (canal développeur via le PC) |
| Mémoire et processeur de la box | Moyen | Budget §7, mesures pendant les tests longs |

Questions à trancher avec Rod au démarrage :
1. Option de distribution A, B ou C (§5.1).
2. Périmètre public : rester en bêta privée (Rod + proches) ou viser une publication ?
3. Nom public définitif.
4. Accord pour une autorisation Freebox OS depuis le Player (test V2.1).

## 11. Méthode de travail (reprise de la V1)

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

## 12. Message de démarrage pour la nouvelle conversation

> Projet « Stremio Revolution » (V2). Dépôt `C:\Dev\stremio-freebox-revolution`, partir de la branche
> `feasibility/step0-qml-test`. Lis d'abord `docs/PLAN-V2-STREMIO-REVOLUTION.md`, puis `docs/PLAN.md`,
> `docs/ETAPE0-RESULTATS.md` et `docs/INSTALLATION.md`. Player à 192.168.0.42 (mode développeur), PC
> 192.168.0.16, Freebox Server 192.168.0.254. Préfixe FreeFactory `com.ehplodor`, appli « Revo Stream »
> en bêta privée. Commence par les questions du §10, puis les jalons V2.0 et V2.1. Respecte les règles du §11.

## Sources

- Manifest Freebox (capacités, points d'entrée, urlHandler) : https://dev.freebox.fr/sdk/manifest.html
- SDK QML et modules : https://dev.freebox.fr/sdk/player.html, https://dev.freebox.fr/sdk/libfbxqml/,
  https://github.com/fbx/libfbxqml (`fbx/web/freeboxos.js`, `fbx/web/freeboxos_auth.js`)
- API de téléchargement Freebox OS (magnet, `preview_url`, pièces) : https://dev.freebox.fr/sdk/os/download/
- Requêtes API Stremio : https://github.com/Stremio/stremio-core/blob/development/src/types/api/request.rs
- Bibliothèque Stremio : https://github.com/Stremio/stremio-core/blob/development/src/types/library/library_item.rs
- Modèles Stremio : https://github.com/Stremio/stremio-core/tree/development/src/models
- Écrans Stremio Web : https://github.com/Stremio/stremio-web/tree/development/src/routes
