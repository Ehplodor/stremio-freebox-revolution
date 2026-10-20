# stremio-freebox-revolution

Client compatible Stremio pour le **Freebox Player Revolution**, écrit en QML/JavaScript
avec le SDK Freebox. Appli « Revo Stream », installée depuis le FreeStore (bêta privée).

- Navigation dans les catalogues des addons Stremio, fiches films et séries, choix du flux.
- **Sans PC** : lecture directe des liens HTTP en H.264 (addons avec débrideur), les sources que la box
  ne sait pas lire sont masquées.
- **Avec un PC (facultatif)** : torrents et conversion en H.264 par le serveur de streaming Stremio
  d'un PC Windows du même réseau (port 11470), pistes audio, sous-titres intégrés.
- Synchronisation avec le compte Stremio (bibliothèque, progression).
- Tri des sources réglable (priorité par addon, cache débrideur, qualité, langue), sources trop lourdes
  pour le PC masquées, épisode suivant sur la source la plus proche.
- Préchargement par le PC avec écran d'attente intelligent et pause automatique : lecture sans coupure
  même sur une connexion lente.

## Demarrage rapide

1. Sur le PC : double-cliquer sur **`Lancer-Stremio-Freebox.bat`** (verifie tout, demarre Stremio et l'agent,
   affiche l'appli sur la tele).
2. Sur la tele : l'appli « Revo Stream » s'ouvre ; lier le compte Stremio depuis l'accueil.

Details, icone dans le menu du Player (FreeStore), changement de PC ou de compte, touches :
[docs/INSTALLATION.md](docs/INSTALLATION.md).

## Organisation

| Dossier | Contenu |
|---|---|
| `Lancer-Stremio-Freebox.bat`, `tools/launcher.py` | Lanceur unique du PC |
| `companion/` | Agent du PC (port 11480) : relais Stremio (HLS sans piste de sous-titres, piste audio choisie), prechargement (`prefetch.py`), mesure des capacites (`capacity.py`), affiches WebP, identite du PC, demarrage de Stremio, fichiers de l'appli |
| `app/` | L'appli, embarquee dans le paquet FreeStore : accueil, recherche, reglages, fiche, lecteur (`qml/`) et mini-core JavaScript (`js/core/`) |
| `bootstrap/` | Lanceur de la V1 (charge l'appli depuis le PC), garde pour le developpement |
| `tools/` | `make_freestore_package.py`, `fbx_qml_run.py` (`--sans-pc`), `render_screens.py` (captures des ecrans sur PC), `test_addon.py`, `make_test_media.sh` |
| `tests/` | Tests du mini-core : `node --test tests/*.test.js` ; faux modules de la box pour le rendu (`qml_stubs/`) |

Résultats des tests sur la box : [docs/ETAPE0-RESULTATS.md](docs/ETAPE0-RESULTATS.md).

Le plan détaillé (architecture, contraintes de la box, étapes, risques) est dans
[docs/PLAN.md](docs/PLAN.md), et celui de la V2 (« zéro PC ») dans
[docs/PLAN-V2-STREMIO-REVOLUTION.md](docs/PLAN-V2-STREMIO-REVOLUTION.md).

Projet non affilié à Stremio ni à Free. Licence MIT, voir [LICENSE](LICENSE) et
[NOTICE.md](NOTICE.md).
