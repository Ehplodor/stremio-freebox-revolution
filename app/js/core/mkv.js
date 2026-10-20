.pragma library
// Pistes d'un fichier Matroska (MKV) lues dans son en-tete, sans PC : le debut du fichier est
// telecharge par une requete Range et analyse ici (EBML). Sert a afficher les pistes audio et
// sous-titres quand le serveur Stremio du PC n'est pas la pour les analyser.
// Reference : specification Matroska (RFC 9559), identifiants des elements ci-dessous.

const ID = {
    EBML: 0x1A45DFA3, Segment: 0x18538067, SeekHead: 0x114D9B74, Seek: 0x4DBB, SeekID: 0x53AB,
    SeekPosition: 0x53AC, Tracks: 0x1654AE6B, TrackEntry: 0xAE, TrackNumber: 0xD7, TrackType: 0x83,
    CodecID: 0x86, Language: 0x22B59C, LanguageIETF: 0x22B59D, Name: 0x536E, FlagDefault: 0x88,
    FlagForced: 0x55AA, Audio: 0xE1, Channels: 0x9F, Cluster: 0x1F43B675
};

// Entier de taille variable (VINT) a la position pos : { value, length } ; keepMarker pour les ids.
function readVint(bytes, pos, keepMarker) {
    const first = bytes[pos];
    if (first === undefined || first === 0)
        return null;
    let length = 1;
    while (!(first & (0x80 >> (length - 1))))
        length++;
    if (pos + length > bytes.length)
        return null;
    let value = keepMarker ? first : first & (0xFF >> length);
    let allOnes = value === (0xFF >> length);
    for (let i = 1; i < length; i++) {
        value = value * 256 + bytes[pos + i];
        if (bytes[pos + i] !== 0xFF)
            allOnes = false;
    }
    return { value: value, length: length, unknown: !keepMarker && allOnes };
}

function readUint(bytes, start, size) {
    let v = 0;
    for (let i = 0; i < size; i++)
        v = v * 256 + bytes[start + i];
    return v;
}

// UTF-8 -> texte (pas de TextDecoder dans le moteur QML).
function readString(bytes, start, size) {
    let out = "";
    let i = start;
    const end = start + size;
    while (i < end) {
        const c = bytes[i++];
        if (c === 0)
            break;
        if (c < 0x80) {
            out += String.fromCharCode(c);
        } else if (c >= 0xC0 && c < 0xE0 && i < end) {
            out += String.fromCharCode(((c & 0x1F) << 6) | (bytes[i++] & 0x3F));
        } else if (c >= 0xE0 && c < 0xF0 && i + 1 < end) {
            out += String.fromCharCode(((c & 0x0F) << 12) | ((bytes[i] & 0x3F) << 6) | (bytes[i + 1] & 0x3F));
            i += 2;
        } else if (c >= 0xF0 && i + 2 < end) {
            const cp = ((c & 0x07) << 18) | ((bytes[i] & 0x3F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F);
            i += 3;
            const u = cp - 0x10000;
            out += String.fromCharCode(0xD800 + (u >> 10), 0xDC00 + (u & 0x3FF));
        }
    }
    return out;
}

// Elements enfants de [start, end) : [{ id, start (donnees), size, end }]. S'arrete a un element tronque.
function children(bytes, start, end) {
    const out = [];
    let pos = start;
    while (pos < end) {
        const id = readVint(bytes, pos, true);
        if (!id)
            break;
        const size = readVint(bytes, pos + id.length, false);
        if (!size)
            break;
        const dataStart = pos + id.length + size.length;
        const dataEnd = size.unknown ? end : dataStart + size.value;
        out.push({ id: id.value, headerStart: pos, start: dataStart, size: dataEnd - dataStart, end: dataEnd, truncated: dataEnd > bytes.length });
        if (dataEnd > end || size.unknown)
            break;
        pos = dataEnd;
    }
    return out;
}

const TYPES = { 1: "video", 2: "audio", 17: "subtitle" };

function parseTrack(bytes, el) {
    const t = { number: 0, type: "", codec: "", language: "eng", name: "", isDefault: true, forced: false, channels: 0 };
    children(bytes, el.start, el.end).forEach(c => {
        switch (c.id) {
        case ID.TrackNumber: t.number = readUint(bytes, c.start, c.size); break;
        case ID.TrackType: t.type = TYPES[readUint(bytes, c.start, c.size)] || "other"; break;
        case ID.CodecID: t.codec = readString(bytes, c.start, c.size); break;
        case ID.Language: t.language = readString(bytes, c.start, c.size) || t.language; break;
        case ID.LanguageIETF: t.languageIETF = readString(bytes, c.start, c.size); break;
        case ID.Name: t.name = readString(bytes, c.start, c.size); break;
        case ID.FlagDefault: t.isDefault = readUint(bytes, c.start, c.size) === 1; break;
        case ID.FlagForced: t.forced = readUint(bytes, c.start, c.size) === 1; break;
        case ID.Audio:
            children(bytes, c.start, c.end).forEach(a => {
                if (a.id === ID.Channels)
                    t.channels = readUint(bytes, a.start, a.size);
            });
            break;
        }
    });
    if (t.languageIETF && (!t.language || t.language === "und" || t.language === "eng"))
        t.language = t.languageIETF.split("-")[0];
    return t;
}

// Analyse du debut d'un fichier (Uint8Array). Renvoie :
//   { tracks: [...] }        pistes trouvees ;
//   { tracksAt: octet }      les pistes sont plus loin dans le fichier (a telecharger a cet endroit) ;
//   { error: "..." }         pas un MKV, ou en-tete insuffisant.
// offset : position de bytes[0] dans le fichier (second appel, a partir de tracksAt).
function parse(bytes, offset, segmentStart) {
    offset = offset || 0;
    if (!offset) {
        const top = children(bytes, 0, bytes.length);
        if (!top.length || top[0].id !== ID.EBML)
            return { error: "pas un fichier Matroska" };
        const segment = top.find(e => e.id === ID.Segment);
        if (!segment)
            return { error: "segment absent du début du fichier" };
        let tracksAt = 0;
        const items = children(bytes, segment.start, Math.min(segment.end, bytes.length));
        for (let i = 0; i < items.length; i++) {
            const e = items[i];
            if (e.id === ID.Tracks && !e.truncated)
                return { tracks: tracksOf(bytes, e), segmentStart: segment.start };
            if (e.id === ID.Tracks)
                return { tracksAt: offset + e.headerStart, segmentStart: segment.start };
            if (e.id === ID.SeekHead && !e.truncated)
                tracksAt = seekPosition(bytes, e, ID.Tracks, segment.start) || tracksAt;
            if (e.id === ID.Cluster)
                break;
        }
        return tracksAt ? { tracksAt: tracksAt, segmentStart: segment.start } : { error: "pistes introuvables" };
    }
    // Second appel : bytes commence a l'element Tracks.
    const els = children(bytes, 0, bytes.length);
    const tracks = els.find(e => e.id === ID.Tracks && !e.truncated);
    return tracks ? { tracks: tracksOf(bytes, tracks), segmentStart: segmentStart } : { error: "pistes illisibles" };
}

function seekPosition(bytes, seekHead, wantedId, segmentStart) {
    let found = 0;
    children(bytes, seekHead.start, seekHead.end).forEach(seek => {
        if (seek.id !== ID.Seek)
            return;
        let id = 0;
        let position = -1;
        children(bytes, seek.start, seek.end).forEach(c => {
            if (c.id === ID.SeekID)
                id = readUint(bytes, c.start, c.size);
            else if (c.id === ID.SeekPosition)
                position = readUint(bytes, c.start, c.size);
        });
        if (id === wantedId && position >= 0)
            found = segmentStart + position;
    });
    return found;
}

function tracksOf(bytes, tracksEl) {
    return children(bytes, tracksEl.start, tracksEl.end).filter(e => e.id === ID.TrackEntry)
        .map(e => parseTrack(bytes, e));
}

// Pistes audio pour le menu du lecteur : [{ id, label, language, isDefault }] ; la piste lue par
// le Player est la piste par defaut (la premiere marquee « defaut », sinon la premiere).
function audioTracks(tracks, labelOf) {
    const audio = (tracks || []).filter(t => t.type === "audio");
    return audio.map((t, i) => ({
        id: t.number,
        label: labelOf({ language: t.language, title: t.name, codec: codecName(t.codec), channels: t.channels }, i),
        language: t.language,
        isDefault: t.isDefault
    }));
}

function defaultIndex(audio) {
    const i = (audio || []).findIndex(t => t.isDefault);
    return i === -1 ? 0 : i;
}

function codecName(codecId) {
    const m = { "A_AAC": "aac", "A_AC3": "ac3", "A_EAC3": "eac3", "A_DTS": "dts", "A_MPEG/L3": "mp3", "A_OPUS": "opus",
                "A_TRUEHD": "truehd", "A_FLAC": "flac", "A_VORBIS": "vorbis" };
    const key = Object.keys(m).find(k => String(codecId).indexOf(k) === 0);
    return key ? m[key] : String(codecId).replace(/^A_/, "").toLowerCase();
}
