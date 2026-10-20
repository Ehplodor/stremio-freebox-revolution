.pragma library
// Prechargement par le PC : combien attendre avant de lancer, quand suspendre la lecture.
// Fonctions pures (testees sous Node). Unites : octets, millisecondes, octets/s.

const MIN_START_S = 12;          // avance minimale au demarrage (la conversion lit un peu en avance)
const STALL_S = 6;               // en dessous : pause automatique (au lieu de saccades)
const RESUME_S = 30;             // apres une pause automatique : reprise avec 30 s d'avance au moins
const MAX_WAIT_S = 20 * 60;      // au-dela, on propose de lancer quand meme
const FAR_AHEAD_BYTES = 48 * 1024 * 1024;   // comme l'agent (prefetch.FAR_AHEAD) : relais direct

// Debit de la video (octets/s) : taille / duree.
function bytesPerSecond(total, durationMs) {
    return total > 0 && durationMs > 0 ? total / (durationMs / 1000) : 0;
}

// Octet correspondant a une position (approximation proportionnelle).
function byteAt(total, durationMs, positionMs) {
    return durationMs > 0 ? Math.floor(total * Math.min(1, Math.max(0, positionMs / durationMs))) : 0;
}

// Avance prechargee devant la position (secondes de video) ; Infinity si tout est la.
function aheadSeconds(st, durationMs, positionMs) {
    if (st.done)
        return Infinity;
    const bps = bytesPerSecond(st.total, durationMs);
    if (!bps)
        return 0;
    const pos = byteAt(st.total, durationMs, positionMs);
    if (pos < st.base)
        return 0;                      // avant la partie prechargee (saut arriere) : relais direct
    return Math.max(0, (st.end - pos) / bps);
}

// Avance a constituer avant de lancer (secondes) : si le telechargement est plus lent que la
// video, il faut assez d'avance pour ne jamais la rattraper avant la fin.
function startTarget(st, durationMs, positionMs) {
    const bps = bytesPerSecond(st.total, durationMs);
    const remaining = Math.max(0, (durationMs - positionMs) / 1000);
    if (!bps || !st.rateBps)
        return Math.min(MIN_START_S, remaining);
    const ratio = st.rateBps / bps;
    if (ratio >= 1.2)
        return Math.min(MIN_START_S, remaining);
    // avance a = duree restante x (1 - vitesse de telechargement / debit de la video)
    return Math.min(remaining, MIN_START_S + remaining * (1 - ratio));
}

// Etat d'attente a afficher : { ready, percent, etaS, aheadS, targetS, tooLong }.
function progress(st, durationMs, positionMs, targetS) {
    const ahead = aheadSeconds(st, durationMs, positionMs);
    if (ahead >= targetS || st.done)
        return { ready: true, percent: 100, etaS: 0, aheadS: ahead, targetS: targetS, tooLong: false };
    const bps = bytesPerSecond(st.total, durationMs);
    const missing = (targetS - ahead) * bps;
    // Pendant l'attente la video ne defile pas : seule la vitesse de telechargement compte.
    const eta = st.rateBps > 0 ? missing / st.rateBps : -1;
    return {
        ready: false,
        percent: Math.max(0, Math.min(99, Math.round(100 * ahead / Math.max(1, targetS)))),
        etaS: eta < 0 ? -1 : Math.ceil(eta),
        aheadS: ahead,
        targetS: targetS,
        tooLong: eta > MAX_WAIT_S
    };
}

// Pendant la lecture : faut-il suspendre (avance presque epuisee) ?
// Hors de la partie prechargee (saut arriere, ou loin devant) l'agent relaie directement la
// source : attendre ne servirait a rien.
function shouldStall(st, durationMs, positionMs) {
    if (st.done || st.error || !st.total)
        return false;
    const pos = byteAt(st.total, durationMs, positionMs);
    if (pos < st.base || pos > st.end + FAR_AHEAD_BYTES)
        return false;
    return aheadSeconds(st, durationMs, positionMs) < STALL_S;
}

// Apres une pause automatique : avance a retrouver avant de reprendre.
function resumeTarget(st, durationMs, positionMs) {
    return Math.max(RESUME_S, startTarget(st, durationMs, positionMs));
}

// Objectif par defaut quand la vitesse n'a pas encore pu etre mesuree.
function defaultTarget(mode) {
    return mode === "stall" ? RESUME_S : MIN_START_S;
}

function formatEta(s) {
    if (s < 0)
        return "calcul…";
    if (s < 60)
        return s + " s";
    return Math.floor(s / 60) + " min " + ("0" + (s % 60)).slice(-2);
}
