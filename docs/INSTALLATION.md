# Installation et utilisation

## Sur le PC : un seul lanceur

Double-cliquer sur **`Lancer-Stremio-Freebox.bat`** (racine du depot). Il :

1. verifie Python, Pillow, le reseau Windows et le pare-feu (sans rien modifier : il dit quoi faire) ;
2. demarre **Stremio Desktop** s'il ne tourne pas et attend son serveur (port 11470) ;
3. demarre l'**agent du PC** (port 11480) : relais vers Stremio, affiches, sous-titres, fichiers de l'appli,
   identite du PC ;
4. cherche le **Player** en mode developpeur et y affiche l'appli.

La fenetre doit rester ouverte pendant le visionnage. Options :

| Option | Effet |
|---|---|
| `--nom "PC du salon"` | Nom du PC affiche sur la tele (enregistre) |
| `--player 192.168.0.42` | Adresse du Player si la recherche automatique echoue |
| `--sans-player` | Agent seul, sans afficher l'appli sur la tele |
| `--addon-test` | Sert aussi l'addon de videos de test |
| `--demarrage-auto oui` / `non` | Lancer ce lanceur a chaque ouverture de session Windows (raccourci dans le dossier Demarrage) |

L'identite du PC (nom et identifiant stable) est dans `%APPDATA%\stremio-fbx\agent.json` ; les journaux
de l'appli sur la tele dans `%APPDATA%\stremio-fbx\logs\`.

## Sur la tele : icone dans le menu principal

Le Player n'offre aucun moyen d'installer une appli de facon permanente depuis le PC : l'API du mode
developpeur (`/pub/devel`) ne connait que `debug_qml_app`, un lancement temporaire (verifie le
20 octobre 2026). Une icone dans le menu, a cote de Netflix, passe par le **FreeStore**, en beta privee :

1. Creer un compte developpeur sur **https://factory.free.fr** (FreeFactory) avec votre compte Free.
2. Sur le PC : `python tools/make_freestore_package.py` produit `dist/revo-stream-<version>.tar.gz`
   (meme format que le plugin Qt Creator de Free, memes verifications du manifest).
3. Dans FreeFactory : nouvelle application, envoyer le paquet, ajouter les visuels de `bootstrap/freestore/`
   (icones 80, 150 et 220 px, bannieres 300x90 et 736x152), publier en **beta** et vous ajouter comme
   beta-testeur.
4. L'appli « Revo Stream » apparait dans les applications du Player.

Ce qui est installe sur le Player est seulement le **lanceur** (`bootstrap/`). Il :

- retrouve le PC (adresse memorisee, sinon recherche sur le reseau local si l'adresse a change) et le
  reconnait par son identifiant ; s'il trouve plusieurs PC, il propose le choix ;
- charge l'appli depuis le PC : chaque mise a jour du depot est disponible sans rien reinstaller ;
- si le PC ne repond pas, affiche « Pret — en attente du PC » avec les instructions, et reessaie
  toutes les 10 s.

Points a verifier avec Free : delai et criteres de validation d'une beta privee, et si une appli qui
charge son interface depuis le reseau local est acceptee.

En attendant, le lanceur du PC affiche directement l'appli sur la tele (mode developpeur).

## Changement de PC ou de compte

- **Autre adresse du PC** (DHCP) : le lanceur du Player le retrouve par son identifiant.
- **Autre PC** : l'appli le signale (« Connecte a un autre PC : … ») et le memorise ; avec plusieurs PC
  allumes, le lanceur demande lequel utiliser.
- **Compte Stremio** : la session est verifiee a chaque demarrage ; si elle a expire, l'appli le dit et
  propose de relier le compte. Un autre compte est detecte et signale ; les positions de reprise sont
  propres a chaque compte.

## A la telecommande

| Ou | Touches |
|---|---|
| Partout | Retour : ecran precedent ; Haut depuis le haut d'un ecran : barre des onglets |
| Barre du haut | Gauche/Droite : Accueil, Recherche, Reglages ; OK : ouvrir |
| Fiche | **Lecture** (meilleure source, ou reprise) ; Sources ; Tri des sources (aussi touche Menu) |
| Lecteur | OK : pause ; Gauche -10 s ; Droite +30 s ; Haut ou Menu : audio et sous-titres |
| Fin d'un episode | Episode suivant automatique (OK : tout de suite ; Retour : annuler) |
| Recherche | Clavier a l'ecran ou chiffres de la telecommande ; Droite : resultats |
