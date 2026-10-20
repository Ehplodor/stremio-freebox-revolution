#!/usr/bin/env python3
"""Prechargement des videos par le PC (cache disque), pour des lectures sans saccades.

Au lancement d'une lecture, l'appli demande a l'agent de telecharger la source le plus vite
possible, en avance sur la lecture. Le serveur Stremio (conversion) ou le Player (lecture directe)
lisent ensuite la video depuis l'agent : les donnees deja recues viennent du disque, les suivantes
sont envoyees des leur arrivee. Une demande loin devant la partie prechargee (saut dans la video)
est relayee directement vers la source.

Le cache est dans %APPDATA%/stremio-fbx/cache, plafonne (15 Go par defaut) : les fichiers les plus
anciens de CE dossier sont supprimes quand la place manque, et ceux de plus de 24 h au demarrage.
"""

import hashlib
import os
import shutil
import threading
import time
import urllib.error
import urllib.request

CHUNK = 256 * 1024
UA = {"User-Agent": "Mozilla/5.0 (stremio-fbx prefetch)"}
FAR_AHEAD = 48 * 1024 * 1024      # au-dela de l'avance prechargee : relais direct (saut)
MAX_ACTIVE = 2                    # lecture en cours + episode suivant
MIN_FREE = 2 * 1024 ** 3          # garder au moins 2 Go libres sur le disque
REBASE_AFTER = 8 * 1024 * 1024    # lecture suivie hors de la partie prechargee : le prechargement la suit
IDLE_STOP = 5 * 60                # plus aucune demande de l'appli (lecture quittee) : arret


class Prefetch:
    def __init__(self, url, folder, start_fraction=0.0, max_bytes=0):
        self.url = url
        self.id = Prefetch.make_id(url)
        self.path = os.path.join(folder, self.id + ".part")
        self.start_fraction = max(0.0, min(0.98, start_fraction))
        self.max_bytes = max_bytes        # 0 : tout le fichier ; sinon arret apres max_bytes
        self.total = 0
        self.base = 0                     # debut de la partie prechargee (reprise en cours de film)
        self.end = 0                      # fin (exclue) de la partie prechargee contigue
        self.rate = 0.0                   # debit lisse (octets/s)
        self.done = False
        self.error = ""
        self.cancelled = False
        self.ranges = True                # la source accepte les requetes partielles
        self.rebase_to = None             # nouvelle position demandee (saut du lecteur)
        self.last_access = time.time()
        self.cond = threading.Condition()
        self.thread = threading.Thread(target=self._run, daemon=True)

    @staticmethod
    def make_id(url):
        return hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]

    # ----- telechargement -----

    def _open(self, start):
        headers = dict(UA)
        headers["Range"] = "bytes=%d-" % start
        return urllib.request.urlopen(urllib.request.Request(self.url, headers=headers), timeout=30)

    def _learn_total(self):
        """Taille totale (Content-Range ou Content-Length) en demandant le premier octet."""
        headers = dict(UA)
        headers["Range"] = "bytes=0-0"
        with urllib.request.urlopen(urllib.request.Request(self.url, headers=headers), timeout=30) as rsp:
            cr = rsp.headers.get("Content-Range", "")
            if "/" in cr and cr.rsplit("/", 1)[1].isdigit():
                return int(cr.rsplit("/", 1)[1]), True
            return int(rsp.headers.get("Content-Length") or 0), False

    def rebase(self, pos):
        """Le lecteur a saute hors de la partie prechargee et lit la suite : le prechargement
        repart de cette position (la partie precedente n'est plus suivie)."""
        with self.cond:
            if not self.ranges or self.error or self.cancelled or not self.total:
                return False
            if self.base <= pos <= self.end + FAR_AHEAD:
                return True
            self.rebase_to = pos // CHUNK * CHUNK
            self.done = False
            self.cond.notify_all()
            if not self.thread.is_alive():
                self.thread = threading.Thread(target=self._run, args=(True,), daemon=True)
                self.thread.start()
        return True

    def _run(self, resumed=False):
        try:
            if not resumed:
                self._prepare()
            with open(self.path, "r+b" if os.path.exists(self.path) else "w+b") as f:
                while True:
                    self._download(f)
                    with self.cond:
                        # Saut demande pendant la fin du telechargement : on repart.
                        if self.rebase_to is None or self.cancelled:
                            self.done = bool(self.total) and self.end >= self.total
                            self.cond.notify_all()
                            return
        except Exception as e:  # noqa: BLE001 - erreur rapportee a l'appli
            with self.cond:
                self.error = str(e)[:200]
                self.cond.notify_all()

    def _prepare(self):
        total, ranges = self._learn_total()
        with self.cond:
            self.total = total
            self.ranges = ranges
            # Reprise en cours de film : on commence a la position de lecture (la source
            # doit accepter les requetes partielles).
            if ranges and total and self.start_fraction > 0:
                self.base = self.end = int(total * self.start_fraction) // CHUNK * CHUNK
            self.cond.notify_all()
        free = shutil.disk_usage(os.path.dirname(self.path)).free
        if total and total - self.base > free - MIN_FREE and not self.max_bytes:
            raise OSError("espace disque insuffisant pour precharger (%d Go libres)" % (free // 1024 ** 3))
        if os.path.exists(self.path) and self.base == 0:
            # Meme video deja commencee (prechargement interrompu) : on reprend ou il en etait.
            kept = os.path.getsize(self.path) // CHUNK * CHUNK
            with self.cond:
                self.end = min(kept, total) if total else 0

    def _download(self, f):
        tries = 0
        while not self.cancelled:
            with self.cond:
                if self.rebase_to is not None:
                    self.base = self.end = self.rebase_to
                    self.rebase_to = None
                    self.cond.notify_all()
            if self.total and self.end >= self.total:
                return
            if self.max_bytes and self.end - self.base >= self.max_bytes:
                return
            try:
                with self._open(self.end) as rsp:
                    if rsp.status == 200 and self.end > 0:
                        raise OSError("la source n'accepte pas les reprises")
                    tries = 0
                    window_start, window_bytes = time.time(), 0
                    while not self.cancelled and self.rebase_to is None:
                        if time.time() - self.last_access > IDLE_STOP:
                            self.cancelled = True     # lecture abandonnee : on garde la partie recue
                            break
                        chunk = rsp.read(CHUNK)
                        if not chunk:
                            break
                        f.seek(self.end)
                        f.write(chunk)
                        f.flush()
                        window_bytes += len(chunk)
                        elapsed = time.time() - window_start
                        with self.cond:
                            self.end += len(chunk)
                            if elapsed >= 1.0:
                                inst = window_bytes / elapsed
                                self.rate = inst if not self.rate else 0.7 * self.rate + 0.3 * inst
                                window_start, window_bytes = time.time(), 0
                            self.cond.notify_all()
                        if self.max_bytes and self.end - self.base >= self.max_bytes:
                            break
                    if not self.total:
                        with self.cond:
                            self.total = self.end
            except (urllib.error.URLError, OSError, ConnectionError) as e:
                if "reprises" in str(e):
                    raise
                tries += 1
                if tries > 6:
                    raise
                time.sleep(min(30, 2 ** tries))

    # ----- lecture -----

    def status(self):
        self.last_access = time.time()    # l'appli suit encore ce prechargement
        with self.cond:
            return {"id": self.id, "total": self.total, "base": self.base, "end": self.end,
                    "rateBps": round(self.rate), "done": self.done, "error": self.error,
                    "partial": bool(self.max_bytes)}

    def wait_total(self, timeout=25):
        with self.cond:
            self.cond.wait_for(lambda: self.total or self.error, timeout=timeout)
            return self.total

    def read_into(self, out, start, end):
        """Ecrit [start, end] dans out ; attend les donnees pas encore telechargees.
        Renvoie la position atteinte (end + 1 si tout a ete envoye)."""
        self.last_access = time.time()
        pos = start
        f = None
        try:
            while pos <= end:
                with self.cond:
                    self.cond.wait_for(lambda: self.end > pos or self.error or self.cancelled
                                       or (self.max_bytes and self.end - self.base >= self.max_bytes
                                           and not self.thread.is_alive()), timeout=60)
                    available = self.end
                    # pos < base : partie plus suivie (saut du lecteur) -> relais direct par l'appelant
                    if self.error or self.cancelled or available <= pos or pos < self.base:
                        return pos
                if f is None:
                    try:
                        f = open(self.path, "rb")     # cree par le telechargement avant ses premieres donnees
                    except OSError:
                        return pos                    # fichier efface (nettoyage) : relais direct
                f.seek(pos)
                data = f.read(min(CHUNK, available - pos, end - pos + 1))
                if not data:
                    return pos
                out.write(data)
                pos += len(data)
                self.last_access = time.time()
            return pos
        finally:
            if f is not None:
                f.close()


class Manager:
    def __init__(self, folder):
        self.folder = folder
        self.items = {}
        self.lock = threading.Lock()
        os.makedirs(folder, exist_ok=True)
        self.cleanup(max_age=24 * 3600)

    def start(self, url, start_fraction=0.0, max_bytes=0, max_cache_gb=15):
        with self.lock:
            pid = Prefetch.make_id(url)
            item = self.items.get(pid)
            if item and not item.error and not item.cancelled:
                item.last_access = time.time()
                # Episode suivant precharge partiellement, maintenant lu : on va jusqu'au bout.
                if item.max_bytes and not max_bytes:
                    item.max_bytes = 0
                    if not item.thread.is_alive() and not item.done:
                        item = self._spawn(url, item.start_fraction, 0, pid)
                return item
            active = [i for i in self.items.values() if i.thread.is_alive() and not i.cancelled]
            for old in sorted(active, key=lambda i: i.last_access)[:max(0, len(active) - MAX_ACTIVE + 1)]:
                old.cancelled = True
            self.cleanup(max_bytes=max_cache_gb * 1024 ** 3)
            return self._spawn(url, start_fraction, max_bytes, pid)

    def _spawn(self, url, start_fraction, max_bytes, pid):
        old = self.items.get(pid)
        if old:
            old.cancelled = True
        item = Prefetch(url, self.folder, start_fraction, max_bytes)
        # Le fichier existant ne vaut que pour la meme partie : on repart de zero sinon.
        if os.path.exists(item.path) and (not old or old.base != 0 or start_fraction > 0):
            try:
                os.remove(item.path)
            except OSError:
                pass
        self.items[pid] = item
        item.thread.start()
        return item

    def get(self, pid):
        return self.items.get(pid)

    def live_mbps(self):
        """Debit Internet observe en ce moment par les prechargements actifs (0 si aucun)."""
        rates = [i.rate for i in self.items.values() if i.thread.is_alive() and i.rate > 0]
        return round(sum(rates) * 8 / 1e6, 1) if rates else 0.0

    def cleanup(self, max_bytes=None, max_age=None):
        """Supprime des fichiers de CE cache : trop vieux, ou les plus anciens si trop gros."""
        files = []
        for name in os.listdir(self.folder):
            if not name.endswith(".part"):
                continue
            path = os.path.join(self.folder, name)
            pid = name[:-5]
            item = self.items.get(pid)
            # En cours de telechargement, ou lu recemment (film en cours, deja entierement recu).
            busy = bool(item) and (item.thread.is_alive() or time.time() - item.last_access < 600)
            try:
                st = os.stat(path)
            except OSError:
                continue
            files.append((st.st_mtime, st.st_size, path, busy))
        now = time.time()
        if max_age:
            for mtime, _, path, busy in files:
                if not busy and now - mtime > max_age:
                    _remove(path)
        if max_bytes:
            files = [f for f in files if os.path.exists(f[2])]
            used = sum(f[1] for f in files)
            for mtime, size, path, busy in sorted(files):
                if used <= max_bytes:
                    break
                if not busy:
                    _remove(path)
                    used -= size


def _remove(path):
    try:
        os.remove(path)
    except OSError:
        pass
