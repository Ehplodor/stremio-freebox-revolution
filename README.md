# stremio-freebox-revolution

Client compatible Stremio pour le **Freebox Player Revolution**, écrit en QML/JavaScript
avec le SDK Freebox. Usage personnel, en mode développeur.

- Navigation dans les catalogues des addons Stremio, fiches films et séries, choix du flux.
- Lecture avec le lecteur du Player ; torrents et transcodage H.264 assurés par le
  serveur de streaming Stremio qui tourne sur un PC Windows du même réseau (port 11470).
- Synchronisation avec le compte Stremio (bibliothèque, progression).

## Organisation

| Dossier | Contenu |
|---|---|
| `app/` | L'appli QML : accueil (rangées de catalogues), fiche, choix du flux, lecteur avec sous-titres |
| `app/js/core/` | Mini-core JavaScript : protocole d'addons, choix lecture directe ou transcodage, sous-titres VTT |
| `companion/` | Service à lancer sur le PC (port 11480) : relais vers le serveur Stremio qui retire la piste de sous-titres des flux HLS (le lecteur du Player bloque dessus) et convertit les affiches WebP |
| `tools/` | `fbx_qml_run.py` (lance une appli sur le Player), `test_addon.py` (addon de test, port 8235), `make_test_media.sh` (vidéos de test) |
| `tests/` | Tests du mini-core : `node --test tests/*.test.js` |
| `apps/step0-test/` | Appli de test de faisabilité (étape 0) |

## Lancer depuis le PC

Avec Stremio Desktop ouvert (serveur sur le port 11470) et le Player en mode développeur :

```bash
python companion/companion.py
python tools/test_addon.py
python tools/fbx_qml_run.py app/manifest.json
```

L'adresse du PC est dans `app/js/config.js` (`PC`). `AUTOTEST` y lance un scénario
automatique (fiche, lecture, retour) utile pour tester sans télécommande ; le vider pour
naviguer à la main.

Résultats des tests sur la box : [docs/ETAPE0-RESULTATS.md](docs/ETAPE0-RESULTATS.md).

Le plan détaillé (architecture, contraintes de la box, étapes, risques) est dans
[docs/PLAN.md](docs/PLAN.md).

Projet non affilié à Stremio ni à Free. Licence MIT, voir [LICENSE](LICENSE) et
[NOTICE.md](NOTICE.md).
