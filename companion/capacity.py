#!/usr/bin/env python3
"""Mesure des capacites du PC pour la conversion video et le debit Internet.

L'appli du Player s'en sert pour ecarter les sources que ce PC ne pourrait pas convertir a temps
(ou que la connexion ne suivrait pas). Mesure faite une fois, gardee 7 jours dans
%APPDATA%/stremio-fbx/agent.json.

Conversion : on fait convertir par le serveur Stremio lui-meme (meme chemin que la lecture, avec
ses propres reglages ffmpeg) des videos de test 1080p realistes (image granuleuse, ~10 Mbit/s)
servies par l'agent, et on chronometre la fabrication des segments HLS.
Resultat : "facteur temps reel" (2.0 = deux fois plus vite que la lecture) et delai du 1er segment.
"""

import os
import random
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_AGE = 7 * 24 * 3600
CLIP_SECONDS = 20
UA = {"User-Agent": "Mozilla/5.0 (stremio-fbx capacity test)"}


def find_ffmpeg():
    for path in [os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "Stremio", "ffmpeg.exe"),
                 os.path.join(os.environ.get("ProgramFiles", ""), "Stremio", "ffmpeg.exe")]:
        if os.path.isfile(path):
            return path
    return "ffmpeg"


def make_clips(folder):
    """Videos de test 1080p (generees une fois) : HEVC 8 bits et H.264 10 bits, avec du grain
    pour approcher le cout de vraies videos (une mire unie se convertit dix fois trop vite)."""
    os.makedirs(folder, exist_ok=True)
    ffmpeg = find_ffmpeg()
    src = ["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=24:duration=%d,noise=alls=12:allf=t" % CLIP_SECONDS,
           "-f", "lavfi", "-i", "sine=frequency=440:duration=%d" % CLIP_SECONDS]
    clips = {
        "hevc": ("hevc_1080.mkv", ["-c:v", "libx265", "-preset", "ultrafast", "-b:v", "10M",
                                   "-x265-params", "log-level=error", "-pix_fmt", "yuv420p"]),
        "h264x10": ("h264_10bit_1080.mkv", ["-c:v", "libx264", "-preset", "ultrafast", "-b:v", "10M",
                                            "-pix_fmt", "yuv420p10le"]),
        "hevc10": ("hevc_10bit_1080.mkv", ["-c:v", "libx265", "-preset", "ultrafast", "-b:v", "10M",
                                           "-x265-params", "log-level=error", "-pix_fmt", "yuv420p10le"]),
    }
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    for name, codec in clips.values():
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            subprocess.run([ffmpeg, "-hide_banner", "-nostdin", "-loglevel", "error", "-y"] + src + codec +
                           ["-c:a", "aac", "-shortest", path], timeout=900, creationflags=flags)
    return {k: v[0] for k, v in clips.items()}


def fetch(url, timeout=120, tries=4):
    """GET avec nouveaux essais : le serveur Stremio refuse (500) tant qu'une conversion
    precedente occupe son unique emplacement (transcodeConcurrency = 1)."""
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as rsp:
                return rsp.read()
        except urllib.error.HTTPError as e:
            if e.code < 500 or attempt == tries - 1:
                raise
            time.sleep(3 * (attempt + 1))


def convert_speed(stremio, media_url, profile):
    """Conversion par le serveur Stremio -> (facteur temps reel, delai du 1er segment en s)."""
    base = "%s/hlsv2/bench%d/" % (stremio, random.randint(0, 10 ** 9))
    q = "mediaURL=%s&videoCodecs=h264&audioCodecs=aac&maxAudioChannels=2&maxWidth=1280&forceTranscoding=1%s" % (
        urllib.parse.quote(media_url, safe=""), "&profile=" + profile if profile else "")
    try:
        start = time.time()
        fetch(base + "master.m3u8?" + q)
        playlist = fetch(base + "video0.m3u8?" + q).decode("utf-8", "replace")
        segments, durations, d = [], [], None
        for line in playlist.splitlines():
            if line.startswith("#EXTINF:"):
                d = float(line[8:].split(",")[0])
            elif line and not line.startswith("#") and d is not None:
                segments.append(line)
                durations.append(d)
                d = None
        if len(segments) < 2:
            return 0.0, 0.0
        fetch(base + segments[0])
        first = time.time() - start
        t = time.time()
        for s in segments[1:]:
            fetch(base + s)
        return round(sum(durations[1:]) / max(0.01, time.time() - t), 2), round(first, 1)
    except Exception:  # noqa: BLE001 - encodeur inutilisable ou serveur absent
        return 0.0, 0.0


def internet_mbps(url="https://speed.cloudflare.com/__down?bytes=25000000", limit_s=10):
    """Debit de telechargement du PC (Mbit/s), plafonne a limit_s secondes ; 0 si echec."""
    try:
        start = time.time()
        got = 0
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=10) as rsp:
            while time.time() - start < limit_s:
                chunk = rsp.read(262144)
                if not chunk:
                    break
                got += len(chunk)
        return round(got * 8 / 1e6 / max(0.01, time.time() - start), 1)
    except Exception:  # noqa: BLE001 - pas de reseau : inconnu
        return 0.0


def measure(stremio, clip_base_url, profiles, folder, log=print):
    """Mesure complete. clip_base_url : URL (servie par l'agent) du dossier des videos de test."""
    log("  ... mesure des capacites du PC (une fois par semaine, 1 a 3 minutes)")
    clips = make_clips(folder)
    result = {"measuredAt": int(time.time()), "encoders": {}}
    for enc in ["cpu"] + list(profiles):
        values = {}
        for codec, name in clips.items():
            # Adresse unique : le serveur Stremio garde en cache ce qu'il a deja lu ou converti.
            factor, first = 0.0, 0.0
            for attempt in range(2):       # un echec peut venir de l'emplacement encore occupe
                url = "%s%s?run=%d" % (clip_base_url, name, random.randint(0, 10 ** 9))
                factor, first = convert_speed(stremio, url, "" if enc == "cpu" else enc)
                time.sleep(2)              # laisse le serveur liberer son emplacement de conversion
                if factor > 0:
                    break
                time.sleep(5)
            values[codec] = factor
            values[codec + "First"] = first
        if enc != "cpu" and not values.get("hevc"):
            log("  !! encodeur %s annonce par Stremio mais inutilisable : ignore" % enc)
            continue
        # Pas d'encodeur AV1 dans ce ffmpeg pour fabriquer un test : estimation prudente
        # (souvent en 10 bits ; meme famille de cout que le HEVC 10 bits).
        values["av1"] = round(min(values.get("hevc", 0), values.get("hevc10", 0) or values.get("hevc", 0)) * 0.8, 2)
        result["encoders"][enc] = values
        log("  [OK ] Conversion %-10s HEVC : %.1fx, HEVC 10 bits : %.1fx, H.264 10 bits : %.1fx (temps reel)"
            % (enc, values.get("hevc", 0), values.get("hevc10", 0), values.get("h264x10", 0)))
    result["pcInternetMbps"] = internet_mbps()
    log("  [OK ] Internet vers le PC : %.0f Mbit/s" % result["pcInternetMbps"])
    return result


def is_fresh(capacity, profiles):
    if not capacity or time.time() - capacity.get("measuredAt", 0) > MAX_AGE:
        return False
    known = set(capacity.get("encoders", {}))
    return "cpu" in known and all(p in known for p in profiles)
