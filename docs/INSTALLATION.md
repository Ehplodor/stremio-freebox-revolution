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
| `--addon-test` | Sert aussi l'addon de videos de test (films, une serie de 3 episodes, sources bridees qui simulent une connexion lente) |
| `--mesurer` / `--sans-mesure` | Refaire / sauter la mesure des capacites du PC (faite automatiquement une fois par semaine) |
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

## Lecture fluide

- **Capacites du PC** : le lanceur mesure une fois par semaine la vitesse de conversion (processeur, NVENC,
  AMF selon la machine) et le debit Internet. L'appli masque les sources trop lourdes pour ce PC et choisit
  l'encodeur le plus rapide pour chaque format (un vieux PC sans carte graphique reste utilisable).
- **Prechargement par le PC** (Reglages > Lecture, active par defaut) : l'agent telecharge la video en
  avance dans `%APPDATA%\stremio-fbx\cache` (15 Go au plus, fichiers de plus de 24 h supprimes ; 2 Go
  toujours laisses libres sur le disque). Avant la lecture, un ecran d'attente indique la progression et
  le temps restant : l'attente est calculee pour que la lecture ne rattrape jamais le telechargement
  (quelques secondes si la connexion est rapide). OK lance tout de suite. Si l'avance s'epuise quand meme,
  la lecture se met en pause d'elle-meme et reprend avec 30 s d'avance. La partie prechargee apparait en
  gris clair dans la barre de lecture ; apres un saut, le prechargement suit.
- **Episode suivant** : a 4 min de la fin, l'appli choisit la source la plus proche de celle en cours
  (meme addon, meme ligne de source, equipe, qualite, langue) et en precharge le debut des que l'episode
  en cours est entierement telecharge : l'enchainement est quasi immediat.
- **PC eveille** : tant que le Player utilise l'agent, le PC ne se met pas en veille automatique (demande
  temporaire a Windows, levee 3 min apres la derniere activite ; aucun reglage n'est modifie).
- Les sources des torrents (serveur Stremio) et celles du PC lui-meme ne sont pas prechargees : le serveur
  Stremio gere deja leur cache.

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
| Sous-titres decales | 4 : plus tot ; 6 : plus tard (pas de 0,25 s) ; 5 : remise a zero (aussi dans le menu Haut) |
| Ecran de prechargement | OK : lancer maintenant ; Retour : quitter |
| Fin d'un episode | Episode suivant automatique (OK : tout de suite ; Retour : annuler) |
| Recherche | Clavier a l'ecran ou chiffres de la telecommande ; Droite : resultats |
