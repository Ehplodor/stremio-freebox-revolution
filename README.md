# stremio-freebox-revolution

Client compatible Stremio pour le **Freebox Player Revolution**, écrit en QML/JavaScript
avec le SDK Freebox. Usage personnel, en mode développeur.

- Navigation dans les catalogues des addons Stremio, fiches films et séries, choix du flux.
- Lecture avec le lecteur du Player ; torrents et transcodage H.264 assurés par le
  serveur de streaming Stremio qui tourne sur un PC Windows du même réseau (port 11470).
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
| `bootstrap/` | Lanceur installe sur le Player (FreeStore) : trouve le PC et charge l'appli |
| `app/` | L'appli : accueil, recherche, reglages, fiche, lecteur (`qml/`) et mini-core JavaScript (`js/core/`) |
| `tools/` | `make_freestore_package.py`, `fbx_qml_run.py`, `test_addon.py`, `make_test_media.sh` |
| `tests/` | Tests du mini-core : `node --test tests/*.test.js` |

Résultats des tests sur la box : [docs/ETAPE0-RESULTATS.md](docs/ETAPE0-RESULTATS.md).

Le plan détaillé (architecture, contraintes de la box, étapes, risques) est dans
[docs/PLAN.md](docs/PLAN.md).

Projet non affilié à Stremio ni à Free. Licence MIT, voir [LICENSE](LICENSE) et
[NOTICE.md](NOTICE.md).
