# Mentions tierces

Ce projet est sous licence MIT (voir `LICENSE`).

Une partie de la logique est transposée en JavaScript/QML à partir des projets
suivants, publiés sous licence MIT par Smart Code OOD :

- [stremio-core](https://github.com/Stremio/stremio-core)
- [stremio-video](https://github.com/Stremio/stremio-video)
- [stremio-addon-sdk](https://github.com/Stremio/stremio-addon-sdk)

Chaque fichier qui reprend du code de ces projets conserve leur mention de copyright :

- `app/js/core/playback.js` : logique de `stremio-video/src/withStreamingServer`
  (convertStream, createTorrent, buildProxyUrl, canPlayProbe), Copyright (c) 2018 Smart Code OOD.

- `app/js/core/lzstring.js` : décompression de [lz-string](https://github.com/pieroxy/lz-string)
  1.5.0 (configuration de l'addon TMDB), Copyright (c) 2013 pieroxy, licence MIT.

Aucun code de `stremio-web` ni de `stremio-shell` (GPL) n'est repris : ils
servent uniquement de référence d'ergonomie.

Les exemples Freebox (`fbx/qmlapps_examples`) et `fbx/freebox-dev-utils`
(dont `tools/fbx_qml_run.py` est une réécriture en Python 3) sont dans le domaine public.
La bibliothèque `libfbxqml` est fournie par le runtime du Freebox Player et
n'est pas incluse dans ce dépôt.

« Stremio » est une marque de Smart Code OOD. Ce projet n'est ni affilié ni
approuvé par Stremio ou par Free.
