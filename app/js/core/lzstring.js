.pragma library
// Decompression lz-string « EncodedURIComponent » : configuration des addons TMDB (cle API dans
// l'adresse de l'addon). Reprise de decompressFromEncodedURIComponent / _decompress de lz-string
// 1.5.0 (https://github.com/pieroxy/lz-string), Copyright (c) 2013 pieroxy, licence MIT.

const KEYS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$";

// Chaine decompressee, ou null si l'entree n'est pas valide.
function decompressFromEncodedURIComponent(input) {
    if (!input)
        return null;
    input = String(input).replace(/ /g, "+");
    for (let i = 0; i < input.length; i++)
        if (KEYS.indexOf(input.charAt(i)) === -1)
            return null;
    const length = input.length;
    const reset = 32;
    const data = { val: KEYS.indexOf(input.charAt(0)), position: reset, index: 1 };
    const readBits = n => {
        let bits = 0;
        for (let power = 1; power !== 1 << n; power <<= 1) {
            const resb = data.val & data.position;
            data.position >>= 1;
            if (data.position === 0) {
                data.position = reset;
                data.val = KEYS.indexOf(input.charAt(data.index++));
            }
            bits |= (resb > 0 ? 1 : 0) * power;
        }
        return bits;
    };

    const dictionary = [0, 1, 2];
    let enlargeIn = 4, dictSize = 4, numBits = 3;
    let c;
    const first = readBits(2);
    if (first === 0)
        c = String.fromCharCode(readBits(8));
    else if (first === 1)
        c = String.fromCharCode(readBits(16));
    else
        return "";
    dictionary[3] = c;
    let w = c;
    const result = [c];
    while (true) {
        if (data.index > length)
            return "";
        let code = readBits(numBits);
        if (code === 0 || code === 1) {
            dictionary[dictSize++] = String.fromCharCode(readBits(code === 0 ? 8 : 16));
            code = dictSize - 1;
            enlargeIn--;
        } else if (code === 2) {
            return result.join("");
        }
        if (enlargeIn === 0) {
            enlargeIn = Math.pow(2, numBits);
            numBits++;
        }
        let entry;
        if (dictionary[code])
            entry = dictionary[code];
        else if (code === dictSize)
            entry = w + w.charAt(0);
        else
            return null;
        result.push(entry);
        dictionary[dictSize++] = w + entry.charAt(0);
        enlargeIn--;
        w = entry;
        if (enlargeIn === 0) {
            enlargeIn = Math.pow(2, numBits);
            numBits++;
        }
    }
}
