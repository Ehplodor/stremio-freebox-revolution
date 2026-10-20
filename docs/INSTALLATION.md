# Installation et utilisation

## Sur le PC : un seul lanceur

Double-cliquer sur **`Lancer-Stremio-Freebox.bat`** (racine du depot). Il :

1. verifie Python, Pillow, le reseau Windows et le pare-feu (sans rien modifier : il dit quoi faire) ;
2. demarre **Stremio Desktop** s'il ne tourne pas et attend son serveur (port 11470) ;
3. demarre l'**agent du PC** (port 11480) : relais vers Stremio, affiches, sous-titres, fichiers de l'appli,
   identite du PC ;
4. cherche le **Player** en mode developpeur et y affiche l'appli.

La fenetre doit rester ouverte pendant le visionnage. Appli fermee sur la tele : touche Entree dans la
fenetre, ou depuis un telephone sur le meme Wi-Fi, la page **`http://<IP-du-PC>:11480/tele`** (adresse
affichee par le lanceur) et son bouton « Afficher sur la tele ». Astuce : l'ajouter a l'ecran d'accueil
du telephone. Options :

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
   (meme format que le plugin Qt Creator de Free, memes verifications du manifest). Depuis la 2.1.0, c'est
   **l'appli entiere** (`app/`) : elle fonctionne sans PC. L'ancien lanceur : `--source bootstrap`.
3. Dans FreeFactory : nouvelle application, envoyer le paquet, ajouter les visuels de `bootstrap/freestore/` (deja aux noms attendus : logo_80/150/220.png, mini_banner.jpg, big_banner.jpg, screenshot1-3.jpg, mini_screenshot1-3.jpg ; captures rendues depuis les vrais ecrans QML),
   publier en **beta** et vous ajouter comme beta-testeur.
4. L'appli « Revo Stream » apparait dans les applications du Player.

Depuis la 2.1.0, le paquet contient **toute l'appli** : elle demarre sans PC. Sans PC, elle lit en direct
les liens HTTP en H.264 (addons avec debrideur) et masque le reste (torrents, HEVC, 4K) avec la raison.
Le PC est facultatif (Reglages > PC) : s'il a deja ete utilise et qu'il repond, l'appli s'en sert pour
les torrents, la conversion, les pistes audio et le prechargement ; sinon elle continue sans lui.

Les versions 2.0.x installaient seulement le **lanceur** (`bootstrap/`), qui chargeait l'appli depuis le
PC ; il reste disponible pour le developpement (`--source bootstrap`).

Developpement : `python tools/fbx_qml_run.py app/manifest.json` affiche l'appli du depot sur la tele
(identifiant suffixe `.dev`, reglages separes de l'appli installee) ; `--sans-pc` simule une box seule.
`python tools/render_screens.py` capture les ecrans sur le PC et signale les textes qui se chevauchent.

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
